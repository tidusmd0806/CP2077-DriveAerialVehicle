# 改善計画：ポーリング駆動 → イベント駆動

作成日: 2026-10-02 / 対象: v3.3.1
**進捗: B群・§1.5・C群・A群・D群 すべて実装済み（8スイート 358 assertion 通過）。**
既存の `PERFORMANCE_FIX_PLAN.md`（fix 1〜30）は「1回あたりのコスト削減」が主眼だった。
本計画は **そもそも発火させない**（周期そのものを消す／要求時のみ起こす）軸で残りを潰す。

---

## 0. 棚卸し：今も回っているポーリング一覧

| # | 箇所 | 周期 | AV未召喚でも走る | 実体 |
|---|---|---|---|---|
| 1 | `core.lua:193` 主ループ `Cron.Every(applied)` → `ControlTick` | 100Hz | **走る** | CheckAllEvents + GetActions |
| 2 | `core.lua:1149` `GetActions()` の `move_actions={}` + `{Nothing,1}` | 100Hz | **走る** | 無入力時も Lua table 3個/tick |
| 3 | `core.lua:591` `UpdateGarageInfo` | 1s | **走る** | `GetVehicleSystem`+`GetPlayerUnlockedVehicles`（N個 userdata alloc） |
| 4 | `core.lua:264` `EnsureObstacleMapPreloadTimer` → `MaintainObstacleMapCache` | 20Hz | **走る（セッション中永久）** | `GetPlayer`+`GetWorldPosition`+`FlushLearnedCellsToImage` |
| 5 | `init.lua:502` `Engine:Update(delta)` | 毎フレーム | **走りうる**（下記 §1.5） | `GetPhysicsState` 等 |
| 6 | `event.lua:196` LTBF 互換 poll | 10Hz | **走る** | `fs().ctlr.active` 読み |
| 7 | `event.lua:504` `CheckInAV` → `IsPlayerMounted` | 100Hz | Waiting時のみ | 降車検知 |
| 8 | `event.lua:594` `CheckDoor` → `GetVehiclePS`+`GetDoorState` | 100Hz | Waiting時のみ | 開閉状態の追従 |
| 9 | `event.lua:587` `CheckEngine` → `IsEngineTurnedOn` | 100Hz | InVehicle時のみ | |
| 10 | `event.lua:609` `CheckCombat` → `GetPlayer`+`PSIsInDriverCombat` | 100Hz | InVehicle時のみ | |
| 11 | `event.lua:553` `IsVisibleConsumeItemSlot`（pcall+widget走査） | 100Hz | InVehicle時のみ | |
| 12 | `event.lua:565` 速度/RPM 取得→メータ書き込み | 100Hz | InVehicle時のみ | 既に game 側 change event あり |
| 13 | `event.lua:782` `CheckInput` → `IsVisibleCustomInputHints` | 2s | InVehicle時のみ | widget ツリー走査 |
| 14 | `event.lua:802/814` `CheckAutoModeChange` / `CheckFailAutoPilot` | 100Hz | InVehicle時のみ | 読み元は全部 Lua 側状態 |
| 15 | `event.lua:845` `CheckPerspective` → `GetCurrentCameraDistanceLevel` | 100Hz | InVehicle時のみ | 読み元は Lua の `current_camera_mode` |

**#14 #15 は C# を跨がないだけの「疑似ポーリング」**（状態変化は必ず Lua 側で起きている）。
**#7 #12 はゲーム本体が既にイベントを配っている**（mount/unmount、`OnSpeedValueChanged`/`OnRpmValueChanged`）。

---

## 1. A群：状況駆動のループ停止（最大効果）

### 1.1 設計
`Event:SetSituation()`（`event.lua:333`）は **全状態遷移が必ず通る唯一のチョークポイント**。
ここに「状況 → ループ周期」の対応表を置き、`Cron.Pause` / `Cron.Resume` で
主ループごと寝かせる。Cron は既に Pause/Resume を持つ（`Cron.lua:124-154`）ので新機構は不要。

| situation | 主ループ周期 | 理由 |
|---|---|---|
| `Idle` / `Normal`（AV 未召喚） | **停止**（garage の 1Hz ハートビートのみ） | 実質アイドル。fix 21 で「Waiting tick の 95% はメニュー中」と実測済み。Normal に至っては中身が `UpdateGarageInfo` だけ |
| `Landing` / `TalkingOff` | 100Hz 維持 | 降下／上昇の閾値判定（`SpawnLead`）が tick 周期依存 |
| `Waiting` | 20Hz に減速 | 進入エリア・降車検知は 20Hz で体感差なし。CheckHeight は既に間引き済み |
| `InVehicle` | 100Hz 維持 | 飛行制御ループ |

### 1.2 起こし条件（wake-up）— すべて既存のイベントで賄える
| きっかけ | 既存の受け口 |
|---|---|
| 召喚キー | `Core:SetSummonTrigger` の `Override("VehicleSystem","SpawnActivePlayerVehicle")`（core.lua:334） |
| セーブ読込 | `GameUI.Observe("SessionStart")`（event.lua:162） |
| メニュー/ポップアップ/フォト解除 | `MenuClose` / `PopupClose` / `PhotoModeClose`（event.lua:142-159） |
| 入力全般 | `Input/Key` / `Input/Axis` プロキシ（init.lua:378/415） |
| 搭乗／降車 | `VehicleTransition` フック（event.lua:290/308）＋下記 C-1 |

