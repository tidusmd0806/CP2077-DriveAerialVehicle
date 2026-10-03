# 移行計画 v2：onUpdate 周期処理のイベント駆動化 + native 化

作成日: 2026-10-03 / 対象: v3.3.1 以降
対象処理: `Core:CheckAllEvents()` / `Core:GetActions()` / `Engine:Update()`（CET `onUpdate`/Cron 経由）
関連: `PERFORMANCE_FIX_PLAN.md`（fix 1〜30: 1回あたりコスト削減）、`PERF_PLAN_event_driven.md`（発火削減）
本ファイルは v1（`PERF_PLAN_redscript_migration.md`）の改訂。**v2 が正、v1 はスレッドモデル調査記録として残す。**

---

## 0. 意図の明確化（v1 からの改訂点）

v1 は「ワーカースレッド」の語に引きずられて redscript 移行が主眼だったが、本来の意図は以下である：

> **CET の `onUpdate`（＝ゲームメインスレッド）で重い周期処理を回すのをやめる。**
> ロジックをゲーム native 側（RED4ext native / redscript VM）に載せ、
> ゲームのイベントキュー／コールバックで**イベントドリブン**に駆動する。
> CET の Cron を全否定はしない。redscript に必ず移行する必要もなく、
> CET の `NewProxy` + `Game.GetCallbackSystem()` で足りるならそれでもよい。

この意図は**成立する**。成立条件と限界を以下に確定させる。

### 0.1 費用モデルの転換

| モデル | コスト |
|---|---|
| 現状（周期駆動） | 発火回数 × 1回あたり C# 往復。Waiting でも ~10 往復/tick、InVehicle ~12.6 往復/tick が**常に**走る |
| イベント駆動 | **イベント発火回数 × 1往復**。アイドル時は 0。カクつきへの寄与は「イベントが実際に起きた瞬間」だけ |

重要: コールバックは**ディスパッチ元（ゲーム）スレッドで同期実行**される。
「メインスレッドで実行されない」のではなく「**メインスレッドで走る回数が桁で消える**」のが効能。
したがってハンドラ自体は軽く保ち、重い仕事はキューに逃がす原則は残る。

### 0.2 駆動機構の選択肢（すべて「ゲームのイベント経路」）

| 機構 | 実体 | 本MODでの実績 | 用途 |
|---|---|---|---|
| CET `Observe` / `Override` | ゲーム**スクリプト関数**のフック。関数が呼ばれた瞬間に割込む | `VehicleTransition`、`GetHasAnyDoorOpen`、`SessionStart`、`MenuClose` 群で使用中 | 状態変化をスクリプト層で検知 |
| CET `NewProxy` + `CallbackSystem:RegisterCallback` | ゲーム **C++ 側 CallbackSystem** の購読。`Input/Key`/`Input/Axis` がこれ | init.lua 346–418 で入力の受け口に使用中 | C++ ディスパッチのイベント（エンティティ、入力等） |
| redscript `RegisterCallback` / `QueueEvent` | VM 内からゲームイベントを発行・購読 | 未使用 | **ゲームが外に露出していないシグナルを CET へ橋渡しする**ときだけ必要 |

**結論: イベント駆動の本体は CET だけで実装可能。**
本MODは既に `NewProxy` + `CallbackSystem` を入力系で実績運用しており、同じ口の状態版を展開する形になる。
redscript は「CET から見えしくないが redscript 層なら検知できる信号」の橋渡し役としてのみ出番がある（任意）。

---

## 1. イベント棚卸し：各 Check がイベント化できるか

`CheckAllEvents` の構成要素を「検知源」で分類する。ここが計画の実質。

### 1.1 イベント化可能（ゲーム側に検知源あり）

