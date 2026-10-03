# 移行計画：CET Lua 周期処理 → redscript / RED4ext ワーカースレッド

作成日: 2026-10-03 / 対象: v3.3.1 以降
対象処理: `Core:CheckAllEvents()` / `Core:GetActions()` / `Engine:Update()`（CET `onUpdate` 経由）
関連: `PERFORMANCE_FIX_PLAN.md`（fix 1〜30: 1回あたりコスト削減）、`PERF_PLAN_event_driven.md`（発火削減）

---

## 0. 前提の検証：スレッドモデルの事実確認（重要）

ご要望は「重い処理を redscript に移行してワーカースレッドで実行」だが、
**redscript はワーカースレッドではない**。移行の前に3レイヤーのスレッドモデルを確定させる。

| レイヤー | 実行スレッド | 特徴 |
|---|---|---|
| CET Lua (`onUpdate`/Cron) | **ゲームメインスレッド** | 重い主因は中身より **Lua→C# ラッパ往復（マ샐リング）**。本MOD実測: 素の getter 1回 0.5〜2µs + 50〜150B alloc、同期レイキャスト 10〜80µs |
| redscript (`.reds`) | **ゲームのスレッド**（フックされた関数を呼んだスレッド。通常はメイン/ロジックスレッド） | ゲームスクリプトVMにネイティブ bytecode として直接統合。**マ샐リングゼロ**で同一呼び出しは Lua より 1桁程度安い。ただし**ワーカースレッドを spawn する言語機構は存在しない** |
| RED4ext C++ プラグイン | **任意（ワーカースレッド可）** | `std::thread` を起こせる。ただし **ゲームAPI・エンティティ・物理・UI への呼び出しはワーカースレッドから unsafe**。純計算のみ offload 可。結果はロックフリーキューでメインスレッドに返す |

### 帰結（本計画の骨格）

1. **`CheckAllEvents` / `GetActions` / `Engine:Update` の「移行先」は redscript だが、目的はワーカースレッド化ではなく「マ샐リングコストの消去 + ネイティブ状態機械」である。** 移動後も実行はゲームスレッド上だが、CET 比で呼び出しコストが 1/5〜1/10 になり、Lua GC プレッシャ（クロージャ/table/文字列）が消える。
2. **本当にワーカースレッドへ出せるのは「純計算」だけ** — A* ルート探索、障害物マップのチャンク変換・照合など、ゲーム API を触らない部分。これは RED4ext DLL 側の仕事になる。
3. **同期レイキャスト（`SyncRaycastByQueryFilter`）は redscript に移ってもワーカースレッド化できない。** 物理クエリ自体はエンジン側同期処理であり、効くのは既に実装済みの周期間引き（fix 28）だけ。ここを誤解したまま移行しても R コストは減らない。

> 参考: REDengine4 の job system（GDC 2022 "The Job System in Cyberpunk 2077"）はエンジン内部の並列化であり、
> MOD からスクリプトでワーカースレッドを使う口は redscript には開放されていない。
> 外部から使えるのは RED4ext 経由の C++ スレッドのみで、そこは「ゲーム状態を読まない計算」の隔離場所と考える。

---

## 1. 現状のコスト構造（移行で何が消えるか）

`PERF_PLAN_event_driven.md` の A〜D 群（発火削減）は実装済み。残っているのは「発火した回の 1 回コスト」。

### 1 tick あたりの C# 往復（situation_cost_test 実測、C群後）

| 状況 | CheckAllEvents | GetActions | 合計 |
|---|---|---|---|
| Waiting | 2.0/tick | 7.0/tick | ~9.9 |
| InVehicle（手動） | — | — | ~12.6 |

`Engine:Update` はこれとは別に `onUpdate` で毎フレーム走り、
`GetPhysicsState` / `GetDirectionAndAngularVelocity` / `AddForce` 等で 4〜8 往復 + `Vector3.new` alloc。

### 移行で消えるコスト / 残るコスト