### 1.3 実装スケッチ
```lua
-- core.lua
local LOOP_RATE = {          -- nil = 停止
    [Def.Situation.Idle]      = nil,
    [Def.Situation.Normal]    = nil,
    [Def.Situation.Landing]   = 1.0,   -- 基準解像度の倍率。0.01 * 1.0 = 100Hz
    [Def.Situation.Waiting]   = 0.2,   -- 5 倍間引き = 20Hz
    [Def.Situation.InVehicle] = 1.0,
    [Def.Situation.TalkingOff]= 1.0,
}

--- Rescale the main loop for a situation. Idempotent.
function Core:ApplySituationLoopRate(situation)
    local rate = LOOP_RATE[situation]
    if rate == nil then
        if self.main_loop_timer ~= nil then Cron.Pause(self.main_loop_timer) end
        self.main_loop_paused = true
    elseif self.main_loop_paused then
        Cron.Resume(self.main_loop_timer); self.main_loop_paused = false
    end
    -- 周期そのものを変える場合は ApplyTimeResolution(applied * rate) を再利用
end
```
`Event:SetSituation()` の return true 経路で `DAV.core_obj:ApplySituationLoopRate(situation)` を呼ぶ。

### 1.4 注意点（要テスト）
- **停止中に Cron.After が積めない**わけではない（Cron.Update が走らないので `Cron.After` も遅延する）。
  → 停止するときは保留中の `Cron.After`（`delay_action_time_*`, 降車後 1.5s の HUD 処理など）を
    必ず **状況復帰時に実行し直す**か、停止前に flush する。
  代替案：主ループは止めず、`ControlTick()` の先頭で
  `if self.loop_sleeping and not self:wake_required() then return end` とする
  （Cron 自体は回し続けるので `Cron.After` は死ぬが、CheckAllEvents/GetActions だけ止まる）。
  **こちらの方が安全で、効果もほぼ同じ**（CheckAllEvents+GetActions が本体なので）。
- `Engine:Update` は `onUpdate` 側で毎フレーム呼ばれている（主ループ外）。A群では止まらない。
  → §1.5 を参照。

### 1.5 副次バグ：`Engine:Update` が死んだ機体に対して走り続ける
`Engine.is_finished_init` は `Engine:Init`（engine.lua:71）で true になり、
**Despawn ではリセットされない**（engine.lua 全体で 57/71 の 2 箇所のみ）。
`AV:Despawn()`（av.lua:548）は `entity_id = nil` にするが engine は触らない。
`Core:Reset()` で新 AV/Engine に差し替わるまで、`init.lua:505` の
`engine_obj:Update(delta)` が **消えた entity_id に対して毎フレーム
`fly_av_system:GetPhysicsState()` を叩き続ける**（降車〜Reset の間だけでなく、
`DespawnFromGround` の 1.5s + 検知遅延ぶん）。

**実装済み（2026-10-02）**：`Engine:Update` の先頭に `av_obj.entity_id` を
見るゲートを追加した（engine.lua、`is_finished_init` チェクの直後）。

`is_finished_init` を `AV:Despawn()` で倒す案は採用しなかった。このフラグは
engine.lua 内で 10 箇所のメソッドが参照しており、降車後に黙って no-op に
なる経路が出てしまう。`entity_id` 側を見たほうが影響は `Update` の 1 箇所に
閉じ、次の `AV:Spawn` で自然に解消する。

検証: `tests/demand_driven_test.lua` §13（entity なし／despawn 済みでは
メニュー判定も物理判定も 0 回、生存 entity では従来どおり走る）。

## 1.9 A群 実装内容（2026-10-02 完了）

### 方式：`ControlTick` 先頭ゲート（§1.4 の「代替案」を採用）
`Cron.Pause` / `Cron.Resume` で主ループごと寝かせる案は**不採用**。理由:

1. measured-dt サンプラも一緒に止まる。復帰後の最初の 1 tick が**睡眠期間
   まるごとを 1 dt として積分**し、tick 依存のアキュムレータ（RPM ランプ、
   スラスター角など）が吹っ飛ぶ。
2. 計画 §1.2 に並べた起こし条件を**全部**取りこぼすと二度と起きなくなる。
   ゲート方式は毎 tick Lua 側状態を見るだけなので、起こしフックが構造的に
   不要。

Cron は回し続けたまま body だけをスキップする。コストは tick あたり Lua 比較 1 回。

### 3 段階ゲート `Core:ControlLoopState()`
body は「CheckAllEvents（C# heavy 側）」と「GetActions（入力ドレイン側）」の
2 半分で結合度が違うので、段階を分けた。

| state | CheckAllEvents | GetActions | 該当状況 |
|---|---|---|---|
| `run` | 実行 | 実行 | Landing / TalkingOff / InVehicle、保留入力あり、heartbeat 期限 |
| `checks_paced` | **スキップ** | 実行 | Waiting の非スロット |
| `sleep` | スキップ | スキップ | Idle / Normal |

