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
0. **B-1（フックポイント実証）— 実装済み、実機待ち**
   - DLL に `vehicle::WheelSuspensionBase::ApplyAllResistances`（hash 2526549425）フックを追加。
     let_there_be_flight が飛行中の車両で每物理ティック発火することを実績で証明している点。
   - フックは観察のみ: 自機（`g_fly_vehicle_entity_id_hash` 一致）かつ `is_enable_original_physics == false`
     の時だけティックを数え、`FlyAVSystem:GetNativeTickCount()`（新規登録）で CET から読める。
   - CET 側 `Engine:ProbeNativeTick` が 1 秒間隔で実効 Hz をログ出力（`native physics tick: total=N effective=XHz`）。
   - 期待値: 物理ティックレート（概ねフレームレート連動 60〜144Hz、`dt` は 0.005〜0.017 程度）。
     発火確認をもって B-2（AddForce 手動飛行の native 化）へ進む。
   - 注意: let_there_be_flight と同一アドレスを hook するが、RED4ext の hooking は多重 Attach を
     チェーンするため共存可（LTBF 側も自機コンポーネント以外では素通し）。
   - **実機検証済み（2026-10-04）**: InVehicle 中 59.4〜60.8Hz で安定発火、Exit AV で凍結（0Hz）。合格。
0.5. **B-2（每フレーム force/torque 適用の native 化）— 実機検証済み（2026-10-04）、違和感なし**
   - DLL: `FlyAVSystem:SetFlightControl(mode, velocity, angularVelocity, torqueGain)` を登録。
     二重バッファ（release/acquire）で CET→物理スレッドへ引き渡し。
     mode 1 = AddForce 意味論（force += target*m、torque += (target_angvel − 実 angvel)*gain を每ティック、
     実 angvel は物理スレッドで読むので CET 側の GetAngularVelocity 往復が不要になる）、
     mode 2 = ChangeVelocity 意味論（velocity/angularVelocity を每ティック保持書き込み）。
   - Lua: `Engine:Update` は control_type に応じて target を push のみ。AddForce 時の
     `GetVelocity`/`GetAngularVelocity` C# 読み（2往復/フレーム）と `AddForce` 書き（1往復/フレーム）が消える。
     メニュー中は mode 0 を 1 回 push して native 適用を停止（旧「メニュー中は Update 停止」と同義）。
     Blocking も mode 0。FluctuationVelocity は mode 2 経由。
   - 互換: 旧 DLL（SetFlightControl 未登録）では `native_control=false` で従来経路に完全フォールバック。
   - 未実施（意図的）: `Engine:Run` の Lua 側計算（姿勢復元・air resistance・max_speed・RPM）は 20Hz のまま。
     これらの native 化（CET は入力 push のみで済む段階）は B-3。
   - 検証ポイント: ①手動飛行の挙動が移行前と同一（特に旋回時の angular 追従——torque が每物理ティックに
     増えたことで姿勢安定がむしろ滑らかになる可能性がある）②autopilot 巡航（ChangeVelocity 保持書き込みが
     每ティックになる差分）③メニュー開閉後の飛行再開 ④降車→再搭乗。
   - 検証後の後片付け: B-1 の tick ログ出力（DLL 側 120tick 毎ログ・Lua 側 ProbeNativeTick）を削除。
     push 経路は scratch Vector3 使い回し（`Engine:PushNativeControl`）で毎回アロケーションを撤去。
0.7. **B-3（手動飛行の飛行モデル計算の native 化）— 実装済み（2026-10-04）、実機検証待ち**
   - DLL: `SetFlightControl` に mode 3（native flight model）を追加。`ApplyAllResistances` フック内で
     `FmStep`（`Engine:CalculateAddVelocity`＋`Engine:Run` の移植: コマンド→加速度・姿勢ターゲット、
     姿勢復元境界層、max_speed クランプ、air resistance、RPM 積分、heli lift 積分）を每物理ティック実行し、
     AddForce 意味論で force/torque に加算。フィードバック項は每ティック再計算、積分項（RPM・lift）は
     `dt/0.01`（BASE_RESOLUTION）スケーリングで旧 20Hz ループと同一の毎秒レートに一致させる。
   - DLL 登録: `SetFlightParams`（29 個の tunables を float で push）、`SetFlightModel`（flight_mode・
     has_gravity・dt_scale・最大 6 コマンド・reset フラグ）、`GetNativeRPM`（HUD 用、rpm_count_scale 適用前値）。
     FlightModel は二重バッファ（release/acquire）。reset は搭乗直後の RPM/lift クリア。
   - Lua: `Engine:Init` が `SetFlightModel` 登録有無で `native_flight_model` を判定（旧 DLL は完全フォールバック）。
     `Engine:Init` 時に `PushNativeParams`（user_setting_table＋エンジン定数）。`AV:Operate` は手動 AddForce 中
     コマンドリストを `PushNativeCommands` で渡すだけ（Lua 計算ゼロ）。`Engine:Update` は mode 3 を 1 回 push
     して何もしない。メニュー中は mode 0（既存）。`GetRPMCount` は mode 3 中 `GetNativeRPM` を読む。
     設定スライダーは `UI:UpdateNativeSettingsPage` 経由で `PushNativeParams` 再 push。
     autopilot・Waiting（Idle）・Landing/TalkingOff・FluctuationVelocity は Lua 経路のまま（Engine:Run＋mode 1/2）。
   - 随伴修正: `Navigation` の衝突検知 speed は `engine_obj.direction_velocity`（Lua ターゲット、B-3 中は stale）
     ではなく `AV:GetCurrentSpeed()`（live velocity）を読むよう変更。
   - 検証ポイント: ①手動飛行（AV・ヘリ両モード）の挙動が移行前と同一（加速・旋回・姿勢復元・最高速クランプ・
     RPM メータ）②設定スライダー変更が即反映③メニュー開閉→飛行再開④搭乗→降車→再搭乗（RPM リセット）
     ⑤CET ログにエラーなし⑥ヘリホバリングの浮き沈み。