| 現 Check | 検知源 | 現状の本MOD | 移行後 |
|---|---|---|---|
| `CheckInAV`（搭乗検知） | `VehicleTransition` / mount 系イベント | `VehicleTransition` フック実績あり | 購読して `SetSituation(InVehicle)`。ポーリングは 2Hz 保険のみ |
| 降車 | `IsUnmountDirectionClosest` フック → `Unmount()` | **イベント化済み** | 据え置き |
| `CheckDestroyed` | Entity ライフサイクル／destroyed 通知 | 10Hz ポーリング | 購読に変更 |
| メニュー/ポップアップ/フォト | `MenuClose`/`PopupClose`/`PhotoModeClose` | 既に observe 済み | 購読のみ。判定の定期読み廃止 |
| HP 表示 | `ReactToHPChange` observer | 使用中 | 据え置き（このパターンの横展開） |
| 速度/RPM | ゲーム側に `OnSpeedValueChanged`/`OnRpmValueChanged` 相当の change event あり（fix 計画 #12 で確認済み） | 未使用（毎 tick 読み） | 購読して HUD 更新。読み捨てポーリング廃止 |
| `CheckDoor` | `GetHasAnyDoorOpen` Override が**読み取り経路を握っている** | Override 済みだがポーリング併用 | Override 内で last state を記録し、**差分時のみ**後処理。`CheckDoor` の定期読み廃止 |
| `CheckEngine` | エンジン状態変化イベント（要確認） | 5Hz ポーリング | 取れれば購読、取れなければ 5Hz 維持（既に安い） |

### 1.2 イベントが存在しない（縮減不能ポーリング）

| 現 Check | 理由 | 打ち手 |
|---|---|---|
| `CheckHeight`（同期レイキャスト） | 地面までの距離に「変化を配る側」がいない | fix 28 の予測間引きが最善（駐機中 4本/s）。**これ以上は native 化（§3.2）まで不可能** |
| `CheckDistance` | 同上 | 0.5s 間引き維持 |
| `CheckInEntryArea` | 同上 | 20Hz キャッシュ維持 |

### 1.3 疑似ポーリング（読み元が Lua 状態）

`CheckAutoModeChange` / `CheckFailAutoPilot` / `CheckPerspective` —
状態変化は必ず MOD 側で起きているのだから、**変更箇所で直接呼ぶ**だけで消せる。
イベント機構すら不要。

### 1.4 Autopilot 群（`navigation.lua`）— 専用の周期ループ、稼働中が最重量

`CheckAllEvents` の外に **Autopilot 自身の Cron ループ**がある。v2 計画で明記が必要だった部分。

**実態（navigation.lua 確認済み）:**

| 要素 | 実体 | 周期 |
|---|---|---|
| Autopilot 本体ループ | `AutoPilot()`（3233）が起動する `Cron.Every(DAV.time_resolution)`。**`is_auto_pilot` が false になれば自走停止** | 100Hz（稼働中のみ） |
| A* ルート計画 | `route_plan_job` + `StepRoutePlanJob`（1999）で**既にジョブ化・予算制約済み**。1200 iter/tick（離陸時 4000）を毎 tick 刻んで完了したら adopt | 稼働中 100Hz |
| ルート追従・局所回避 | 毎 tick `GetPosition` + 回避レイキャスト + exception area 判定。phase 機械（start_local / astar / astar_local_avoidance / final_local） | 稼働中 100Hz |
| 回廊チャンク配信 | `StartRouteCorridorPreload`（1304）— 離陸前にルートが_cross_るチャンクを 8ms/tick 予算でストリーム | 離陸時のみ |
| 障害物学習フラッシュ | `MaintainObstacleMapCache`（B群で park 済み） | 学習時のみ |
| Autopilot UI | AutopilotMenu（redscript/ink popup）。RPM ゲージは進行度変換、速度/RPM change event で駆動化可能 | イベント |

**扱い（v2 アーキテクチャでの位置づけ）:**

Autopilot は「**要るときだけ走る周期処理**」であり、イベント駆動の方向性とは矛盾しない
（`ToggleAutopilot` イベントで起動、`InterruptAutoPilot`/降車で停止 — これは既に正しい）。
問題は**稼働中の 1 回コスト**で、3 分割して行き先が決まる:

| 構成要素 | 性質 | 行き先 |
|---|---|---|
| **A* 計画（`StepRoutePlanJob` 内部）** | 障害物グリッドに対する**純計算**（ゲーム API を触らない — 入力はセル集合のスナップショットで渡せる）。既にジョブ化済みで移行口がclean | **Phase D: C++ ワーカースレッド**。Lua は job 生成と結果 adopt だけ。1200 iter/tick の Lua 実行が消え、予算も撤廃できる（ワーカならフレームを圧迫しない）。CET 側は完了イベントを受けるだけ |
| **ルート追従・局所回避・phase 機械** | 毎 tick の機体位置＋回避レイキャスト＋加力変換。**飛行制御と同一カテゴリ（毎フレーム必要）** | **Phase B: DLL の `DAVFlightController` に同梱**。CET は目的地・speed・phase 遷移通知を push。追従誤差計算と force 算出が native 化し、Lua の 100Hz ループは消える |
| **回廊チャンク配信・学習フラッシュ** | ファイル I/O＋パース。I/O は CET が持つ方が楽（CET のファイル API・設定・Language 周りと同居） | **CET 残留**。パース（`ParseChunkIncremental`）だけ Phase D で C++ に出す選択肢あり |
| **Autopilot UI・お気に入り・目的地選択** | redscript/ink 側で完結済み。HUD 進行度は速度/RPM イベントで駆動 | **現状維持**（Phase A の速度/RPM 購読がそのまま効く） |

**Phase A での Autopilot 関連の即効策（CET のみ）:**
- `CheckFailAutoPilot` / `CheckAutoModeChange` の疑似ポーリング消去（§1.3）→
  `SuccessAutoPilot` / `InterruptAutoPilot` / `ToggleAutoMode` の**変更箇所で直接** HUD・イベント後処理を呼ぶ
- Autopilot 起動/停止を `SetSituation` と同様に**明示イベント化**（既に `ToggleAutopilot` キー由来なので、
  Cron ループの「割り込み検知」も `is_auto_pilot` 反転箇所からの直接呼びに置換し、
  ループ内の自己終了判定ポーリングを削減）
- Autopilot 稼働中の `IsInMenuOrPopupOrPhoto()` 毎 tick 読み → メニュー open/close 購読フラグで無償化

**実装結果（2026-10-03 実機検証込み）:**
- `CheckAutoModeChange` / `CheckFailAutoPilot` は削除済み。`SuccessAutoPilot` は
  **0.5s 遅延**で `NotifyAutoModeEnded`（ChangeVelocity 停止が物理に反映されてから
  AddForce 復帰しないと慣性で激突するため。遅延量は調整可能）。
  `InterruptAutoPilot` は即時（ユーザー嗜好）。
- `CheckPerspective` は削除済み。**NativeDB の `hudCarController.OnCameraModeChanged(mode: Bool)`
  を Override して実装**（ゲーム自身のカメラモード変更イベント）。
  wrappedMethod 実行後（＝ゲームの hide/show 処理後）に `mode == true`（FPP）なら
  `ShowRequest()` で再表示するため、遅延レースが存在しない。
  ※ 当初の「CET 側で Cron.After / 再強制ウィンドウ」方式は、ゲーム側の非同期 hide に
     勝てず（連続切替で表示されない）不採用。イベント順序に乗せるのが正解だった。

**効果の見積り（Autopilot 巡航中）:**
- Phase A 後: 100Hz ループは残るが 1 回あたり往復が減少（メニュー判定・HUD 読みが消える）
- Phase B 後: ルート追従の Lua 実行が消え、CET 側は push のみ
- Phase D 後: A* の 1200 iter/tick が消え、長距離計画のフレーム圧迫がゼロになる
  （現状は予算制約で抑えているが、それでも 100Hz × 1200 iter の Lua 実行は巡航中の主コスト）

---

## 2. 目標アーキテクチャ

```
┌─ ゲーム C++ / スクリプトVM ──────────────────────────┐
│  CallbackSystem（入力・エンティティ・遷移イベント）      │
│  物理シーン（vehiclePhysicsData_* フック点）            │
└──────┬──────────────────────────┬────────────────────┘
       │ 同期ディスパッチ（発火時のみ）  │ 毎フレーム（native 内）
┌──────▼───────────────┐   ┌──────▼─────────────────────┐
│ CET Lua（NewProxy 群） │   │ RED4ext DLL（本命）          │
│  - 入力捕捉・keybind   │   │  DAVFlightController:        │
│  - 状態イベント購読    │   │   飛行制御状態を native 保持   │
│    (mount/destroy/    │   │   毎フレーム force/torque 適用 │
│     menu/HP/speed/    │   │   CET から push された入力のみ  │
│     door差分)         │   │   で駆動                      │
│  - 縮減不能ポーリング   │   └────────────────────────────┘
│    (height/dist/entry) │
│  - HUD/設定/互換ハブ   │
└──────────────────────┘
```