### 計画からの重要な変更：Waiting で `GetActions()` を止めない
計画では Waiting ごと 20Hz に落とす想定だったが、**`AV:MoveThruster` が
`DAV.dt_scale` を「呼び出し回数分」積分している**（av.lua:1164-1182）。
`GetActions()` まで 20Hz にするとスラスター復元が実時間で 5 倍遅くなる。
また保留中のホットキーがスロット待ちで遅延する。

そこで Waiting は **heavy 側（CheckAllEvents）だけ 20Hz** にした。

### 上記の正当化は弱い（実測で判明、未対応）
上記の理由づけはスラスターという**最も安い要素**に基づいていた。実測すると
Waiting の残りコストの大半は `GetActions()` 側にある
（`situation_cost_test` §12、100 tick あたりの C# 往復）:

| 内訳 | 往復 | 占比 |
|---|---|---|
| `CheckAllEvents` | 200（2.0/tick） | 22% |
| **`GetActions`** | **700（7.0/tick）** | **78%** |
| └ うち idle-gravity レイキャスト | 100（1.0/tick） | |

スラスター自体は定常状態の Waiting ではほぼ無料:
`thruster_angle` は既に 0 で、av.lua:1196 の dedup により **C# 書き込み 0 回**。
実際に復元が走る唯一のケースは「前方キーを押したまま降車した直後の過渡期」
で、`AV:Unmount()`（av.lua:826）が `thruster_angle` をリセットしないため、
`Operate({Idle})` → `MoveThruster` が唯一の復元経路になっている。

一方で `GetActions()` を**消せない**ことも分かった。設定キーの文言が決定的:

> `native_settings_general_idle_gravity` = **"Enable Descent of Waiting Vehicle"**
> "When enabled, it slowly approaches the ground while waiting."
> 待機中の車両の降下を有効にする — 有効にすると待機中にゆっくりと地面に近づきます

つまり `CalculateIdleMode`（engine.lua:768-779）のレイキャストと `Engine:Run`
による水平保持は、**Waiting 専用の仕様そのもの**であり死んだ仕事ではない。
ただしループ自体は遅い（damping 0.2 / height_gain 0.5 / 復元レート制限付き）
ので、間引いても体感差は出ない見込み。

**未決着**（要ユーザー判断・要実機検証）:
1. `GetActions()` を Waiting で 10Hz 間引き（仕様維持、約 -6.3 往復/tick）
2. 静止時完全停止 ＋ 降車時に `thruster_angle = 0`（最大削減、降下仕様は無効化）
3. 降車時 `thruster_angle` リセットのみ（`GetActions()` は現状維持）

→ **2026-10-03 ユーザー判断: 据え置き。** 上記 1〜3 はいずれも飛行挙動に
関わるため実機検証が前提。D群（HUD push 化）を先に実施する。
`situation_cost_test` §12 の実測セクションは残してあるので、着手時に
そのまま再計測できる。

### 追加した関数・フィールド（core.lua）
| 名前 | 役割 |
|---|---|
| `Core:ControlLoopState()` | 今 tick を走らせるか 3 段階で返す（純 Lua、C# を跨がない） |
| `Core:WakeControlLoop()` | `last_waiting_loop_time = 0` で次回 tick を必ず走らせる |
| `Core:ControlTick()` | 改修。sampler を先に回してからゲートを評価 |
| `waiting_loop_interval = 0.05` | Waiting の CheckAllEvents 周期（20Hz） |
| `last_waiting_loop_time` | 次回スロット時刻 |
| `is_control_loop_sleeping` | 可観測用フラグ |

**ゲートを開ける条件（優先順）**
1. `queue_obj` に保留入力が ある — ホットキーを人質に取らない
2. Landing / TalkingOff / InVehicle — 降下・上昇閾値と飛行制御は tick 周期依存
3. Waiting でスロット到達
4. Normal/Idle でガレージ heartbeat 期限（`last_garage_update_time + 30s`）

**situation change の再スロット**: `CheckAllEvents` の実行前後で
`current_situation` が変わっていたら `WakeControlLoop()` を呼ぶ。これで
InVehicle→Waiting などが次 tick で即反映され、`waiting_loop_interval` ぶん
待つことがない。`SetSituation` 側を触らずに全遷移を捕まえられる。

### 効果（100 tick = 1 秒あたりの body 実行回数）
| 状況 | 従来 | A群後 |
|---|---|---|
| Idle / Normal | 100 | **0**（heartbeat と入力時のみ） |
| Waiting | 100 | **17〜20**（CheckAllEvents）/ 100（GetActions） |
| Landing / TalkingOff / InVehicle | 100 | 100（変更なし） |

### テスト：`tests/loop_gate_test.lua`（新規 26 assertion）
`Core` を実 metatable + カウント用 event_obj / queue_obj で駆動し、
`ControlTick` / `ControlLoopState` が shipped のまま通ることを検証。