0.8. **B-3 実機検証失敗の分析・修正（2026-10-04）**

   **症状**: 搭乗後に一切の操作が効かない（B-3 固有ではなく native 経路全体が死んでいた）。

   **ログ証拠**（`red4ext/logs/driveaerialvehicle-*.log` / CET `DriveAerialVehicle.log`）:

   | 証拠 | 意味 |
   |---|---|
   | `SetVehicle hash=... locked=0` | `FindEntityByID` の結果を `WeakHandle` で受け `Lock()` していた。**型違い**（FindEntityByID の戻りは強ハンドル）＋エンティティ未登録だと null が返る |
   | `native_control=true native_flight_model=true mass=0.0 physics_state=-1` | `g_fly_vehicle` が **セッション全程で null**。GetMass=0 / GetPhysicsState=-1 は null 時の戻り値 |
   | `hook entry` / `hook tick` / `physics hook live` のログが **1 行も無い** | `ApplyAllResistances` フックが一度も発火していない＝ native 適用が 1 回も走っていない |

   **根本原因（多重の悪循環）**:
   1. `SetVehicle` のハンドル解決に失敗 → `g_fly_vehicle == null`。
   2. null のため `UnsetPhysicsState()`（＝`ForceEnablePhysics`）が空振り → AV の物理が有効にならない。
   3. 物理が走らないので `ApplyAllResistances` フックも発火しない → フック内の「ハンドル捕捉」も走らない。
      → **ハンドル解決できないから物理が動かず、物理が動かないからハンドルも解決できない**という閉ループ。
   4. さらに `EnableOriginalPhysics(false)` / `EnableGravity(false)` も空振りし、ゲーム側の物理と重力が乗ったまま。
   5. B-3 の mode 3 は「フックが発火して初めて効く」設計なので、入力は DLL に push されるだけで物理に一切届かない。
      （B-2 までは Lua 側 `AddForce`/`ChangeVelocity` が DLL 直接書き込みで動いていたため、この欠陥が表面化しなかった。）

   **修正**:
   - DLL: `TryResolveVehicle()` を追加。`FindEntityByID` の戻り値を**強ハンドルで直接受け**、
     失敗時はゲームスレッド側の各ネイティブ呼び出し（`GetPhysicsState`/`SetFlightControl`/`AddForce` …、
     毎フレーム走る）から**遅延再解決**（16 回に 1 回へスロットル、`SetVehicle` は常に即試行）。
     `WeakHandle`+`Lock` の型違い（weak 参照カウントの不正デクリメントも含む）は完全に撤去。
   - DLL: フックのティックカウンタを「DAV が物理を握っている時」から**自機なら常に計数**に変更。
     → Lua 側から「フックが発火しているか」を直接検証できる。
     初回発火時に `physics hook live for our vehicle` を 1 行ログ。
   - Lua: `Engine:WatchNativeTick` を追加。**mode 1/2/3 を push しているのに 1.5s ティックが進まなければ**
     `Engine:DisableNative()` で native を降り、Lua 経路（DLL 直接書き込み）へ自動フォールバック。
     ハンドル未解決（mass<=0）の間は「フックのせい」にしない（待機）。
   - Lua: `mass<=0` の間は毎フレーム `GetMass()` を再読して解決後に反映。
   - Lua: 搭乗中は 1s ごとに `EnableOriginalPhysics(false)` / `EnableGravity(false)` を再主張
     （搭乗の瞬間にハンドル未解決だと一度きりのトグルが黙って捨てられるための自己修復）。

   **再検証で確認すべきログ**（`red4ext/logs/driveaerialvehicle-*.log`）:
   - `SetVehicle hash=... resolved=1`（または遅延解決時 `vehicle resolved by 'GetPhysicsState' ...`）
   - `physics hook live for our vehicle`（搭乗後すぐ）
   - 10s に 1 行程度 `hook tick mode=3 ...`
   - CET 側: `native mass resolved: ...`、`native physics tick stalled` / `native flight disabled` が出ていたら
     native は動いていない＝フォールバックで飛んでいる（要調査）。

0.9. **B-3 実機検証 2回目（2026-10-04）— 真の根本原因は EntityID の serial 欠落**

   上記修正後のログで原因が確定した：

   ```
   SetVehicle hash=158925105316 resolved=0
   hook entry #0 hash=11315364 expected=158925105316
   ```

   - フック自体は発火していた（搭乗直後から）。**車両判定で落ちていた。**
   - `158925105316 = 0x25_00ACA8A4`（serial=37 / local=0xACA8A4）
     `11315364     = 0x00_00ACA8A4`（**serial=0** / local=0xACA8A4）
     → `vehicle::BaseObject::entityID` は **local のみ**（serial が 0）。
     CET 側が渡す `EntityID.hash` は serial 込みなので **64bit 比較は永久に不一致**。
   - つまり B-1 の「60Hz 発火」も実は別車両（または serial=0 の状態）で、
     自機判定が通ったことは一度もなかった可能性が高い。
   - さらに `FindEntityByID` は強ハンドルに直しても `resolved=0`（mod が `CreateEntity` で
     スポーンしたエンティティは DLL 側から引けない）。**ハンドル前提の設計自体が成り立たない。**

   **方針転換：ハンドル依存をなくし、フック側で自機を判定・公開する。**
   - `IsFlyVehicle()`：フル ID 一致 → だめなら **local(下位 32bit) 一致** で自機とみなす。
     `ApplyAllResistances` / `ApplyForceAtPosition` / `ApplyTorqueAtPosition` の 3 フックすべてをこの判定に統一
     （後者 2 つも同じ 64bit 比較で、ゲーム側の force/torque を抑止できていなかった）。
   - フックが自機の `BaseObject*` を `g_fly_vehicle_raw` に公開 → ゲームスレッド側の
     `TryResolveVehicle()` がそれを Adopt してハンドル化（物理スレッドでの Handle 操作＝競合は撤去）。
   - ハンドルが要る呼び出しはハンドル不要化：
     - `EnableOriginalPhysics`：単なるフラグなのでハンドル不要に変更（従来は解決失敗時に黙って捨てられていた）
     - `EnableGravity`：希望状態 `g_gravity_enable` に保存し、**フックが每ティック `unk1B0` に適用**
     - `GetMass` / `HasGravity`：フックが発行する `g_native_mass` / `g_native_gravity` にフォールバック
   - `hook tick` ログに `mass=` を追加（total_mass が 0 なら force が全部 0 になるため要確認）。

   **次の検証ログで見る行**:
   - `physics hook live for our vehicle`（これが出れば自機判定が通った証拠）
   - `vehicle adopted from physics hook`
   - `hook tick mode=3 orig_phys=0 mass=... vel=(...) force=(...)`（10s に 1 行）
     - `orig_phys=0` ならゲーム側の物理抑止が効いている
     - `mass=0` なら force が 0 なので total_mass 参照を別フィールドに替える
   - CET 側に `native flight disabled` が出なければ native 経路で飛んでいる

0.10. **B-3 実機検証 3回目（2026-10-04）— 搭乗中は動作 / 非搭乗時・水平維持が死んでいる**

   ユーザ操作（スロットル・旋回）は効くが、①非搭乗時の制御（待機ホバー・スポーン降下）と
   ②水平維持が効かない。原因は別々。

   **① 非搭乗時** — 二重の原因:
   - DLL の `FindEntityByID` が空ハンドルを返す（`SetVehicle hash=... resolved=0`）。
     Lua は同じ ID を `Game.FindEntityByID` で解決できている（`AV:Spawn` の Cron が解決できるまで
     `Engine:Init` をやり直す）ので、DLL 側の `ExecuteFunction` の噛み合わせが悪い。
     → **`SetVehicleEntity(Entity)` を新設**し、CET が解決済みのエンティティをそのまま渡してハンドル化
     （`FindEntityByID` を経由しない）。`Engine:Init` と、mass が 0 の間の再試行で送る。
   - **設計ミス**: 誰も乗っていない車両では `ApplyAllResistances` が呼ばれない（物理が回らない）。
     つまり **フック駆動の mode 2 は待機状態に使えない**。待機（ChangeVelocity /
     FluctuationVelocity）は Lua の直接書き戻しに戻した。フック駆動は AddForce（手動飛行）のみ。
   - ウォッチドッグも AddForce のみに限定（待機状態での誤発火がなくなる）。
   - mode 3 から抜けたときに mode 0 を push するよう修正（降機後も最後の飛行目標が掛かり続けた）。

   **② 水平維持** — `FmStep` の数式は Lua と同一。疑わしいのは `physicsData->orientation` からの
   Euler 分解が CET の `Quaternion:ToEulerAngles()` と一致しているか不明な点（一致しないと
   復旧項だけが無意味になる）。両側へログを追加して突き合わせる:
   - DLL: `hook tick ... att=(roll,pitch,yaw)`（10 秒ごと）
   - Lua: `cet euler roll=... pitch=... yaw=...`（飛行中 1 秒ごと）
   - 水平飛行でこの 2 組が一致すれば分解は正しい。ずれていればそこが原因。

   **ビルド済み DLL**: md5 `0ded59198aae6a9a3e529dc3c80f31fa`