- **CET Cron の役割**: 縮減不能ポーリング（height/dist/entry）と、イベント保険の低速ハートビートのみ。
  主ループ 100Hz の `CheckAllEvents`/`GetActions` は消える。
- **コールバック原則**: ハンドラは「読む・判断する・キューに積む」まで。
  重い後処理（HUD 再構成、セーブロック等）は次の CET tick で flush。
- **状況の正本**: 移行後も CET Lua が保持してよい（redscript に移さない）。
  変えるのは「誰が毎 tick 確認するか」→「イベントが教えてくれる」であり、
  所有場所を移す必要はない。v1 の「正本 redscript 化」は不要になった。

---

## 3. 唯一の毎フレーム処理：飛行制御の native 化

`Engine:Update`（control_type 分岐 → torque 計算 → `FlyAVSystem:AddForce`）は
物理適用なので**原理的に毎フレーム必要**。イベント駆動にできない唯一の部分。

### 3.1 移行先候補

| 候補 | 内容 | 評価 |
|---|---|---|
| **A. RED4ext DLL に制御ループを移す（本命）** | 既存 DLL は既に `vehiclePhysicsData_ApplyTorqueAtPosition` 等の物理パイプラインへフックを持ち、`FlyAVSystem` 自体が native。CET は `SetInputState(axes, control_type, params)` を push するだけ。DLL は物理 update のフック点で毎フレーム native 適用 | Lua→C# 毎フレーム往復が **push 1回/フレーム or 変化時のみ** に。既存 DLL の拡張で済み、redscript 不要 |
| B. redscript フックで毎フレーム tick を得る | `PlayerPuppet`/vehicle update 経路にフックを当て VM 内で回す | 成立するが、CET との往復が結局必要になり A より構成が重い。A が塞がった時の代替 |

### 3.2 縮減不能ポーリングの native 化（任意・第2フェーズ）

height レイキャストも DLL の物理シーン update フック内で native 実行し、
閾値 crossing だけを CET にコールバックできる。
R 自体は消えないが「Lua を跨がない同期クエリ」になり、発火も crossing 時に限定できる。
効果の実測（Phase 0 計装）後に要否判断。

---

## 4. フェーズ計画（v2）

### Phase 0: 計装（既存 profprobe の再掲、1〜2日）
- 状況別「C# 往復/秒・Lua alloc KB/秒」を再実測（47f5716 で削除されたので最小再計装）。
- 移行効果の見積もりを数字で持つ。**効果が薄い項目は移行しない判断を先に下す。**

### Phase A: イベント駆動化（CET のみ・redscript 不要・最優先）
1. **棚卸し確定**: §1.1 の各検知源が現環境（game 2.13 / CET 1.36 / Codeware 1.17）で
   実際に購読可能かを1つずつ実証（イベント名の確認が最大の作業。
   CET の CallbackSystem ダンプ / redscript のコールバック一覧で照合）。
2. 置換実装（効果の大きい順）:
   - `CheckInAV` 搭乗検知 → mount/transition 購読（保険 2Hz に）
   - 速度/RPM → change event 購読で HUD 更新（`CheckHUD` の定期読み廃止）
   - `CheckDestroyed` → Entity 購読
   - `CheckDoor` → Override 記録＋差分イベント
   - 疑似ポーリング 3 件（§1.3）→ 変更箇所直接呼びで消去
3. `ControlTick` の主ループは「縮減不能ポーリングのまとめ役」に縮退
   （Waiting/InVehicle の 100Hz 駆動 body がイベント主体になる）。
4. 検証: 状況別 C# 往復/秒 の再実測。目標 Waiting < 3、InVehicle < 5
   （height/dist/entry の間引き済みポーリング残のみ）。

**Phase A 実装結果（2026-10-03）:**