1. Idle / Normal で body が両方 0 回
2. ガレージ heartbeat で開き、refresh 後は閉じる
3. 保留入力がゲートに優先
4. Waiting: CheckAllEvents ~20/100、GetActions 100/100、入力時は即時
5. Landing / TalkingOff / InVehicle は 100/100 でスキップなし
6. situation change がループを起こし、その後 pacing が効く
7. 睡眠中も sampler が進み、dt_scale が安定（1 秒睡眠明けでスパイクなし）
8. Cron タイマーは halt も pause もされず、`Cron.After` が睡眠中も発火する

---

## 2. B群：常時タイマーの要求駆動化

### 2-1 `UpdateGarageInfo`（#3）を「UI が開いた時だけ」
現状は 1s 周期で `Game.GetVehicleSystem()` + `GetPlayerUnlockedVehicles()` を叩き、
クリア後セーブ（解錠 150〜200 台）では **1回で N 個の userdata を確保**する。
使われるのは Vehicle Manager / 召喚時の購入判定だけ。

**変更案**
- 周期ポーリングを廃し、次イベント時のみ `UpdateGarageInfo(true)` を呼ぶ。
  - `Core:OpenVehicleManager()`（core.lua:1303）の直前
  - `Core:SetSummonTrigger` の Override 内（`SpawnActivePlayerVehicle` 到達時）
  - `SessionStart`（既に `UpdateGarageInfo(true)` を呼んでいる／event.lua:181）
  - 車両購入イベントが取れるなら `Observe("VehicleSystem", "AddUnlockedVehicle")` で無効化フラグ
- 取りこぼし保険として **10Hz → 1回/30s** の遅い heartbeat を残す（1s の 1/30）。
  あるいは `is_garage_dirty` を UI 側で立てて、開く直前に必ず refresh する形なら heartbeat 不要。

**リスク**: 購入直後に未更新で召喚すると「未購入」判定になりうる。
→ 召喚経路は必ず force refresh するので実害なし。

### 2-2 `MaintainObstacleMapCache`（#4）を「機体が存在する時だけ」
`Core:EnsureObstacleMapPreloadTimer`（core.lua:264）は 20Hz で **セッション中ずっと**走る。
中身は `Game.GetPlayer()` + `GetWorldPosition()` + `FlushLearnedCellsToImage()`。
全 chunk 常駐（`IsFullResidencyActive()`）なら、**学習セルのフラッシュ以外に仕事が無い**
（navigation.lua:1366-1374 のコメントどおり）。

**変更案**
1. `AV:Spawn` 成功時 / `SessionStart` で起動、`AV:Despawn` で停止（`Cron.Halt`）。
2. 常駐モードのときは周期を **0.05s → 2〜5s** に落とす。
   フラッシュは「学習セルが溜まった時」だけでよいので、
   `if next(self.learned_cells) == nil then return end` を最上位に置き、
   空なら C# を 1 回も跨がない（`GetPlayer` より前に抜ける）。
3. 着地（`Waiting`）中はマップ更新が発生しないので停止、`InVehicle` で再開、が本筋。

**期待効果**: 未召喚・AFK 時の 20Hz×2C# 遷移/秒 が **0** になる。

### 2-3 LTBF 互換 poll（#6）を搭乗時のみ起動
`event.lua:196` の `Cron.Every(0.1)` は `DAV.is_valid_ltbf` なら **搭乗していなくても永久に**走り、
毎 tick `self:IsInVehicle()`（= Lua + `IsPlayerMounted` の C# 往復）で弾いているだけ。

**変更案**
- 登録をやめ、`CheckInAV` の enter 遷移（event.lua:510 付近）で起動、
  exit 遷移（event.lua:530 付近）で `Cron.Halt`。

---

## 2.9 B群 実装内容（2026-10-02 完了）

### 追加・変更した関数

| 箇所 | 内容 |
|---|---|
| `core.lua` `obj.garage_update_interval` | `1.0` → `30.0`（保険の heartbeat） |
| `Core:RequestGarageRefresh(reason)` | 新規。`UpdateGarageInfo(true)` を呼ぶ明示口 |
| `Core:OpenVehicleManager()` | 起動直前に `RequestGarageRefresh` |
| `Core:EnsureObstacleMapPreloadTimer` | タイマーハンドルを `obstacle_map_maintenance_timer` に保持。tick 内で `HasPendingMapWork()==false` なら **自走停止（park）** |
| `Core:WakeObstacleMapMaintenance()` | 新規。park 済みのタイマーを再起動（稼働中なら false） |
| `Core:StopObstacleMapMaintenance()` | 新規。`ReleaseObstacleMapSession()` から呼ぶ |
| `Navigation:HasPendingMapWork()` | 新規。**C# を 1 回も跨がない**純 Lua ゲート |
| `Navigation:WakeMapMaintenance()` | 新規。`nav -> av -> core` を辿って wake |
| `Navigation:NoteLearnedCellAdded()` | 新規。学習セルが閾値を超えた瞬間だけ wake |
| `Navigation:MaintainObstacleMapCache` | 冒頭に `HasPendingMapWork()` ゲート（idle なら `Game.GetPlayer()` すら叩かない） |
| `Navigation:StartObstacleMapFill` | park 済みタイマーを wake |
| `Event:StartLTBFCompatPoll` / `StopLTBFCompatPoll` | 新規。搭乗遷移で起動／降車遷移で停止 |
| `Event:StartLTBFThrusterCheck` / `StopLTBFThrusterCheck` | 新規。入れ子タイマーをハンドル管理 |
| `Event:CheckInAV` | enter で Start、exit で Stop |