| コスト種別 | 例 | redscript 移行後 |
|---|---|---|
| `T` 素の getter/setter 往復 | `IsPlayerMounted` `GetDoorState` `GetPlayer` | **ほぼ消える**（VM 内直接呼び出し。同一 bytecode 世界になる） |
| `A` Lua アロケーション | クロージャ、`{action,1}` table、文字列連結 | **消える**（redscript は値型/管理配列。CET Lua GC なし） |
| `W` widget 書き込み | `SetText` `EvaluateRPMMeterWidget` | 呼び出し側コストは消えるが **widget dirty→再レンダリング自体は残る**（表示値エッジトリガー fix 29 が効いている前提） |
| `R` 同期レイキャスト | `SyncRaycastByQueryFilter` | **残る**（エンジン同期処理）。周期間引きが唯一の対策 |
| 物理適用 `AddForce` 等 | FlyAVSystem（RED4ext native） | 呼び出し側コスト消滅。**DLL はそのまま流用可**（redscript から native 型は直接 import できる） |

**要点: `FlyAVSystem` は既に RED4ext native 型である。** 現状 CET Lua → native のマ샐リングを経ているが、
redscript からは同じ native 型をマ샐リングなしで呼べる。`Engine:Update` の移行は DLL 変更ゼロで成立する。

---

## 2. 移行先の分類（何をどこへ）

### 2.1 redscript へ移す（メインスレッド上だが安くなる）

| 現 CET 処理 | 移行後 | 根拠 |
|---|---|---|
| `Event:CheckAllEvents()` の**状況機械**（Idle/Normal/Landing/Waiting/InVehicle/TalkingOff の遷移表 + 各 Check*） | `DAVSituationService`（ScriptableService 相当。`GameInstance` に紐づくシングルトン）が状況状態を所有し、tick ごとに各チェックを redscript で実行 | 全 Check* の読み取り先（mount 状態・ドア・エンジン・destroyed・距離）はゲーム API そのもの。VM 内化で T 往復が実質タダになる。遷移表は純 Lua ロジックなので移行は機械的 |
| `Core:OperateAerialVehicle()` 以降の**操作適用**（`AV:Operate` → `Engine` 加算/速度変換 → `FlyAVSystem`） | `DAVFlightController`（redscript）が `FlyAVSystem` を直接呼ぶ | 入力→物理の往復路が Lua を経由しなくなる。`Vector3` が redscript 値型になり alloc 消滅 |
| `Engine:Update()` の**制御ロジック**（control_type 分岐、torque 計算、RPM ランプ） | 同上 `DAVFlightController` の tick | DLL 無変更で移行可能。`is_finished_init` / entity ゲートも redscript 側に移植 |
| `IsInMenuOrPopupOrPhoto()` 等の**メニュー状態判定** | redscript 側で game event（`MenuClose`/`PopupClose`/`PhotoModeClose`）を受け取りフラグ保持 | 既に CET 側も observe しているイベント群。redscript の `Observe` で同等 |

### 2.2 CET Lua に残す（移行しない / 移行できない）

| 処理 | 残す理由 |
|---|---|
| 入力捕捉（`Input/Key`/`Input/Axis` プロキシ、keybind 変換、hold 判定） | CET の入力系が唯一の口。ただし**変換後のアクションは redscript へ push するだけ**にし、`GetActions` のドレイン＋適用を redscript 側に渡す |
| HUD widget 操作（`hud.lua` 全体） | ink widget 操作は CET からでも redscript からでもコストは同じ（書き込み先が同じ）。移行の便益が薄く、UI 実装は redscript popup 側と分散して既にredscript/ink 側にある。**現状維持** |
| 設定読み書き（`user_setting_v3.json`）、言語テーブル | CET のファイル I/O が楽。起動時に一度 redscript へ同期すればよい |
| LTBF / Audioware / NativeSettings 互換ハブ | CET `GetMod()` が前提の相互運用。移行対象外 |
| オブstacle map の**ファイル I/O・チャンク読み** | CET 側維持（計算は §2.3 へ） |