| 項目 | 実装 | 状態 |
|---|---|---|
| 搭乗検知 | `Observe("hudCarController", "OnMountingEvent")` → `Event:OnPlayerMounted()`（situation+entity ガード）。`CheckInAV` 削除 | ✅ |
| 降車 | 既存 `IsUnmountDirectionClosest` フックに加え `OnUnmountingEvent` → `Event:OnPlayerUnmounted()`。`CheckInAV` から分離 | ✅ |
| 破壊検知 | `ObserveAfter("VehicleComponent", "OnDeath")` ハッシュ照合 → `Event:OnAVDestroyed()`。`CheckDestroyed` 削除。（当初の `Entity.DestroyRequest` は実在関数ではなく CET 起動時エラーになった。NativeDB 2.13 で確認: Entity に destroy 系スクリプト関数は無く、death は `gameeventsDeathEvent` として車両スクリプト側へ配られる。HP observer と同クラス同パターン） | ✅ |
| 疑似ポーリング | `CheckAutoModeChange`/`CheckFailAutoPilot` 削除 → `NotifyAutoModeEnded`（0.5s 遅延）/`NotifyAutoPilotFailed` を Navigation の状態反転箇所から直接呼び | ✅ |
| 視点（FPP メータ） | `CheckPerspective` 削除 → **`Override("hudCarController", "OnCameraModeChanged")`** で wrappedMethod（ゲームの hide）実行後に `ForceShowMeter()`（mode 値ではゲートしない）。`ForceShowMeter` 側の再入は `is_force_show_meter_active` ラッチで防止。camera.lua の Cron.After 暫定版は撤去 | ✅ |
| 速度/RPM | `OnSpeedValueChanged`/`OnRpmValueChanged` Override が「所有時」に自前値を直接書き込む（`SetSpeedMeterValue`/`SetRPMMeterValue` は差分時のみ widget 書き込み）。`CheckHUD` ポーリングは削除（進捗ゲージは Navigation の更新箇所から push） | ✅ |
| ドア | `GetHasAnyDoorOpen` Override（非搭乗時）で実ドア状態を記録し、**変化時のみ** `SyncEntryDoor()`。加えて `CheckInEntryArea` の進入/離脱エッジで即時同期。`CheckDoor` ポーリングは削除 | ✅ |

- 残る定期処理（縮減不能）: height（予測間引き）/ distance（0.5s）/ entry area（キャッシュ）/
  engine 5Hz / combat 5Hz。HUD・ドアの保険ポーリングは削除済み（純イベント駆動）。
- FPP メータ再表示の実装修正（実機指摘）: `OnCameraModeChanged` の **mode 値でゲートしない**。
  ゲームは FPP 進入時に hide 経路でこの関数を呼ぶが mode の値は当てにならない（初回搭乗の
  表示は boarding の ForceShowMeter が担い、再 FPP で mode!=true により不発だった）。
  正: wrappedMethod 実行後、`IsInAVSituation() and IsFPP` なら `ForceShowMeter()` を呼ぶ
  （ShowRequest + OnCameraModeChanged(true) の実績ある合成）。`is_force_show_meter_active`
  ラッチで ForceShowMeter 自身の呼出しを再入防止。
- 保険削除に伴う駆動の引き受け手:
  - メータ所有権切替（EnableManualMeter）→ ToggleAutoMode / NotifyAutoModeEnded / 搭乗・降車イベントで明示
  - Autopilot 進捗ゲージ → Navigation 本体ループの dest_remaining_to_final 更新箇所で毎 tick push
    （一定巡航速度ではゲームの speed/rpm change event が来ないため。widget 書き込みは整数差分時のみ）
  - 左下スロット（消費アイテム/ラジオ）の非表示維持 → 旧 CheckHUD の 1Hz 再隠しを、
    `Override("HotkeyConsumableWidgetController", "SetContainerVisibility")` で置換。
    搭乗中（IsInAVSituation）は可視化要求を強制的に false に書き換える。
    降車後は situation が Waiting なので通常の車のスロット表示は影響を受けない。

### Phase B: 飛行制御の native 化
1. DLL に `DAVFlightController` 相当を追加（C++）。
   入力状態・control_type・物理パラメータは CET から push API で共有。
2. `Engine:Update` の CET 側呼び出しを撤去。
3. 既存 `FlyAVSystem` の CET からの直接呼び出しを段階的に廃止（DLL 内呼びに集約）。
4. **Autopilot のルート追従・局所回避・phase 機械を同梱**（§1.4）。
   CET は目的地・speed・phase 遷移通知を push。`AutoPilot()` の Cron ループを撤去。
5. 検証: 手動飛行のフレームタイム比較、挙動同一性。