`SetObstacleCell` / `SetObstacleCellNoDirty` の学習カウント加算箇所に
`NoteLearnedCellAdded()` を差し込んだ。

### 計画からの変更点
- **`AV:Despawn()` では停止しない。** 未 flush の学習セルがある状態で止めると、
  次回搭乗まで obstacle bin へのフラッシュが遅延し、そのまま終了すると
  **学習データが失われる**。`HasPendingMapWork()` ゲートで idle 時に自動 park する
  ため despawn 停止は不要と判断（効果同じ・リスク下）。
- **`ChangeGarageAVType` は `UpdateGarageInfo(false)` のまま。**
  購入状態を読まず type_index を書くだけなので force 化しなかった。
- **召喚 Override は force refresh なし。** `av_record_list` は MOD 側
  `all_models` から作られ、購入判定はゲーム側の `SpawnActivePlayerVehicle`
  呼び出し自体が担保している。
- LTBF は停止時に `is_ltbf_flight_active` を明示解除し `BlockOperation(false)` /
  widget flag を戻す。旧常時 poll は降車後に単に動作を止めるだけで
  `BlockOperation(true)` を残していたため、その改善も兼ねる。

### テスト
`tests/demand_driven_test.lua` + `tests/run_demand_driven_test.py`（新規、57 件全通過）
- §1 `HasPendingMapWork` の 7 状態
- §2 idle で park（`MaintainObstacleMapCache` に到達しない／タイマー死亡）
- §3 作業中は毎 tick 走る ／ §4 稼働中の wake は no-op（重複なし）
- §5 `StopObstacleMapMaintenance` の後始末
- §6 学習セル閾値超過で park から復帰
- §7 `StartObstacleMapFill` で復帰
- §8 実 `MaintainObstacleMapCache` が idle 時に `Game.GetPlayer` を呼ばない
- §9-10 LTBF poll の起動／停止／二重起動防止／停止時の state unwind
- §11 garage interval = 30s ／ `RequestGarageRefresh` が force で届く
- §12 `Event:Init` が前回インスタンスから引き継いだ poll を破棄する（リーク防止）


既存スイート全通過: situation 54 / enter_exit 52 / entity+height 31 /
meter_cadence 42 / axis_proxy 31 / onaction 40。

---

## 3. C群：InVehicle / Waiting のチェックをイベント or 低速化

### 3-1 搭乗／降車検知（#7）を mount イベントで駆動
`CheckInAV` は 100Hz で `IsPlayerMounted` を叩いているが、
ゲーム側には **`VehiclePuppet` の mount/unmount 系イベント**と、
既に MOD が握っている `VehicleTransition` フック（event.lua:290/308）がある。

**変更案（段階導入）**
1. 即効: `CheckInAV` を **20Hz に間引く**（`next_mount_check_time` を追加、
   既存の `CheckHeight` と同じ「次回時刻を保持して早期 return」型）。
2. 本命: `Observe("VehiclePuppet", "OnMountingEvent")` / `"OnUnmountedEvent"`
   （または `VehicleComponentPS` の mount 系）で `Event:OnMounted()` /
   `Event:OnUnmounted()` を直接呼び、`CheckInAV` を **保険の 2Hz ハートビート**に落とす。
   降車経路は `IsUnmountDirectionClosest` フックが既に `Unmount()` を呼んでいるので、
   降車側はほぼイベント化済み。

### 3-2 ドア状態（#8）
`CheckDoor` は 100Hz で `GetVehiclePS` + `GetDoorState`。
`GetHasAnyDoorOpen` の Override（event.lua:276）が既に **ドア状態の読み取り経路を握っている**
ので、そこで last door state を記録しておけばポーリング不要になる。

**変更案**
- `CheckDoor` を **5〜10Hz** に間引く（開閉は人間操作、100Hz 不要）。
- 加えて `ChangeDoorState` 呼び出し時に `self.last_known_door_state` を更新し、
  差分が無ければ読みに行かない。

### 3-3 エンジン状態（#9）
`CheckEngine` は 100Hz で `IsEngineTurnedOn`。エンジンが切れるのは
爆発／イベント時だけで、切れていれば即 `TurnEngineOn(true)` するだけの処理。
→ **5Hz で十分**。`CheckDestroyed`（同 100Hz）と 90% 重複しているので
  単一の "liveness" チェックに統合すれば 1 往復/tick 浮く（fix 計画 ⑦ と同じ指摘）。

### 3-4 コンバット状態（#10）
`CheckCombat` は 100Hz で `Game.GetPlayer()` + `PSIsInDriverCombat()`。
`Game.GetPlayer()` は **frame cache 済み**（fix 1）だが往復自体は残る。
→ **5Hz 間引き**。状態変化時のみ `ChangeDoorState` / hint 更新なので体感差なし。