### 2.3 RED4ext ワーカースレッドへ出せるもの（第2フェーズ・任意）

| 処理 | 内容 | 制約 |
|---|---|---|
| A* ルート探索（`navigation.lua` の計算部） | 現在 Lua で実行。ループ自体は搭乗時オンデマンドだが、長距離ルートで 1 回が重い。**C++ 側でワーカースレッド実行 → 結果をロックフリーキューでメインへ返す** | 入力（障害物グリッド・目的地）をスナップショットして渡す。ゲーム API を呼ばない純計算にする |
| 障害物マップのチャンク変換・照合 | bin 読み込み後の変換を C++ で | 同上 |
| 同期レイキャスト | **出せない**（エンジン同期 API） | §0 の帰結 3 |

---

## 3. アーキテクチャ

```
┌─ CET Lua（薄い残骸）────────────────────────────┐
│ 入力捕捉 → ActionCommand を push                  │
│ 設定/言語/互換MODハブ                            │
│ HUD widget 書き込み（redscript 通知を受けて）      │
└──────────────┬──────────────────────────────────┘
       Command: CET→redscript（§4.1）
       Notify : redscript→CET（§4.2）
┌──────────────▼──────────────────────────────────┐
│ redscript: DAVSituationService（状況機械）         │
│   - current_situation 所有・遷移表               │
│   - Check* 群（VM 内直接読み、マ샐リングなし）     │
│   - 状況変化・HUD値・イベントを CET へ通知        │
│ redscript: DAVFlightController                   │
│   - Engine:Update 相当（control_type 分岐）       │
│   - FlyAVSystem を直接呼ぶ（DLL 無変更）          │
└──────────────┬──────────────────────────────────┘
               │ native 呼び出し（マ샐リングなし）
┌──────────────▼──────────────────────────────────┐
│ RED4ext DLL: FlyAVSystem（現状維持）              │
│  [Phase 2] DAVComputeWorker: A*/障害物変換        │
│    ワーカースレッド + lock-free queue             │
└──────────────────────────────────────────────────┘
```

### 3.1 状況機械の再設計（「各イベントフラグを確認して状態遷移」の解消）

現状の `CheckAllEvents` は「毎 tick 全フラグをポーリングして `SetSituation` を引く」構造。
移行と同時にこれを **イベント優先 + 低速ハートビート** に作り替える:

- **状況状態は redscript の `DAVSituationService` が単一所有**。CET は読み取り専用（通知で追従）。
  二重所有（CET の `current_situation` と redscript の状況）は作らない — 同期バグの温床。
- 遷移の駆動は既存のゲームイベントを優先:
  - 搭乗/降車: `VehicleTransition` / mount 系イベント（CET 側で既にフック実績あり）
  - 破壊: `Entity/AfterDetached` / destroyed 通知
  - メニュー: `MenuClose`/`PopupClose`/`PhotoModeClose`
- ポーリングは「イベントで取れない残件」だけを残す（降車検知の 20Hz 保険など、
  C 群で確立した `DueNow` 型を redscript 側にも同型で実装）。
- 各 Check は「読み取り → 差分があれば redscript 内イベント（`QueueEvent`）発火」に変え、
  状態遷移は発火されたイベントのハンドラだけで行う。
  **フラグ確認のループ → 差分イベントの購読** に反転させる。

---

## 4. 通信（IPC）設計

CET ↔ redscript の往復路。どちらもゲーム内で共有できるものを使う。

### 4.1 CET → redscript（コマンド）
- **方案A（推奨）: CET から redscript 関数を直接呼ぶ。**
  CET はゲームの任意スクリプト関数を呼べる（`Game.GetSystemByName(...)` / `new` + メソッド呼び）。
  `DAVSituationService:PushAction(actionId, value)` を呼ぶだけ。片道マ샐リング 1 回。