0.11. **`SetVehicleEntity` は不採用（CET↔DLL はハッシュのみ）＋ FindEntityByID の正しい組み立て**

   前項で入れた `SetVehicleEntity(Entity)` は**不採用**（Lua からオブジェクトを渡せないため撤去）。
   従来どおり **ハッシュのみ**で解決する。

   `FindEntityByID` が空を返す理由として残っている本命は **引数の組み立て**：
   `ExecuteFunction("ScriptGameInstance", "FindEntityByID", &out, gameInstance, entity_id)` は
   `gameInstance` を **param 0 として**積む（`ExecuteFunction` の可変長引数はすべて param になる）。
   実際の宣言が `FindEntityByID(entityID)` の 1 引数なら、param 0 に `ScriptGameInstance` の先頭 8
   バイト（`IGameInstance*`）が **EntityID として読まれ**、本物の ID は捨てられる。
   `ExecuteFunction` は true を返すので **失敗が黙っている**。

   → **呼び出しを RTTI シグネチャ駆動にchanged**：`func->params` を回して
   `ScriptGameInstance` ならラッパーを、`EntityID`/`entEntityID` なら ID を積む。
   想定外の型なら **型名をログに出す**（`FindEntityByID param N type=...`）。
   さらに:
   - 署名を一度ログに出す（`FindEntityByID params=N ret=...`）
   - フル ID（serial 込み）で失敗したら **serial を落とした local のみ**で再試行
     （車両オブジェクトの `entityID` は serial=0 なので、レジストリ側もそうかもしれない）
   - 解決できたオブジェクトは **RTTI で `vehicleBaseObject` か検証**（違う型なら拒否。
     `physicsData` を固定オフセットで触るため、別エンティティだとメモリ破壊）
   - 解決ログに `class=` / `physdata=` / `mass=` を追加（非搭乗時に物理ボディがあるかの確認）
   - `physicsData` の null チェックを全ネイティブ呼び出しに追加（従来は null 参照のままだった）

   **ビルド済み DLL**: md5 `df3b62801698849bc7b652062822838d`

0.12. **B-3 実機検証 4回目（2026-10-04）— 非搭乗時は正常。搭乗中の水平制御だけが残っている**

   召喚後の着陸・非搭乗時の挙動・格納時の離陸は意図どおり。残るは搭乗中の姿勢（水平）制御。

   原因の本命は **DLL の Euler 分解**。`RotSpeed`（`Utils:CalculateRotationalSpeed` の移植）が
   使う行列 R1 は `Rz(roll)·Ry(pitch)·Rx(yaw)` という **roll と yaw を入れ替えた形**で、
   Lua はゲームの `ToEulerAngles()` の出力をそのままその形に放り込んでいる。
   DLL はクォータニオンから標準の回転行列（列 = 各軸の像）を作って
   `roll=atan2(fy,fx) / pitch=asin(-fz) / yaw=atan2(rz,uz)` と分解していた。
   **RotSpeed との整合は取れている**が、**ゲームの `ToEulerAngles()` と一致する保証がない**。
   一致していなければ復旧項が別軸に作用し、水平維持が壊れる（旋回中のバンクも暴れる）。

   → **推測をやめて CET と同じ値を使う**：`SetFlightModel` の 6 番目の `Vector4` で
   **CET が読んだ Euler 角（roll, pitch, yaw, valid）**を押し付け、`FmStep` はそれを使う
   （valid でないときだけ DLL の分解にフォールバック）。
   Lua 側は `AV:GetEulerAngles()`（フレームキャッシュ済み）なので追加コストは小さい。
   クォータニオン自体は推力の方向（forward/right/up）にそのまま使い続ける。

   切り分けログを 1 行に統合：
   `hook tick ... att=(CET が押した値) ext=(DLL の分解) vel=(...) force=(...)`
   - `att` と `ext` が一致 → DLL の分解は正しかった（原因はゲイン/単位側の話）
   - 不一致 → これで直る（`att` が使われるようになる）

   **ビルド済み DLL**: md5 `8f13510424f9488bc4a8e927d2e34269`

0.13. **CET の Euler を投入したら悪化した（激しい回転）→ 既定を DLL 分解に戻して診断強化**

   0.12 で `SetFlightModel` の 6 番目 `Vector4` に CET の `ToEulerAngles()` を積んで DLL に使わせた
   が、**水平維持が効かないどころか搭乗時に激しく回転するようになった**。つまり
   - ゲームの Euler 角は `RotSpeed`（R1 形式）の想定と**合わない**（R1 の分解は
     `roll,yaw ∈ (-180,180]`, `pitch ∈ [-90,90]`。ゲームの軸割り当てが違えば復旧項が暴れる）
   - もしくは 6 番目のパラメータが化けている（`att_valid` がゴミ）
   のどちらか。前者でも後者でも「att が使われると暴れる」同じ症状になる。

   対応:
   - **既定は DLL 分解に戻した**（`NATIVE_ATTITUDE_FROM_CET = false`）。CET 値の投入は
     `Vector4(roll, pitch, yaw, 1)` の W で切り替える（W=0 なら DLL 分解）。
   - DLL 側に **attitude のサニティチェック**（NaN / |値| > 540 なら不正として分解にフォールバック）。
     化けた attitude が復旧項を通じてスピンに化けるのを防ぐ。
   - 診断ログを拡張:
     - `hook tick mode=.. src=P/E .. att=(使用中) ext=(DLL分解) ..`
     - `hook ang target=(..) actual=(..) torque=(..) gain=..`（10 秒ごと）
     - Lua 側は飛行中 1 秒ごとに `cet euler roll=.. pitch=.. yaw=..`

   **切り分け**: 水平飛行中に `cet euler`（ゲームの値）と `ext=`（DLL の分解）を比べる。
   - 一致 → DLL の分解は正しい。原因は姿勢角ではなくゲイン／単位側（`hook ang` の target が
     収束しているかで判断）
   - 不一致 → 分解が違う。ただし CET 値をそのまま入れると暴れるので、
     **ゲーム Euler → R1 パラメータの変換**を挟む必要がある（`cet euler` の値から変換式を決める）

   **ビルド済み DLL**: md5 `d7bd8065517252438c8ef8fb1ccaa005`