### 3-5 消費アイテム枠（#11）
`IsVisibleConsumeItemSlot` は **pcall + `GetRootCompoundWidget().visible`** を 100Hz。
`SetVisibleConsumeItemSlot(false)` は `ShowLeftBottomHUD()` で既に一度やっている
（hud.lua:307）。搭乗中にゲームが再び表示しないか張っているだけ。

## 3.9 C群 実装内容（2026-10-02 完了）

### 共通機構：`Event:DueNow(field, interval)`
`CheckHeight` が既に使っていた「次回時刻を保持して早期 return」型を
ヘルパーに抽出した（event.lua）。`os.clock()` は CPU 時間なので、
プロセスが詰まっているときは全チェックが自動的に間隔を延ばす。
間隔はすべて `Event:New()` のインスタンスフィールドにして調整可能にした。

| 項目 | 計画 | 実装 | 追加フィールド |
|---|---|---|---|
| C-1 `CheckInAV` | 20Hz | **20Hz** | `mount_check_interval = 0.05` |
| C-2 `CheckDoor` | 5〜10Hz | **10Hz** | `door_check_interval = 0.1` |
| C-3 `CheckEngine` | 5Hz | **5Hz** | `engine_check_interval = 0.2` |
| C-3 `CheckDestroyed` | 統合 | **10Hz**（据え置き低速化） | `destroyed_check_interval = 0.1` |
| C-4 `CheckCombat` | 5Hz | **5Hz** | `combat_check_interval = 0.2` |
| C-5 消費アイテム枠 | 低速化 | **1Hz** | `consume_slot_check_interval = 1.0` |
| C-6 入口エリア（追加） | — | **20Hz** | `AV.entry_area_check_interval = 0.05` |

### 計画からの変更点
- **C-1 の本命（mount イベント化）は見送り。** 間引きだけで 100Hz→20Hz に
  なっており、`VehiclePuppet` の Override 追加は効果/リスク比が合わない。
  降車側は `IsUnmountDirectionClosest` フックが既に `Unmount()` を呼ぶため
  イベント化済みであり、張っているのは搭乗検知の 50ms だけ。
- **C-3 の liveness 統合は見送り。** `CheckEngine` と `CheckDestroyed` は
  それぞれ 5Hz／10Hz に落ちた時点で計 0.15 往復/秒。統合でさらに 0.05
  往復/秒 しか浮かず、両者の後始末（`Reset` 相当）を1関数に寄せるリスクが
  見合わない。
- **C-6 を追加した。** C群を適用した後に計測すると、Waiting が InVehicle より
  高コストになった（13.6 vs 12.6 往復/tick）。犯人は入口エリアの再計算で、
  frame cache は「1 tick 内の重複」を消すだけで、Waiting ループは毎 tick
  再計算していた。`AV:IsPlayerInEntryArea()` に 20Hz の時間間引きの cache を
  追加し、Waiting を 9.6 まで下げて invariant を回復させた。
- **`AV:InvalidateEntryAreaCache()` を追加。** 時間 cache を入れたことで
  「機体を動かした／プレイヤーを転送した」時に stale 値を引く経路が生まれた。
  `AV:Despawn()` で必ず無効化する。テスト側もプレイヤー位置を切り替える度に
  呼んでいる（`situation_cost_test` の `player_in_entry_area()`）。

### 効果（situation_cost_test 実測、往復/tick）
| 状況 | 最適化前 | C群後 | 削減 |
|---|---|---|---|
| Waiting（入口に立っている） | 67.0 | 9.9 | 85.3% |
| Waiting（離れている） | 37.0 | 9.6 | 74.0% |
| InVehicle（手動） | 31.7 | 12.6 | 60.2% |
| Landing | 5.0 | 3.2 | 36.4% |

### テスト
- `tests/demand_driven_test.lua` §13〜§15（新規 16 assertion）
  - §13: `Engine:Update` の dead-entity ゲート
  - §14: C-1〜C-5 の実際の実行回数（100 tick に対し 20/10/5/10/5/1）
  - §15: C-6 の入口エリア間引きと invalidate
- `situation_cost_test` §4 は pre-fix 基準から C-2 の間引きを切り離すため
  計測中だけ `door_check_interval = 0` にして 200 回/tick 基準を維持。
- 全 7スイート 324 assertion 合格。

---

## 4. D群：HUD を push 型にする（CheckHUD ポーリングの廃止）

### 4-1 速度／RPM（#12）
MOD は既に `Override("hudCarController","OnSpeedValueChanged")` と
`OnRpmValueChanged` を握っている（hud.lua:147/159）。
現状この Override は「**我々が手動設定している間は game の書き込みを握り潰す**」
ためだけに使われ、値の供給は `CheckHUD` が 100Hz で
`GetCurrentSpeed()`（= `GetVelocity`+`GetAngularVelocity`+`Vector3To4`+`Length` の 4 往復）
→ `SetSpeedMeterValue` を回している。