- 方案B: TweakDB を共有ブラックボードに（`SetFlat`/`GetFlat`）。型が素朴で遅い。A で足りるため不採用。

### 4.2 redscript → CET（通知）
- **方案A（推奨）: CallbackSystem。**
  本MODは既に `Game.GetCallbackSystem():RegisterCallback('Input/Key', ...)` を使っているのと同じ口で、
  redscript 側が `RegisterCallback` 用のコールバックを発行 → CET `NewProxy` が受ける。
  通知内容は `Int32`/`Float` の小さいペイロード（situation id、HUD 値、door state 等）に限定し、
  文字列・配列を跨がせない（跨ぐとマ샐リング復活）。
- 方案B: 専用 CName イベント + CET `Observe`。発火頻度が低い通知（状況変化のみ）に併用可。

### 4.3 同期規則
- **全状態の正本は redscript 側**。CET 側の状況・HUD 値はすべて通知由来のキャッシュ。
- CET 側キャッシュが stale でも「入力→PushAction」は常に正本へ届くので、取りこぼしは通知側だけ直す。
- セーブ/ロード（`SessionStart`）時は必ずフル再同期（situation=Idle からの再構築）。

---

## 5. フェーズ計画

### Phase 1: 計装と赤点確認（CET 内、1 ウィーク）
1. 現状の 1 秒あたり「C# 往復回数・Lua alloc bytes」を状況別に再実測
   （既存 profprobe 系は 47f5716 で削除済みなので、最小の再計装を一時追加）。
2. 「redscript 移行で消える往復（T/A）」と「残る往復（R/W）」の内訳表を実データで確定。
   → **移行効果の見積もりを数字で持つ。効果が薄いなら Phase 2 以降をやらない判断も valid。**

### Phase 2: `Engine:Update` の redscript 化（先行・最小リスク）
- 理由: 依存が最も少ない（`FlyAVSystem` native + control_type + 設定値）。
  移行先 `DAVFlightController` は「毎フレーム呼ばれる redscript 関数」でよく、
  状況機械の引っ越しを待たない。
- 実装:
  1. `r6/scripts/DriveAerialVehicle/DAVFlightController.reds` 新設。
     `FlyAVSystem` を import（RED4ext native は redscript から import 可 — 本MOD DLL が既に
     `RegisterFlyAVSystem` で登録済み）。
  2. control_type 分岐・torque 計算・RPM ランプを移植。dt は CET から PushAction で渡す
     （または redscript 側の tick 源へ）。
  3. CET `init.lua` の `Engine:Update(delta)` 呼び出しを `PushAction(ENGINE_TICK, delta)` に置換。
  4. 比較計測: 同一ルート手動飛行でフレームタイム比較。
- 完了条件: 飛行挙動が従来と体感同一、CET 側 onUpdate の物理関連往復が 0。

### Phase 3: 状況機械（CheckAllEvents）の redscript 化（本命）
- `DAVSituationService` 実装（§3.1 のイベント優先設計）。
- 移行順序は「状況ごと」に段階的に: Normal → Waiting → Landing/TalkingOff → InVehicle。
  各状況の移行完了まで、未移行状況は CET 側 `CheckAllEvents` が面倒を見る
  （**ハイブリッド期間の設計**: 状況が redscript 所有に移った瞬間から CET 側は該当分岐を停止）。
- CET 側の `Event` クラスは「通知の受け皿 + HUD 反映」に縮退。
- テスト: 既存 loop_gate / demand_driven スイートの redscript 版 +
  「CET 側 Check 呼び出し回数 0」を assert。

### Phase 4: GetActions の再配置
- 入力捕捉は CET 残留（変更なし）。変換後アクションを `PushAction` で redscript へ。
- `Core:GetActions()` のドレイン・`OperateAerialVehicle` の分岐が redscript 側に移動し、
  CET 側は「queue に積むだけ」になる（待機時コスト ~0）。