0.14. **方針：まず元実装（Lua 飛行モデル）と同じ挙動に戻す（2026-10-04）**

   「まず元実装と同じ挙動にしたい」という指示。native 飛行モデル（B-2/B-3）は性能のための置き換えで、
   参考挙動を再現できていないなら参考側を既定にすべき。よって **native 飛行をデフォルト無効**にした。

   - `init.lua` に開発スイッチ `DAV.is_enable_native_flight = false` を追加
     （`is_debug_enable_obstacle_scan` と同じ流儀の developer switch）
   - `Engine:Init` で `native_control` / `native_flight_model` をこのスイッチで gate
   - 無効時 `Engine:Update` は **元の Lua 経路**そのもの：
     Lua が force/torque を計算して `AddForce` / `ChangeVelocity` を 1 フレームに 1 回直接書く
     （＝ B-2 以前の挙動。DLL は物理アクセッサとしてだけ使う）
   - B-3 の診断（`att=` / `ext=` / `hook ang`）はスイッチを true にしたときだけ出る
   - DLL 側は無変更（`d7bd8065517252438c8ef8fb1ccaa005` のまま）

   B-3 を続けるなら戻ってくる論点：**DLL の Euler 分解（`ext=`）とゲームの `ToEulerAngles()`
   （`cet euler`）の対応表**を作る。CET 値をそのまま R1 形式に入れると暴れるので、
   水平飛行・90°旋回などの実測から変換式を確定する。

0.15. **移植バグ確定：Euler 分解で roll と yaw が入れ替わっていた（2026-10-04）**

   Lua との差分を洗って原因を特定した。**DLL の姿勢分解が物理的に roll と yaw を入れ替えていた。**

   `RotSpeed`（`Utils:CalculateRotationalSpeed` の移植）が作る行列は
   `R1 = Rz(第1引数)·Ry(pitch)·Rx(第3引数)` — つまり **第1引数は world Z まわり**、
   **第3引数は body X まわり**の回転。Lua はここにゲームの Euler 角
   （roll = 機体左右のバンク、yaw = world Z まわりの向き）をそのまま渡している。

   一方 DLL はクォータニオンから
   ```
   roll = atan2(fy, fx)   // forward の向き = 実は heading
   yaw  = atan2(rz, uz)   // right.z / up.z   = 実はバンク角
   ```
   と分解していた。**これは R1 形式としては正しいが、物理的には roll と yaw が逆。**
   数値検証（`Rz(yaw)Ry(pitch)Rx(roll)` から作ったクォータニオンに分解を通す）：

   | 入力 roll/pitch/yaw | 旧分解 (r,p,y) | 新分解 (r,p,y) |
   |---|---|---|
   | (10, -5, 30) | (30, -5, **10**) | (10, -5, 30) ✓ |
   | (-25, 0, 90) | (90, 0, **-25**) | (-25, 0, 90) ✓ |
   | (0, 0, 179) | (179, 0, **0**) | (0, 0, 179) ✓ |
   | (-35, 12, 0) | (0, 12, **-35**) | (-35, 12, 0) ✓ |

   結果として `if cur_roll > roll_restore_amount`（バンクしているかの判定）は
   **バンクでは発火せず、旋回したときに発火**していた。→ 水平維持が効かない＋旋回時に変なロール指令。

   **修正**: 分解を物理基準に差し替え
   ```cpp
   cur_roll  = atan2(rz, uz)                        // right.z / up.z = バンク
   cur_pitch = atan2(-fz, sqrt(rz*rz + uz*uz))
   cur_yaw   = atan2(fy, fx)                        // forward の向き = heading
   ```
   これで Lua が `CalculateRotationalSpeed` に渡していた値と同じ意味になる
   （`RotSpeed` への入力は Lua と同じく「ゲームの Euler 角」でよい）。
   0.12/0.13 で CET の値を push して悪化したのも、この分解との二重すれ違いが原因。

   **副次で見つけた移植違い（Idle）**: Lua は `action == Idle` を
   `rpm_count = 0` + `CalculateIdleMode`（rpm リセット＋pitch 復旧のみ・`RestoreRate` で絞る）で
   処理するが、DLL は `LeanReset`/`Nothing` と同じ扱いで rpm もリセットしていなかった。
   → Idle を別ケースとして分離。**未移植**: `CalculateIdleMode` の高度保持
   （`is_enable_idle_gravity` と `Navigation:GetHeight()` が必要。待機状態は Lua 経路なので実害なし）

   **ビルド済み DLL**: md5 `4f12a142ba2e035e1ef5de90ab1b6bee`

0.16. **根本原因2つが確定。`physicsData->orientation` は姿勢ではなかった（2026-10-05）**

   **(a) `physicsData->orientation` はクォータニオンですらない**
   実機ログで `orientation` のノルムを測ると 2〜15（単位クォータニオンなら 1.0）。
   水平ホバー中は `(0,0,0,0)` で、本来の水平姿勢 `(0,0,0,1)` と一致しない。
   → DLL が姿勢と推力軸をここから取っていたこと自体が誤り。0.15 の Euler 分解云々の手前だった。

   **対策**: 姿勢・推力軸とも CET が毎フレーム送るエンティティ実測値に切り替え。
   `v6` = `ToEulerAngles()`、`v7` = `GetWorldOrientation()`（実 `w` を W に。妥当性はノルムで判定）、
   `v8/v9/v10` = `GetWorldForward()/GetRight()/GetUp()`。`physicsData->orientation` はフォールバック退避。
   → 無入力では 8 秒間 `roll=0.2 pitch=0.0` のまま完全水平維持を確認（元実装同等）。

   **(b) `CalculateRotationalSpeed` の受け手の roll/pitch すれ違い（真の移植バグ）**
   `Etc/utils.lua:264` は `(new_pitch - pitch, new_roll - roll, new_yaw - yaw)` を返すのに、
   呼び手は `local d_roll, d_pitch, d_yaw = ...` と受け取る。つまり元実装は
   ```lua
   roll  += (new_pitch - current_angle.pitch)   -- pitch 増分が roll に掛かる
   pitch += (new_roll  - current_angle.roll)    -- roll 増分が pitch に掛かる
   ```
   DLL はこれを「正しく」`roll += (new_roll - roll)` にしていたため、roll の補正が pitch 軸に、
   pitch の補正が roll 軸に掛かって正のフィードバックになり、少し傾いた瞬間に裏返っていた。
   `att≈0` の無入力時は増分がboth 0 なので水平維持は成功し、崩れ始めたら回収不能 — ログと一致。
   → `RotSpeed` 内で `d_roll = np - cur_pitch` / `d_pitch = nr - cur_roll` に交差させて元実装に一致。
   （`RotSpeed` の `R1` が roll↔yaw を交差させる癖と、この受け手の癖が打ち消し合っている可能性が高い）

   **同一 `att` の A/B 実測**（Lua 側で影子計算 `DAV.native_shadow` を追加して取得）
   ```
   att=(127.5,14.3,2.3)  Lua target=(-21.21,-127.03,-15.17)  DLL target=(-30.00,-21.21,-15.17)
   ```
   X と Y が入れ替わっており、上の交差で解消する。

   **安全クランプは撤去**: ±30 deg/tick は `force_restore`（`lr2 = -cur_roll`、最大 180）の
   正常な目標に掛かって元実装との差異を作っていた。±500 のゴミ値ガードのみ残す。

   **ビルド済み DLL**: md5 `5dc6c1ee70d24c2b61d01d18cd4dfbf7`