**変更案**
```lua
Override("hudCarController", "OnSpeedValueChanged", function(_, speedValue, wrappedMethod)
    if DAV.core_obj.event_obj:IsInAVSituation() and self.is_manually_setting_speed then
        -- game が教えてくれた値をそのまま供給源にする。自前の 4 往復が不要。
        self:SetSpeedMeterValue(FromGameSpeed(speedValue))
        return true   -- 我々が描画した、で握り潰す
    end
    return wrappedMethod(speedValue)
end)
```
- 供給元が game の change イベントになるので、**値が変わった時だけ**走る。
  既存の表示値ラッチ（`last_speed_display_value`）と相性が良く、書き込みはさらに減る。
- `CheckHUD` 側は速度/RPM 供給を削除し、**状況変化時の 1 回だけ**の初期化に残す。
- RPM 進捗ゲージ（autopilot）は game の RPM とは無関係なので、
  進捗が変わった時だけ `SetRPMMeterValue` を呼ぶよう Navigation 側から push。

### 4-2 HP（#12 の続き）
`Observe("VehicleComponent","ReactToHPChange")`（hud.lua:220）で既に `vehicle_hp` は更新済み。
`SetHPDisplay` はラッチ付きだが、**呼ばれること自体が 100Hz**。
→ `ReactToHPChange` の中で直接 `self:SetHPDisplay()` を呼び、`CheckHUD` から外す。

### 4-3 入力ヒント（#13）
`CheckInput` は 2s 周期で `IsVisibleCustomInputHints()`（widget ツリー走査＋pcall）を回し、
消されていたら再構築している。
→ `ObserveAfter("UISystem","QueueEvent")` でヒント消去イベントを既に捕捉できる
   （hud.lua:242 の既存フックと同じ口）。消去を検知した時だけ再構築し、
   周期チェックは **10s の保険** or 完全撤去。

### 4-4 疑似ポーリング（#14 #15）— C# を跨がないだけの無駄
> **⚠️ 実測済（2026-10-03）: この 3 つは C# を 1 回も跨いでいなかった**
> （`situation_cost_test` §13 で 100 tick あたり **0 往復**）。
> イベント化しても削減量は 0 なので**変更していない**。詳細は §4-9 を参照。
- `CheckAutoModeChange`: 読み元は `av_obj.is_auto_pilot`（Lua）。
  設定箇所は `navigation.lua:3496`（開始）と `4633/4652`（終了）の 3 箇所だけ。
  → 設定時に `Event:OnAutoModeChanged(bool)` を呼べば **100Hz ポーリングは完全撤去可**。
- `CheckFailAutoPilot`: `is_failture_auto_pilot` の consume-and-clear を 100Hz で回している。
  → `InterruptAutoPilot()` 内で直接 HUD を出せばよい（`IsFailedAutoPilot()` は撤去）。
- `CheckPerspective`: `GetCurrentCameraDistanceLevel()` は `self.current_camera_mode`
  という **Lua フィールドを読むだけ**（camera.lua:189）。
  → 変化は `Camera:ChangePosition/Toggle` の時だけなので、そこで push。
  現状は「Lua フィールド比較を 100Hz しているだけ」で安いが、
  上記とまとめて **イベント化すれば tick 自体が減る**。

---

## 4-9. D群 実装内容（2026-10-03）

### 実測が計画の前提を崩した
`tests/situation_cost_test.lua` §13 で InVehicle の `CheckHUD` を分解した結果:

| 内訳（100 tick あたり） | 実装前 | 実装後 |
|---|---|---|
| `flyav.GetVelocity` | 100 | **20** |
| `flyav.GetAngularVelocity` | 100 | **0** |
| Settings / Text / Widget | 5 | 5 |
| **CheckHUD 合計** | **205（2.05/tick）** | **25（0.25/tick）** |
| `CheckAutoModeChange`+`CheckFailAutoPilot`+`CheckPerspective` | 0 | **0** |

**計画 §4-4 の「疑似ポーリング 3 種」は C# を 1 回も跨いでいなかった**（読み元が
全部 Lua フィールドで、ラッチ済み）。イベント化しても削減量は 0 なので
**変更せず、実測値をテストに記録した**。ここに工数を使うより他に余地がある。

### D-1 速度読み出し（`av.lua:413` `AV:GetCurrentSpeed`）
`GetDirectionAndAngularVelocity()` を呼んで **角速度を `_` で捨てていた**。
速度計は線形速度しか見ないので、角速度の C# 往復は丸ごと無駄。
既存の `Engine:GetVelocity()`（CheckHeight 用に追加済み）に切り替え、
nil は 0 として扱う。**1 往復/tick → 20 往復/100 tick**。

さらに `CheckHUD` 全体を **20Hz**（`hud_check_interval = 0.05`）に間引いた。
表示値は `math.floor(speed * unit_factor)` の整数なので、50ms の遅延は
「動いている数値」に対しては知覚不能。RPM ダイヤ・autopilot 進捗ゲージも
同様に整数。

### 計画の「game の OnSpeedValueChanged を供給源にする」案は不採用
理由:
1. 本 MOD の機体は独自 `FlyAVSystem` が駆動しており、game の `speedValue`
   がそれに追従していることを**オフラインで証明できない**
2. 追従が止まると**速度計が飛行中に凍る** — 節約できる往復より遥かに重い障害
3. `speedValue` の単位が `SetSpeedMeterValue` の期待する m/s と
   一致する保証がない（game は settings を見て自前で変換している可能性）