- Waiting の idle-gravity レイキャスト（仕様機能「待機中の降下」）は redscript 側の
  低速スロットへ移動。R 自体は残るが周期は現状維持。

### Phase 5（任意）: RED4ext ワーカースレッド
- A* 探索を C++ へ: `DAVComputeWorker` に `std::thread` + 結果キュー。
  入力スナップショット（障害物グリッド参照、目的地）を C++ 側で保持し、
  完了時にメインスレッドで結果を redscript/CET が拾う。
- 効果: 長距離 autopilot 設定時のメインスレッド停止が消える。
- 制約: ワーカースレッドからゲーム API 呼び出し厳禁（クラッシュ/データ競合）。
  純計算化のリファクタが前提。工数が最大なので Phase 1 の数字で要否を判断。

---

## 6. リスクと対策

| リスク | 内容 | 対策 |
|---|---|---|
| **誤解の残留** | 「redscript = ワーカースレッド」の期待で移行すると「メインスレッド負荷は減ったがゼロではない」結果にガッカリする | §0 を README/リリースノートにも明記。期待値は「コスト 1/5〜1/10」で設定 |
| redscript の tick 源 | redscript には CET の `onUpdate` に相当する常時 tick が無い。`DelaySystem` はフレーム依存で高頻度に不向き | フックベース: `inkGameController` 系または `PlayerPuppet` の update 経関数にフックを当てて tick を得る。Phase 2 で実証する（**未検証事項の筆頭**） |
| ハイブリッド期間の二重所有 | 状況が CET と redscript に分かれる期間の同期バグ | 正本を redscript に一本化（§4.3）。移行単位で CET 側分岐を即停止 |
| 既存 DLL との互換 | `FlyAVSystem` の native 登録は redscript からも見える前提。ゲームバージョン依存 | Phase 2 で最初に実証。見えない場合は DLL に redscript 向け薄いラッパー登録を追加（小改修） |
| セーブ互換 | `DAV_IN_AV` セーブロック、garage 設定の永続化経路 | 永続化は CET 側維持（Phase 2〜4 で動かさない）。SessionStart フル再同期 |
| 同期レイキャストの誤解 | R は移行で減らない | §0 帰結3。周期間引き（fix 28）が効いた状態が前提 |
| 移行コスト | 約 15,000 行の Lua のうち移行対象は core/event/engine の ~3,900 行相当 | フェーズごとに revert 可能に。各 Phase の完了条件を計測で持つ |

---

## 7. 検証計画

1. **Phase 1 の計装データ**を移行前後で同一シナリオ比較（同一セーブ、同一ルート、60fps 固定条件）。
   - 指標: CET onUpdate 内 C# 往復/秒、Lua alloc KB/秒、フレームタイム p50/p95/p99
2. 各 Phase の回帰: 既存テストスイート（situation / enter_exit / meter_cadence / loop_gate / demand_driven）の
   redscript 版 + 「CET 側該当呼び出し 0 回」アサーション。
3. 長時間耐久: Waiting 1h / InVehicle 巡航 30min で GC・リーク・stale 通知の確認。
4. 互換: LTBF / Audioware / NativeSettings / VehicleDurabilityDisplay の各構成で起動確認。

---

## 8. 判断のまとめ（先に結論）

- **redscript 移行は「正しいが、効能はワーカースレッド化ではなくマ샐リング消去」。**
  CheckAllEvents / GetActions / Engine:Update の T・A コストはほぼ消え、
  R（同期レイキャスト）と W（widget 再レンダリング）は残る。
- **ワーカースレッドが本当に要るのは A* 純計算だけ**で、それは RED4ext C++ の仕事（Phase 5）。
- 既存の発火削減（A〜D 群）が既にWaiting 85%減を達成済みなので、
  **Phase 1 の実測で「残コストが redscript 移行に見合うか」を先に確認してから本移行に入る**こと。
  移行しない判断（現状維持 + 既存間引きの調整）も選択肢として残す。