0.17. **B-4 事前 probe：非搭乗時にフックは発火するのか（2026-10-11、DLL 再ビルド不要）**

   「非搭乗時は `ApplyAllResistances` が呼ばれない」は **実測結論であって分解による証明ではない**。
   フックは車両 1 台ぶんのメンバ関数（`this = WheeledPhysics*`）なので、
   **ゲーム全体の物理が回っていることと、自機でこの関数が呼ばれることは別問題**。
   判定すべき分岐は 2 つ:
   - (a) ボディ自体が step されていない
   - (b) step はされるが `ApplyAllResistances` に到達しない（無人なので early-out 等）

   `(b)` なら手当てがあるので、まず「非搭乗でカウンタが進むか」を確定させる。
   DLL 側は既に `IsFlyVehicle()` 内でしかインクリメントしていない（＝DAV が物理を握っているかは見ていない）
   ので、**非搭乗でも呼ばれていれば確実に増える**。Lua 側ウォッチドッグが AddForce 中しか読んでいなかっ
   たため、非搭乗の数字を一度も取っていなかっただけ。

   - `init.lua`: 開発スイッチ `DAV.is_debug_probe_hook_tick = true`
   - `Engine:ProbeHookTickRate(delta)`（`Engine:Update` から毎フレーム、`Engine:ReadNativeCounter` 経由なので旧 DLL では無音）
     control_type が変わった時点で 1 エピソード発火レートを計測。
     **非搭乗 6 秒・搭乗 1 秒**（同一ログ内に A/B 基準を残すため）、1 秒ごとに 1 行、非搭乗は最後に判定 1 行。
     セッションあたり最大 40 エピソードで頭打ち（ログ膨張防止）。
   - 見るログ（CET `DriveAerialVehicle.log`）:
     ```
     hook probe armed (unboarded control_type=0 tick=... mass=... physics_state=...)
     hook tick (unboarded control_type=0): total=... effective=XHz mass=... physics_state=...
     unboarded hook verdict: hook does NOT fire unboarded -> the Lua path must keep writing physics
     unboarded hook verdict: hook DOES fire unboarded (X Hz) -> mode 2 can move into the DLL
     hook probe armed (boarded control_type=1 ...)
     hook tick (boarded control_type=1): total=... effective=60.0Hz ...
     ```
   - **判定の使い道**:
     - `effective=0Hz` → 非搭乗（待機ホバー・スポーン降下）は Lua 経路が正解。`onUpdate` は残すしかない
       （非搭乗を 20Hz Cron に落とす方向）
     - `effective>0Hz` → mode 2 をフックに戻して Lua の毎フレーム `ChangeVelocity` を消せる。
       `onUpdate` から物理適用の責務をほぼ全部外せる
   - `mass=` は補助証拠：`GetMass` はハンドル未解決時に **フックが発行する `g_native_mass` へフォールバック**
     するので、tick が 0 でも mass が解決していれば「フックは過去に一度は自機で発火している」ことになる
   - 計測後は `is_debug_probe_hook_tick = false` で無音化（コードは残してよい）

0.18. **B-4 事前 probe 実測（2026-10-11）— 非搭乗でもフックは物理ティックレートで発火している**

   実機ログ（`scripting.log` の `[DAV][probe]` / `red4ext/logs/driveaerialvehicle-*.log`）:

   ```
   hook probe armed (unboarded control_type=0 tick=0   mass=1300.0 physics_state=0)
   hook tick (unboarded control_type=0): total=59  effective=59.0Hz
   hook tick (unboarded control_type=0): total=118 effective=59.0Hz
   hook tick (unboarded control_type=2): total=191 effective=59.0Hz
   hook tick (unboarded control_type=2): total=252 effective=61.0Hz
   ```

   | 項目 | 実測 |
   |---|---|
   | 非搭乗 `ChangeVelocity`(0) | **59.0Hz** |
   | 非搭乗 `FluctuationVelocity`(2) | **59〜61Hz** |
   | `physics_state` | 0 = simulated |
   | `mass` | 1300（ハンドル解決済み・`resolved=1`） |

   **結論：doc 0.10 の「誰も乗っていない車両では `ApplyAllResistances` が呼ばれない」は誤り。**
   あの時の非搭乗不調は 0.9 / 0.11 のハンドル（serial 欠落・`FindEntityByID` の引数組み立て）が原因で、
   フックの発火有無ではなかった。`SetVehicle resolved=1 mass=1300` と `physics hook live` が
   **搭乗の 11 秒前**（`SetFlightControl mode=3` より前）に出ているのが決定的。

   → **B-4 が開いた**: 非搭乗（待機ホバー `ChangeVelocity` / 降下 `FluctuationVelocity`）を
   mode 2 経由で DLL フックに戻せば、`Engine:Update` の毎フレーム物理書き込みを消せる。
   残る `onUpdate` の責務はモード切替と診断だけになる。

   **probe 自体に見つけたバグ（修正済み）**: スポーン降下で `av.lua` が
   `ChangeVelocity` ⇄ `FluctuationVelocity` を ~100ms 間隔で交互に設定するため、
   control_type 変更のたびにエピソードが再武装され、40 件の上限を数秒で使い切っていた。
   → **安定化ゲート 0.5s** を追加（値が 0.5s 保ってから武装）。発火レート自体は全サンプルで同一。

   **ログの可視化について**: `Log:Record` は `spdlog.info` にしか出さず、`print` は
   `PrintDebugMode`（ImGui の "Print Debug Mode"）がオンのときだけ。診断は `Engine:ProbeLog`
   経由で無条件に `print` するようにした（`scripting.log` と CET コンソールに出る）。

0.19. **B-7 の設計方針：「Update を軽くする」ではなく「Update を消す」（2026-10-11）**

   B-6 のあと `Engine:Update` の中身はほぼゼロになったが、**行数は増えた**。毎フレーム呼ぶ関数に
   `is_passive` の簿記を足す設計は、目的（`onUpdate` から物理適用の責務を外す）と逆方向だった。
   そこで B-7 は「ゲートして呼ぶ」ではなく **`Engine:Update` 関数そのものを削除**する。

   以前は「1 つでも wake source を漏らすと推進を失って落下する」ため毎フレーム呼びを残す判断だったが、
   それは **責務を 1 箇所に寄せていない**ことの言い訳になっていた。`Update` の 12 の責務を
   それぞれの自然な家に移せば、毎フレームの呼び出し自体が不要になる:

   | 責務 | 移した先 | 駆動 |
   |---|---|---|
   | ガード（`is_finished_init` / `entity_id` / メニュー） | 関数ごと消滅 / `ApplyControlMode` | エッジ |
   | `mass<=0` の再解決 | `Engine:Heartbeat` | Core の 0.5s Cron |
   | physics state ポーリング | `Engine:Heartbeat` | 同上 |
   | フック生存ウォッチドッグ | `Engine:Heartbeat` | 同上 |
   | mode 3 の push / 解除 push | `Engine:ApplyControlMode` | `SetControlType` |
   | mode 2 の velocity hold | `Engine:PushVelocityHold` ← `PushFlightTarget` | セッター |
   | AddForce（mode 1 / Lua フォールバック） | `Engine:PushForceTarget` / `ApplyLuaFlightModel` | セッター |
   | `FluctuationVelocity` のランプ | `Engine:LoopTick`（専用 Cron） | 0.01s Cron |
   | Blocking / 不明タイプ | `ApplyControlMode` | エッジ |