Override 側の「手動設定中は game の書き込みを握り潰す」挙動はそのまま維持。

### D-2 HP の push 化（`hud.lua:225` `ReactToHPChange`）
`ReactToHPChange` は game が HP の変化時にだけ呼ぶ本物の change event。
そこで `vehicle_hp` を更新した直後に `self:SetHPDisplay()` を呼ぶようになり、
`CheckHUD` からの呼び出しを削除。**HP 表示は「1 搭乗で数回」の頻度でしか
走らない**（従来は 100 回/秒）。既存の `last_hp_display_value` ラッチと
`ShowLeftBottomHUD` からの初期描画はそのまま。

### 効果（situation_cost_test §8 実測・往復/tick）
| 状況 | 最適化前 | D群後 |
|---|---|---|
| InVehicle（手動） | 29.9 | **10.8** |

CheckHUD 単体の −1.80/tick がそのまま全体に出ている。

### テスト（`situation_cost_test` §13、新規 8 assertion）
- 捨てられていた角速度読み出しが消えた（0 回）
- 速度読み出しが 20Hz（ちょうど 20/100 tick）
- C-5 の consume-slot walk は 20Hz ゲート内でも 1Hz を維持
- HP が `CheckHUD` から一切描画されない（ラッチが触られない）
- push された HP が正しく widget に届く（`87` → `" 87"`）
- 同一値の繰り返しは書き込み 0
- 値が変われば再度書き込む
- 疑似ポーリング 3 種が 0 往復（＝変更不要であることの固定）

---

## 5. 効果まとめ（1 秒あたり C# 往復・実測）

`tests/situation_cost_test.lua` §8 の実測値（1 tick = 10ms、100 tick = 1 秒）。

| 状況 | 最適化前 | 現在（B+§1.5+C+A+D） | 削減 |
|---|---|---|---|
| Normal（未召喚） | 1.0 | 1.0 | — |
| Landing | 5.0 | 3.2 | 36.4% |
| Waiting（入口に立っている） | 67.0 | 9.9 | 85.3% |
| Waiting（離れている） | 37.0 | 9.6 | 74.0% |
| TalkingOff（降車中） | 5.0 | 2.2 | 56.0% |
| InVehicle（手動飛行） | 29.9 | 10.8 | 63.8% |

※ 上記は `CheckAllEvents` + `GetActions` + `Engine:Update` を通した実測で、
   計画当初の概算（「数十/s」等）に代わるものとしてこの表を正とする。
※ A群により Idle / Normal ではループ body が 0 回になるため、
   「未召喚 ~0」は §loop_gate_test で別途検証済み。

---

---

## 6. 実装順序と検証

1. **B群**（単独で安全・効果大）→ ✅ **実装済み**（§2.9 参照）。確認は
   `python tests/run_demand_driven_test.py` で未召喚時の遷移数・常駐量をを確認
2. **§1.5 Engine:Update ゲート**（1 行、バグ修正を兼ねる）→ ✅ **実装済み**
   （`Engine:Update` 先頭に `av_obj.entity_id` ゲート。検証 §13）
3. **C群の間引き系**（3-1〜3-5）→ ✅ **実装済み**（§3.9 参照。C-6 追加）
   → `tests/situation_cost_test.lua` の期待値は更新済み
4. **A群**（ControlTick 先頭ゲート方式）→ ✅ **実装済み**（§1.9 参照）
   - 新規テスト `tests/loop_gate_test.lua`（26 assertion）
   - 未召喚で CheckAllEvents が 0 回 / 復帰後再開 / Cron.After が死なないこと → 検証済
5. **D群**（HUD push 化）→ ✅ **実装済み**（§4-9 参照）
   - D-1 速度読み出し: 捨てていた角速度を除去 + 20Hz 間引き（2.05 → 0.25 往復/tick）
   - D-2 HP: `ReactToHPChange` から push（`CheckHUD` から完全削除）
   - D-4 疑似ポーリング 3 種は **実測 0 往復**のため変更せず（§4-9 に理由）
   - 検証: `tests/situation_cost_test.lua` §13（新規 8 assertion）

既存テスト（回帰ゲート）: `loop_gate_test` `demand_driven_test` `situation_cost_test`
`enter_exit_cost_test` `meter_cadence_test` `entity_cache_test` `axis_proxy_cost_test`
`height_cache_test` `onaction_cost_test` + `tools/check_lua_syntax.py`

---

## 7. 触らないほうがよいポーリング（イベントが存在しないもの）

- `Engine:Update` 自体（毎フレームの力積注入。物理なのでフレーム同期が正しい）
- autopilot の巡航ループ（`navigation.lua:3774`）— 制御ループそのもの
- `IsOnGround()`（navigation.lua:3402 のコメントどおり、対応イベントが存在しない）
- spawn/despawn の降下・上昇シーケンス（閾値判定が tick 周期依存、`TimeScale:Lead` で補正済み）
- `StartButtonHold` の保持計測（キー release は取れるが「保持時間」は自分で刻むしかない）
  → ただし `hold_time_resolution` は 0.1s で既に妥当