### Phase C（任意）: 縮減不能ポーリングの native 化（§3.2）
### Phase D（任意）: A* ワーカー（純計算のみ C++ ワーカースレッド + lock-free queue）
- **Autopilot の `StepRoutePlanJob` 内部が主対象**（§1.4）。障害物グリッドのスナップショットを
  C++ に渡して純計算させ、結果ルートのみ adopt。予算（iter/tick）の制約理由が消える。
- 入力スナップショット（障害物グリッド参照、目的地）を C++ 側で保持し、
  完了時にメインスレッドで結果を CET が拾う。
- 効果: 長距離 autopilot 計画時のメインスレッド停止・巡航中の 100Hz×1200iter 実行が消える。
- 制約: ワーカースレッドからゲーム API 呼び出し厳禁（クラッシュ/データ競合）。
  純計算化のリファクタが前提。工数が最大なので Phase 0 の数字で要否を判断。

---

## 5. redscript の出番があるとしたら（限定）

| ケース | 内容 |
|---|---|
| ゲームが CallbackSystem に露出していないシグナル | 例: 特定のドア開閉完了、特定の車両状態。redscript で `QueueEvent` して CET `Observe` で受ける橋渡し |
| Phase B の代替 | DLL 改修が重すぎる場合の VM 内 tick |

**Phase A は redscript 移行を一切要求しない。**
「CET にも NewProxy がある」という見立ては正しく、まず CET だけでイベント駆動化し、
壁に当たった個所だけ redscript で橋渡しする、が最小リスクの順序。

---

## 6. リスクと対策

| リスク | 対策 |
|---|---|
| 購読したいイベントが実は存在しない/露出していない | Phase A-1 の実証を全置換に先行させる。取れないものは間引きポーリング維持（後退可能） |
| コールバック内の重い処理でディスパッチ元が詰まる | ハンドラは「判断＋キュー投入」まで。flush は CET tick で |
| イベントの取りこぼし（順序・欠落） | 各イベント駆動チェックに低速ハートビート保険（2〜5Hz）を残す。C 群の `DueNow` 型を流用 |
| ハイブリッド中の二重駆動（イベントと旧ポーリングが二重発火） | 置換単位で旧ポーリングを即停止。`SetSituation` の冪等性で吸収 |
| 物理フック（Phase B）のタイミング依存 | 既存 DLL のフック実績（ApplyTorqueAtPosition 等）を先に読み、適用点が物理 update と整合していることを実証してから移植 |
| セーブ/ロード整合 | `SessionStart` で全購読の張り直し＋状態フル再同期（既存パターン） |

---

## 7. 検証計画

1. Phase 0 の計装を移行前後で同一シナリオ比較（同一セーブ・同一ルート）:
   - 状況別 C# 往復/秒、Lua alloc KB/秒、フレームタイム p50/p95/p99
   - 「CET Cron 主ループの body 実行回数」が Waiting/InVehicle で激減すること
2. 既存テストスイートの更新版（loop_gate / demand_driven / situation / enter_exit / meter_cadence）
   ＋「イベント購読が実際に発火したか」のアサーション
3. 長時間耐久: Waiting 1h / 巡航 30min（イベント欠落・保険の発火率・リーク）
4. 互換構成マトリクス: LTBF / Audioware / NativeSettings / VehicleDurabilityDisplay

---

## 8. 判断のまとめ

- **意図（onUpdate 周期処理 → イベント駆動）は CET の `NewProxy` + `CallbackSystem` で実現可能。
  redscript 必須ではない。** 本MODは既に同じ口を入力系で使っており、実績のあるパターン。
- 置換できるのは §1.1（搭乗・降車・破壊・メニュー・HP・速度/RPM・ドア差分・疑似ポーリング）。
  **height/dist/entry はイベントが存在しないため縮減不能ポーリングとして残る**（fix 28 の間引きが最善）。
- **毎フレーム必要な飛行制御だけは native（DLL 本命）に移す。** ここが `Engine:Update` の正しい行き先。
- 順序: **Phase 0（計装）→ A（CET のみ・低リスク・効果大）→ B（DLL）→ C/D（任意）**。
  各 Phase は独立に revert 可能で、A だけで「AV 未搭乗時のメインスレッド負荷ほぼゼロ」にできる。