1. DLL に `DAVFlightController` 相当を追加（C++）。
   入力状態・control_type・物理パラメータは CET から push API で共有。
2. `Engine:Update` の CET 側呼び出しを撤去。
3. 既存 `FlyAVSystem` の CET からの直接呼び出しを段階的に廃止（DLL 内呼びに集約）。
4. **Autopilot のルート追従・局所回避・phase 機械を同梱**（§1.4）。
   CET は目的地・speed・phase 遷移通知を push。`AutoPilot()` の Cron ループを撤去。
5. 検証: 手動飛行のフレームタイム比較、挙動同一性。

### Phase B 実装結果（最終・2026-10-10）

**結論: 手動飛行は DLL のフィッシュフック 1 か所で駆動。CET 側の毎フレーム飛行計算は消えた。**

#### B-3 以降に判明した、移植を壊していた根本事実

| # | 事実 | 影響 |
|---|---|---|
| 1 | エンティティ quaternion のローカル軸は **forward = AxisY / right = AxisX / up = AxisZ**。通常の (X=forward, Y=right) 想定が逆だった | 推力方向と姿勢抽出が同時にずれる。以前の「roll/pitch 符号反転」「yaw 90° ズレ」はすべてこれの症状 |
| 2 | ゲームの `ToEulerAngles` 規約は軸から直接導出する<br>`roll = atan2(-right_z, hypot(forward_z, up_z))` / `pitch = atan2(forward_z, up_z)` / `yaw = atan2(right_y, right_x)` | 急バンク・急ピッチでも一致（実測 2 桁一致）。個別パッチは水平付近でしか合わず、自動水平復元が壊れていた |
| 3 | `Utils:CalculateRotationalSpeed` は **戻り値が交差**している（`return new_pitch - pitch, new_roll - roll, ...` を `d_roll, d_pitch` に束縛） | 原実装どおりの交差が必須。「正しそう」な交差なし版はヘリの lean 軸を入れ替えた |
| 4 | Lua の自動復元項はすべて **マイナス**（`local_pitch = local_pitch - RestoreRate(...)`） | DLL がプラスで実装しており正帰還。水平維持が Lua より不安定だった原因 |
| 5 | 方角が ±180° を跨ると差分が ±360 飛ぶ（実測 `d_yaw = -359.90`） | 激しいスピン。`fm_wrap180` で全差分を ±180 に正規化 |
| 6 | roll には `max_roll` 超過補正があるが pitch には無い | ヘリが `max_pitch` を越えると 0.2/tick の弱い復元だけ残り垂直まで行き止まらなかった。対称に追加 |

#### 入力経路（イベント駆動）

- `SetNativeCommand(action_id, value)` で DLL が保持状態（held state）を持つ。Lua は press / `IACT_Release` / `IACT_Abort` / 軸エッジでのみ呼ぶ
- **20Hz のコマンド push は廃止**。タイマー・TTL は不使用（解放はリリースエッジで検知）
- 軸はデッドゾーン通過時のみ送信（サイン反転時は旧アクションを 0 にしてから新アクション）

#### 毎フレームの DLL 往復（定常飛行時）

| 呼び | 頻度 |
|---|---|
| `SetFlightModel` | 毎フレーム（Vector4 は 1 個のみ有効。att/ax は廃止し DLL が quaternion から導出） |
| `GetNativeTickCount` | 約 1 秒に 1 回（フック生存ウォッチドッグ） |
| `GetPhysicsState` | フック live 確認まで。以降は 0 |
| ~~`GetEulerAngles` / `GetForward` / `GetRight` / `GetUp`~~ | **廃止**（毎フレーム 4 回のゲーム API 呼びが消えた） |
| ~~`EnableOriginalPhysics` / `EnableGravity` の 1Hz 再主張~~ | **廃止**（フックが毎 tick 重力を保持している） |

#### 撤去したもの

`native_shadow`（毎フレーム Lua 版フライトモデルを再実行して A/B ログ）、`ProbeInput` / `ProbeAtt` ネイティブ、`att state` / `att delta` / `ax delta` / `ax cmp` / `held changed` ログ、`input_probe` カウンタ。

#### Phase C（縮減不能ポーリングの native 化）

`PollGroundZ` / `GetGroundZ` / `SetGroundFilter` / `PollProximity` / `PollInEntryArea` / `SetEntryAreaParams` を実装したが、Lua 側で採用せず **DLL から削除済み**（552 行）。`ground raycast` と `proximity probe` の実装は履歴に残っているので、必要なら復活できる。

#### ビルド済み DLL

md5 `b8e44ea39b61e7f41337b8e3d4f804a2`（Phase C 削除後）

### B-4（非搭乗の毎フレーム物理書き込みの撤去）— 実装・実機検証済み（2026-10-11）

   0.18 の実測（非搭乗でもフックが 59〜61Hz で発火）を根拠に、doc 0.10 で
   「フックが非搭乗で発火しない」を理由に Lua へ戻した **ChangeVelocity / FluctuationVelocity を
   DLL の mode 2 に戻す**。DLL の変更は不要（mode 2 は B-2 で実装・検証済み）。

   | 変更 | 内容 |
   |---|---|
   | `Engine:ApplyVelocityHold()`（新設） | mode 2 を **ターゲットが動いた時だけ** push（eps: 速度 0.01 / 角速度 0.01）。`native_last_mode == 2` も条件（途中で mode 1/3 が挟まると DLL が別モードを保持したままになるため）。旧 DLL（`native_control=false`）は従来どおり毎フレーム直接書き込み |
   | `Engine:Update` の ChangeVelocity 分岐 | 毎フレーム `ChangeVelocity()` → `ApplyVelocityHold()` に置換 |
   | `Engine:FluctuationVelocity` の末尾 | 同上（降下ランプは毎フレームターゲットが動くので実質毎フレーム push、完了後は 0 回） |
   | `Engine:PushNativeOff()`（新設） | mode 0 を **1 回だけ** push。Blocking・未知の control_type・降機・**エンティティ破棄後**・メニュー閉じで共通利用 |
   | `Engine:Init` | 新規エンティティで mode 0 を 1 回 push（共有バッファが前機の mode 1/2/3 を引き継ぐ事故防止） |
   | `Engine:WatchNativeTick` | 監視対象を拡張：AddForce に加え **mode 2 ホールド中**（ChangeVelocity / FluctuationVelocity）も監視。フックが止まれば従来どおり Lua 経路へ自動フォールバック |

   **期待効果**: 非搭乗の待機ホバーはターゲット再計算が 20Hz（`Engine:Run`／`CalculateIdleMode`）なので、
   物理書き込みの DLL 往復が **60/s → 最大 20/s、ターゲットが収束すれば 0/s**。
   probe の `hold_pushes=N/s` で実測できる。

   **検証ポイント**:
   1. 召喚直後の降下（FluctuationVelocity）が従来どおりか
   2. 待機ホバーの高さ保持（`is_enable_idle_gravity`）が崩れないか — mode 2 は每ティック保持なので
      Lua の毎フレーム書き込みより保持が強い。差が出るなら eps を緩めるか mode 2 を每フレーム push に戻す
   3. 搭乗 → 降車 → 再搭乗（mode 3 ⇄ mode 2 の切り替わりで `PushNativeOff` が効くか）
   4. メニュー開閉、autopilot 巡航（ChangeVelocity を 100Hz で使う）
   5. `native flight disabled` が出ないこと（出たら非搭乗でフックが止まっている＝フォールバック作動中）

   **実機検証結果（2026-10-11、`scripting.log` の `[DAV][probe]` / `red4ext/logs/driveaerialvehicle-*.log`）**:

   | 状態 | フック発火 | `hold_pushes` | 従来（毎フレーム直接書き込み） |
   |---|---|---|---|
   | 非搭乗・待機ホバー（ChangeVelocity） | 58.0Hz | **0/s** | 60〜77/s |
   | 非搭乗・降下（FluctuationVelocity） | 60.0Hz | 77/s（ランプ中はターゲットが動くので要 push） | 77/s |

   モード遷移（DLL 側ログ。DLL は「モード変更」または「mode 2 で |Δv|>0.5」の時だけログする）:

   ```
   18:33:14.961  mode=0            ← Engine:Init の初期化 push（B-4 で新設）
   18:33:14.962  mode=2 (0,0,-5.0) ← スポーン降下のターゲット
   18:33:17.4..18:33:18.9  mode=2 -4.49 → -1.39   ← FluctuationVelocity のランプ
   18:33:22.016  mode=2 (0,0,0)    ← 待機収束（以後 push 0 回）
   18:33:23.297  mode=3            ← 搭乗
   18:33:38.109  mode=0            ← 降車（PushNativeOff）
   18:33:38.110.. mode=2 -0.05 → -3.19 → … → +4.55 ← 降車後の降下／高度保持
   18:33:52.428  mode=0            ← 最終停止
   ```

   - `native physics tick stalled` / `native flight disabled` は**一切なし**＝ウォッチドッグは発火せず、
     native 経路が生きていた
   - Lua エラーなし。probe の安定化ゲート（0.5s）で再武装スパムも消えた（1 セッション 3 武装）
   - **効果**: 非搭乗アイドル時の物理書き込み DLL 往復が **毎フレーム 1 回 → 0 回**。`onUpdate` 側の
     定常コストは「Lua 関数呼び 1 回＋フィールド読み」だけになった

   **残務**: 計測は済んだので `DAV.is_debug_probe_hook_tick = false` で無音化済み（コードは残置。
   true に戻せば `hook tick (unboarded control_type=..): ... hold_pushes=N/s` を再取得できる）。

### B-6（`Engine:Update` の最後の毎フレーム処理を撤去）— 実装済み（2026-10-11）、実機検証待ち

   B-4 後も `onUpdate` から毎フレーム呼ばれている `Engine:Update` に、まだ 2 つの処理が残っていた。

   | 撤去した処理 | 従来 | 現在 |
   |---|---|---|
   | メニュー/ポップアップ/フォト判定 | 毎フレーム `IsInMenuOrPopupOrPhoto()` を読み、開いていたら mode 0 を 1 回 push（`native_off_pushed` ラッチ） | **エッジ駆動**。`Event:SetBlockedFlag(flag, value)` が 6 つの observer（Menu/Popup/PhotoMode の Open/Close）から集約状態の変化だけを `Engine:SetMenuBlocked(blocked)` に伝える。Engine はフラグ 1 個を持ち、開時に `PushNativeOff()`、閉時にラッチを落として次回再 push を強制 |
   | `force` / `torque` のゼロベクトル確保 | 分岐ごとに `Vector3.new(0,0,0)` を 2 回/フレーム（デバッグ表示専用） | `self.zero3` を 1 個共有（`New` で生成。モジュールスコープで作らないのは CET サンドボックスの `Vector3` がランタイムグローバルなため）。`SetForce`/`SetTorque` は参照差し替えのみで要素書き換えが無いことを確認済み |
   | `native_off_pushed` | ラッチ管理 | 撤去（メニューがエッジ駆動になったので不要） |

   **現在の `Engine:Update` の定常コスト**（非搭乗アイドル・ターゲット収束時）:
   `is_finished_init` / `entity_id` / `is_menu_blocked` / `mass` のフィールド読み、
   `WatchNativeTick` のアキュムレータ（**0.5s に 1 回** `GetNativeTickCount` を読むだけ）、
   `ApplyVelocityHold` の比較 6 回。**DLL 往復は 2 回/秒、Lua アロケーションはゼロ。**

   **検証ポイント**:
   1. メニュー / インベントリ / ポップアップ / フォトモードを開いたときに機体が固まり、閉じたら即復帰するか
      （旧実装と同じ挙動か）
   2. 搭乗中にメニューを開閉して飛行再開できるか
   3. 召喚 → 待機 → 搭乗 → 降車が従来どおり

   **残る `onUpdate` 呼び出しそのものを止めるには**（B-7 候補・要設計）:
   `Engine:Update` を「何か起きる時だけ」の呼び出しにするには、wake source を網羅する必要がある
   （`SetControlType` / `SetDirectionVelocity` / 搭乗・降車 / メニュー / 設定変更 / スポーン・格納 /
   autopilot 起動停止）。1 つでも漏れると**推進を失って落下する**ため、
   「毎フレーム呼ぶが中身がほぼゼロ」のままにするか、ウォッチドッグを Cron に移して
   呼び出し側を `is_driving` フラグでゲートするかの判断が要る。

0.20. **B-7 初回実機：メニューを開くと native が黙って落ちる（2026-10-12）**

   ユーザー報告「autopilot だけおかしい」。`scripting.log` の probe が全てを語っていた:

   ```
   11:09:26 unboarded control_type=0: hold_pushes=40/s target_pushes=40/s loop=false   <- native 正常
   11:09:37 boarded   control_type=1: hold_pushes=0/s  target_pushes=0/s  loop=false
   11:10:25 unboarded control_type=0: hold_pushes=0/s  target_pushes=84/s loop=true    <- Lua フォールバック
   ```

   `hold_pushes`（実際に DLL へ push した回数）が 0 なのに `target_pushes`（セッター由来の呼び出し）が ~100/s、
   しかも `loop=true` が常時。`LoopTick` は native が生きている限り自分で `StopLoop()` するので、
   この組み合わせは **`native_control == false`（＝ `DisableNative` 発動）以外に成立しない**。

   **原因：`Engine:Update` を `Engine:Heartbeat` に移したとき、メニューゲートの早期 return を落とした。**
   旧 `Update` は `if self.is_menu_blocked then return end`（`WatchNativeTick` より前）で終わっていたが、
   新 `Heartbeat` にこの check が無い。メニュー / ポップアップ / フォトモードを開くと物理が凍るので
   フックの tick カウンタも止まる → `WatchNativeTick` が 1.5s で stall を数え上げ → `DisableNative` →
   **以後そのセッションは全部 Lua 経路**。しかも `Log:Record(LogLevel.Error, ...)` は `PrintDebugMode`
   オフでは `scripting.log` に出ないので、**何も見えずに落ちていた**。

   **修正**:
   1. `Heartbeat` に `is_menu_blocked` の早期 return を復活（このとき stall アキュムレータもリセット）
   2. `DisableNative` は `ProbeLog`（無条件 `print`）にも出す — 「黙って native を失う」を禁止
   3. probe に `native=` `fm=` `mode=` `auto=` を追加。次回以降この推論をログ 1 行で確定できる

   **同時に見つけた B-7 起因のリグレッション 2 件**:

   | 問題 | 内容 | 修正 |
   |---|---|---|
   | `is_auto_pilot` がモードを再評価しない | mode 3 は「手動専用」。搭乗中に autopilot を開始しても、Navigation が `SetControlType` を叩くまで DLL は mode 3 のまま。旧 `Update` は毎フレーム `not is_auto_pilot` を見ていたので自動回復していた | `Engine:SetAutoPilot(on)` を追加し、`navigation.lua` の 3 か所の直接代入を置換 |
   | ランプが実フレームレートで積分しない | `LoopTick` に固定 0.01s を渡していたが、Cron は 1 フレーム 1 回しか発火させない。60fps だと降下ランプが 40% 遅い | `DAV.last_frame_delta`（onUpdate で記録）を渡すようにした |

   **教訓**: 「毎フレーム呼ぶ」は遅い代わりに **状態変化の見逃しを全部吸収していた**。消すときは
   `Update` の早期 return 1 本まで含めて棚卸ししないと、この種のサイレント劣化になる。

### B-7（`Engine:Update` の削除）— 実装済み（2026-10-11）、実機検証待ち

   > ⚠ **初回実機で 2 つのリグレッション（0.20）。以下の記述は設計時点のもの。**

   `onUpdate` からの `Engine:Update` 呼び出しを消し、**関数ごと削除した**。0.19 の方針どおり、
   「ゲートして呼ぶ」ではなく「呼ばない」。

   **`init.lua` の `onUpdate` は `Cron.Update(delta)` だけになった**（飛行制御の責務ゼロ）。

   #### 新しい責務の置き場所

   | 関数 | 誰が呼ぶ | 何をする |
   |---|---|---|
   | `Engine:ApplyControlMode()` | `SetControlType` / `Engine:Init`（再スポーン用） / `SetMenuBlocked` / `AV:Despawn` / `DisableNative` | 現在の状態が要求する native mode を **1 回** push。mode 3 ラッチの張替え、メニュー・デスポーン時の mode 0 |
   | `Engine:PushFlightTarget()` | `SetDirectionVelocity` / `SetAngularVelocity` / `Run` / `OnlyAngularRun` / `SetFluctuationVelocityParams` / `LoopTick` | 制御タイプに応じた target を DLL へ。**値が変わったときだけ** |
   | `Engine:PushVelocityHold()` | `PushFlightTarget` | mode 2（change-detect 付き、`native_last_mode==2` も見る） |
   | `Engine:PushForceTarget()` | `PushFlightTarget` | mode 1（DLL が毎 tick トルク誤差を計算） |
   | `Engine:ApplyLuaFlightModel()` | `PushFlightTarget`（DLL に `SetFlightControl` が無い／ウォッチドッグ発動時） | 旧 Lua 飛行モデル |
   | `Engine:StartLoop()` / `StopLoop()` / `LoopTick(delta)` | `ApplyControlMode` | **ランプ積分**（`FluctuationVelocity`）と、native が無い場合の再適用だけの専用 Cron（0.01s） |
   | `Engine:Heartbeat(delta)` | Core の 0.5s Cron | `mass<=0` 再解決、`ForceEnablePhysics`、フック生存ウォッチドッグ、probe |

   #### 各状態での「毎フレーム Lua」

   | 状態 | onUpdate での `Engine` 呼び出し | Cron |
   |---|---|---|
   | 非搭乗アイドル（収束） | **0** | なし |
   | 非搭乗アイドル（ターゲット変化） | 0（セッターが push） | なし |
   | 搭乗飛行（mode 3） | 0（`PushNativeCommands` は制御ループ側） | なし |
   | 降下 / 上昇（`FluctuationVelocity`） | 0 | **1 本（0.01s）** |
   | native 無効（旧 DLL / `is_enable_native_flight=false`） | 0 | **1 本（0.01s）** |
   | メニュー開 / 格納済み | **0** | なし |

   #### 削除・変更した呼び出し側

   - `SetControlType`: 変更時 `ApplyControlMode()`。**同一値なら早期 return**（`Engine` は AV より長生きなので、
     `Engine:Init` が再スポーン時に必ず `ApplyControlMode` を呼んで補う）
   - `SetDirectionVelocity` / `SetAngularVelocity`: eps 比較して**変わったときだけ** `PushFlightTarget()`
   - `Run` / `OnlyAngularRun`: 同上（制御ループは毎フレーム同じ値を再送するので、これがゲートの実働部分）
   - `SetMenuBlocked`: `ApplyControlMode()` に一本化（`native_mode3_pushed`/`native_hold_pushed` の手动リセットを撤去）
   - `SetIdle`: wake 不要になったので単なる代入
   - `SetFluctuationVelocityParams`: `engine_control_type` 直書きをやめ `SetControlType` 経由（ランプ開始のトリガ）
   - `FluctuationVelocity`: タイプ直書きを `SetControlType` に、`ApplyVelocityHold` を `PushFlightTarget` に変更
   - `AV:Despawn`: `entity_id = nil` 後に `engine_obj:ApplyControlMode()`（もはや誰も entity を毎フレーム見ていない）
   - `Engine:Init` 末尾: `ApplyControlMode()`
   - `Engine:DisableNative`: `ApplyControlMode()`（Lua 飛行モデルへ切り替え＝ループ開始）
   - `Engine:ApplyVelocityHold` → `Engine:PushVelocityHold` に統合、`Engine:Wake` / `is_passive` / `update_call_count` を削除

   #### native が無い経路の扱い（後方互換）

   `native_control == false`（旧 DLL、または `is_enable_native_flight = false`）では DLL が何も再適用しないので、
   **Lua 側が毎 tick 書き続けないと減速して落ちる**。よって `ApplyControlMode` は native が無いときだけ
   `StartLoop()` を呼び、`LoopTick` が `PushFlightTarget()` を再適用する。つまり「Cron 1 本で毎フレーム駆動を代替」。

   #### probe の変更

   `frames=N/s`（`Update` 呼び出し数）は意味を失ったため **`target_pushes=N/s`（実 push 数）と `loop=true/false`** に置換。

   #### 検証ポイント

   1. 召喚 → 待機ホバー（上下しない・落ちない）
   2. 搭乗 → 離陸 → 飛行 → 降車 → 格納
   3. 降下格納（`FluctuationVelocity` のランプが Cron で回るか）
   4. メニュー / インベントリ / ポップアップ / フォトモード開閉で固まる→復帰
   5. ヘリモード、autopilot（mode 3 解除 → mode 1/2 復帰）
   6. `scripting.log` に `native flight disabled` が出ないこと（ウォッチドッグ誤発動の検知）
   7. probe ON のとき `target_pushes` が収束時 **約 2/s**、降下中だけ **約 100/s**、`loop` が降下中のみ true
   8. **メニュー / ポップアップを開いたまま 5 秒置いても `native=true` が保つか**（0.20 の回帰テスト。
      `native=false` に反転したら `NATIVE FLIGHT DISABLED -> Lua fallback` の行に理由が出る）
   9. 搭乗中に autopilot 開始 → `auto=true` かつ `mode=1`（mode 3 のままにならない）→ 降車・格納できるか

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
