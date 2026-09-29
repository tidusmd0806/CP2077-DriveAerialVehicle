# 性能解析：なぜ InVehicle より Waiting / Landing / Leaving の方が重かったのか

対象: DriveAerialVehicle v3.3.1
計測: `tests/situation_cost_test.lua`（実モジュール + C# API スタブ、遷移回数を実測）
関連: `PERFORMANCE_FIX_PLAN.md` fix (1)〜(15)、`PERF_ANALYSIS_init441.md`、`PERF_ANALYSIS_hooks.md`
本ドキュメントの修正は通し番号で **fix (16)〜(20)**

---

## 0. 報告された現象

> 負荷測定をして気づいたことは、InVehicle よりも Wait や landing、leaving の
> situation の方が処理負荷が高いです。これは間隔に反します。
> なので wait などの区間で必要以上の呼び出しや処理が発生しているのではないか
> と疑っています。

**疑いは的中。しかも主犯は 1 つだった。**

待機中にプレイヤーが車の近くに立っているとき、MOD は **100Hz で搭乗選択肢
UI を毎回フル再構築し、ハブを再アクティベートしていた**。

---

## 1. 実測（situation cost ledger）

実 `core / event / av / engine / hud` を Lua 上でロードし、C# API 呼び出しを
全てカウント。修正前（git HEAD の実装をそのまま書き写したもの）と修正後を
**同じワールド状態で** 100 tick 走らせた。

| situation | 修正前 /tick | 修正後 /tick | 削減 |
|---|---:|---:|---:|
| Normal（未召喚） | 1.0 | 1.0 | 0% |
| Landing | 5.0 | 5.0 | 0% |
| **Waiting（プレイヤーが搭乗エリア内）** | **75.0** | **19.5** | **−74.1%** |
| Waiting（プレイヤー離れている） | 45.0 | 19.1 | −57.6% |
| TalkingOff（leaving） | 5.0 | 4.1 | −18.0% |
| InVehicle（手動飛行） | 39.1 | 22.0 | −43.8% |

**修正前：Waiting(エリア内) 75.0 vs InVehicle 39.1 ＝ 1.9 倍。**
報告どおりの逆転が、そのまま再現された。

「間隔に反する」のではなく、**待機中にしか走らない処理が、飛行中の全処理より
高かった**。

---

## 2. 根本原因

### ① 選択肢ハブの 100Hz 再構築（最大項）

`Event:CheckInEntryArea()`（修正前）:

```lua
function Event:CheckInEntryArea()
    if self.av_obj:IsPlayerInEntryArea() then
        self.hud_obj:ShowChoice(self.selected_seat_index)   -- 毎 tick
    else
        self.hud_obj:HideChoice()
    end
end
```

`HUD:ShowChoice()` は**状態を比較せずに毎回フル構築**する:

| 処理 | 内容 |
|---|---|
| `SetChoiceList()` | `gameinteractionsvisListChoiceHubData.new()`、`GetChoiceTitle()`（`GetLocalizedText`）、`gameinteractionsChoiceTypeWrapper.new()` + `SetType` |
| 座席ループ（N 席） | 席ごとに `ChoiceCaption.new()` / `ListChoiceData.new()` / `GetLocalizedText` / `GetTranslationText` / `TweakDBInterface.GetChoiceCaptionIconPartRecord` / `AddPartFromRecord` / `CName.new("None")` ＝ **約 7 遷移 × N 席** |
| ブラックボード | `GetAllBlackboardDefs()` / `GetBlackboardSystem():Get()` / `SetInt` / `GetVariant` |
| UI 起動 | `OnDialogsSelectIndex` / `OnDialogsData` / `OnInteractionsChanged` / `UpdateListBlackboard` / `OnDialogsActivateHub` |
| 毎回 | `pcall` + 無名クロージャ確保、`hub.id = 77777 + math.random(99999)`（**毎回新しいハブ ID**） |

**1 回で約 40 遷移。** 100Hz なので **約 4000 遷移/秒**を、
変化のまったくない選択肢 UI の再表示だけに使っていた。

実測（100 tick 待機・エリア内）:

```
修正前: 7511 遷移 / 100 回ハブ起動 / 300 席分行構築   (3席 × 100 tick)
修正後: 1946 遷移 /   1 回ハブ起動 /   3 席分行構築
```

### ② 搭乗エリア判定を 1 tick に 2 回やっていた

`Event:CheckInEntryArea()` と `Event:CheckDoor()`（→ `Event:IsInEntryArea()`）が
**同じ tick でそれぞれ** `AV:IsPlayerInEntryArea()` を呼ぶ。

1 回の cost: `GetPosition` + `Vector4:IsZero` + `GetQuaternion` +
`Game.GetPlayer` + `GetWorldPosition` ＝ **約 5 遷移**、
加えて `Utils:RotateVectorByQuaternion` が **Lua テーブル 9 個**（共役・
`{r=0,...}` リテラル・`QuaternionMultiply`×2・戻り値）。

### ③ スラスター角度が変わらなくても毎 tick 書き込んでいた

`AV:MoveThruster()` は 100Hz で:

```lua
local angle = EulerAngles.new(0, self.thruster_angle, 0)
for _, component in pairs(self.engine_components) do
    component:SetLocalOrientation(angle:ToQuat())     -- ToQuat がループ内
end
for _, thruster in pairs(self.thruster_fxs) do
    thruster:SetLocalOrientation(angle:ToQuat())
end
```

エンジン 4 + fx 4 ＝ **1 tick に 16 書き込み + 8 ToQuat**。
待機中は `thruster_angle == 0` で**値が一切動かないのに**、である。
`is_available_thruster` が true の車両（Excalibur / Atlus / Surveyor 等）で常時。

### ④ 離陸アニメ中に、捨て値のために地面を叩いていた

`AV:DespawnFromGround()`（leaving）の 100Hz タイマー:

```lua
local _, _, _, roll_idle, pitch_idle, yaw_idle =
    self.engine_obj:CalculateAddVelocity({Def.ActionList.Idle, 1})
self.engine_obj:OnlyAngularRun(roll_idle, pitch_idle, yaw_idle)
```

`CalculateAddVelocity(Idle)` → `CalculateIdleMode()` は
**線形項（アイドルホバー）まで計算**する。そのために
`IsCollision()` → `fly_av_system:IsOnGround()`、
`GetDirectionAndAngularVelocity()`（2 遷移）、
`Navigation:GetHeight()` → **同期レイキャスト 1 本**を毎 tick 実行する。

しかし呼び出し側は **x / y / z を捨てている**（`OnlyAngularRun` は角速度しか見ない）。
**毎 tick レイキャスト 1 本が完全に無駄**だった。

### ⑤ 人間が気づくより遅い変化を 100Hz で張っていた

| チェック | 実際の効果 | 修正前の頻度 |
|---|---|---|
| `CheckDistance` | 30m 超でエンジン音 ON/OFF | `GetPlayer`+`GetWorldPosition`+`GetPosition`+`Distance` を毎 tick |
| `CheckLockedSave` | TalkingOff 中の保存ロック除去 | `Game.IsSavingLocked()` を毎 tick |

どちらも 0.5 秒／0.1 秒解度で体感差ゼロ。

---

## 3. 修正

### fix (16)：選択肢ハブのエッジトリガー化（`Modules/event.lua`）

`CheckInEntryArea` を「**表示状態が変わったときだけ**」に変更。

```lua
function Event:CheckInEntryArea()
    if self.av_obj:IsPlayerInEntryArea() then
        local shown = (self.hud_obj.interaction_hub ~= nil)   -- HUD 自身の記録
        local now = os.clock()
        if not shown
            or self.shown_seat_index ~= self.selected_seat_index
            or (self.choice_keepalive_interval > 0
                and (now - self.choice_last_shown_time) >= self.choice_keepalive_interval) then
            self.hud_obj:ShowChoice(self.selected_seat_index)
            self.shown_seat_index = self.selected_seat_index
            self.choice_last_shown_time = now
        end
    elseif self.hud_obj.interaction_hub ~= nil then
        self.hud_obj:HideChoice()
        self.shown_seat_index = nil
    end
end
```

- 搭乗エリアに入った瞬間 → 即時表示（遅延なし）
- `SelectUp/Down` で座席が変わった瞬間 → 即時更新
- それ以外 → `choice_keepalive_interval`（既定 **1.0 秒**）に 1 回だけ再 push

**keep-alive を残した理由**：`HUD:SetOverride()` の
`OnDialogsActivateHub` / `OnDialogsData` オーバーライドが、ゲーム側の UI 更新時に
ハブを差し込む役目を担っている。メニューが被さった後などにハブが落ちても
1 秒以内に自己回復する。1Hz でも修正前の **1/100**。
`choice_keepalive_interval = 0` で完全に無効化できる。

`shown` の判定に `hud_obj.interaction_hub` を使っているのは、
**HUD 自身の状態を真実の源**にするため。他の経路（`CheckInAV` 等）が
`HideChoice()` を呼んでも自動的に再表示対象になる。

### fix (17)：`AV:IsPlayerInEntryArea` のフレームキャッシュ（`Modules/av.lua`）

エンティティハンドルキャッシュ（fix (1)）と同じ方式。
本体は `AV:ComputePlayerInEntryArea()` に移し、`IsPlayerInEntryArea()` が
`DAV.frame_seq` 単位でキャッシュする。

- 1 tick に 2 回呼ばれても計算は 1 回
- `InvalidateEntityCache()`（Spawn/Despawn）で同時に無効化
- `DAV.frame_seq` が無い環境ではキャッシュせず従来どおり毎回計算

### fix (18)：`AV:MoveThruster` の不要書き込み除去（`Modules/av.lua`）

- クランプ後に `self.thruster_angle == self._thruster_written_angle` なら**書き込み自体をスキップ**
- `ToQuat()` をループ外に 1 回出す（旧：コンポーネント毎に生成）
- `SetThrusterComponent()` で `_thruster_written_angle = nil` にし、
  外観変更後に再取得したコンポーネントへ必ず 1 回書き込ませる

角度が動いている間は従来どおり全コンポーネントに毎 tick 届く。

### fix (19)：離陸アニメで線形項を計算しない（`Modules/engine.lua` / `av.lua`）

`Engine:CalculateAddVelocity(action_command_list, skip_linear)` と
`Engine:CalculateIdleMode(skip_linear)` を追加。
`DespawnFromGround` は `skip_linear = true` で呼ぶ。

```lua
if not skip_linear and DAV.user_setting_table.is_enable_idle_gravity
   and not self.av_obj.navigation_obj:IsCollision() then
```

既存の呼び出し（`AV:Operate` 経由）は第 2 引数を渡さないため**挙動不変**。

### fix (20)：CheckDistance / CheckLockedSave の間引き（`Modules/event.lua`）

`distance_check_interval = 0.5` / `locked_save_check_interval = 0.1` を追加。
`CheckHeight` の VFX 位置書き込みも、**計測高さが動いたときだけ**行う
（着地中は毎 tick 同じ高さになる）。

---

## 4. 検証

`python tests/run_situation_cost_test.py` — **38 passed, 0 failed**

| 節 | 検証内容 |
|---|---|
| 1 | ハーネス健全性（実モジュールロード、4 engine + 4 thruster、Def.SituationName） |
| **2** | **可視状態の同値**：接近→待機→座席変更→離脱→再接近の 13 ステップで、修正前と修正後の「ハブが表示されているか・選択 index」が**全ステップで一致** |
| 3 | 100 tick 待機：修正前は座席行 300 構築／修正後は ≤6。総遷移 −60% 以上 |
| 4 | 搭乗エリア計算：修正前 2.00 回/tick → 修正後 ≤1.00 回/tick |
| 5 | スラスター書き込み：修正前 800 回/100 tick → 待機時は ≤8 回。**角度が動けば 80 回全到達**、`ToQuat` は 10 tick で 10 回（1 回/tick） |
| 6 | leaving：修正前は 100 tick でレイキャスト 100 本 → 修正後 0 本 |
| 7 | 間引き：`CheckDistance` 100→2、`CheckLockedSave` 100→10。**どちらも実行はされている** |
| **8** | **状況別合計：どの situation も InVehicle を超えないこと** |
| 9 | situation ledger 自体の動作：起動／`Prof.enabled` 非依存／二重起動 no-op／ラップ後に 50 tick 無エラー／`Waiting/*` セクションが記録されること／オフ後もループが動き続けること |

第 2 節が最重要。「呼び出し回数を減らした」ではなく
**「プレイヤーに見える状態がどの瞬間でも同一」**ことを検証している。

### テスト中に検出した実バグ（`Modules/profprobe.lua`）

**① ラッパが戻り値を 5 個で切っていた**

`wrap_methods`（既存）も新規の `wrap_by_situation` も、
`local a,b,c,d,e = orig(self, ...)` で返していた。`CalculateAddVelocity` は
**6 値**を返すので、ラップした瞬間に **`yaw` が消える**：

```
Modules/av.lua:879: attempt to perform arithmetic on local 'yaw' (a nil value)
```

8 スロットに拡大。既存の `wrap_methods` も同じ穴だったので同時に修正した。

**② `Prof.enabled` が situation ledger を巻き込んで消える**

`Prof.finish` は `Prof.enabled` で門を開ける。ところが `Navigation:New()` が
`Prof.enabled = (DAV.is_debug_profile_autopilot ~= false)` を **AV 再初期化ごとに**
実行するため、`is_debug_profile_autopilot = false`（既定）だと ledger の計測も
一緒に止まる。

→ `Prof.finish_forced()`（`Prof.enabled` を見ない）を追加し、
`wrap_by_situation` はそちらへ回した。`Prof.finish` は従来どおり
`Prof.enabled` ゲートで `finish_forced` を呼ぶ。

既存テストへの影響：
`run_entity_cache_test.py` / `run_height_cache_test.py` / `run_onaction_cost_test.py`
/ `run_axis_proxy_cost_test.py` すべて従来どおり pass。

> `run_resident_cache_test.py` / `run_grid_integration_test.py` /
> `run_full_residency_bench.py` は `Data/map`（テキスト形式）をコピーしようとして
> 失敗する。packed-only 移行（fix 4U/4V）でそのディレクトリが消えているためで、
> 本変更とは無関係の既存事象。

---

## 5. 実機での確認（situation ledger）

状況別の集計をゲーム内ログに出す仕組みを追加した。
`init.lua` のフラグを `true` にして起動する:

```lua
DAV = {
    ...
    is_debug_situation_ledger = true,
}
```

`Event.EnableSituationLedger()` が `Event` の全 Check、`AV` の主要 accessor、
`Engine` の制御関数、`Core:GetActions / OperateAerialVehicle` を
**situation 名付きで**ラップし、15 秒ごとに集計表を出す。

```
===== PROBE SUMMARY periodic =====
  section                          calls   total_ms    avg_ms   max_ms    >=8ms
  Waiting/CheckInEntryArea           1500      ...
  Waiting/CheckAllEvents            1500      ...      ← 状況全体の総額
  InVehicle/CheckAllEvents          1500      ...
  ...
```

`Waiting/CheckAllEvents` と `InVehicle/CheckAllEvents` を直接比べられる。
`Prof.situation_enabled` は `Prof.enabled`（autopilot プロファイル）とは
**独立**。`Navigation:New()` が `Prof.enabled` を毎回再設定するため。

---

## 6. 残っているもの（意図的に見送った）

| 項目 | 現状 | 判断 |
|---|---|---|
| `Engine:Update` の `GetPhysicsState()` 每フレーム | 1 遷移/frame | 物理リセットの監視役。間引くと外部リセットの検知が遅れる |
| `Engine:Update` の `ChangeVelocity`（待機中） | 1 遷移/frame | 待機中の機体を** pinned にしている本体**。消すと機体が押されて動く |
| `Utils:CalculateRotationalSpeed` の行列アロケーション | 呼び出し毎に 3×3 行列 3 本 + α | 純 Lua。GC 圧には効くが、使い回しはネスト呼び出しとの相互作用の確認が必要 |
| `CheckDoor` の `GetDoorState` 每 tick | 2 遷移/tick | ドアが外部から開けられた検知に必要。20Hz 化は可能だが体感差との相談 |
| `GetEulerAngles` の戻り値の読み取り専用前提 | 今フレームは同一オブジェクトを返す | 現コードに書き込み箇所は無い。将来の改修時に注意 |

---

## 7. 変更ファイル

| ファイル | 変更 |
|---|---|
| `Modules/event.lua` | `CheckInEntryArea` エッジトリガー化／`CheckDistance`・`CheckLockedSave` 間引き／`CheckHeight` の VFX 書き込み抑止／`EnableSituationLedger` 追加 |
| `Modules/av.lua` | `IsPlayerInEntryArea` フレームキャッシュ（本体は `ComputePlayerInEntryArea`）／`GetEulerAngles` フレームキャッシュ／`MoveThruster` 不要書き込み除去・`ToQuat` 1 回化／`SetThrusterComponent` で書込マーカー初期化／`DespawnFromGround` で `skip_linear` |
| `Modules/engine.lua` | `CalculateAddVelocity` / `CalculateIdleMode` に `skip_linear` 追加 |
| `Modules/profprobe.lua` | `Prof.wrap_by_situation` 追加（`Prof.situation_enabled` で独立制御）／`Prof.section_names` 追加／`Prof.finish_forced` 追加／ラッパの戻り値を 8 スロットに拡大 |
| `Etc/def.lua` | `Def.SituationName`（逆引きマップ）追加 |
| `init.lua` | `DAV.is_debug_situation_ledger` フラグと `EnableSituationLedger(Core)` 呼び出し |
| `tests/situation_cost_test.lua` | 新規（38 assertions → 実機ログ解析で 54 に拡張） |
| `tests/run_situation_cost_test.py` | 新規ランナー |

---

# 第2部：実機ログによる追跡（fix 21 / 22）

`DAV.is_debug_situation_ledger = true` で実機から取った `DriveAerialVehicle.log`
（466 行、約 2 分）を解析した結果。**第1部の修正では消えていなかった症状の真因**
が判明した。

## 8. per-tick では Waiting は InVehicle より「軽い」

ログの累計カウンタをウィンドウ差分にして、上レベル2つ
（`CheckAllEvents` と `GetActions`、この2つは兄弟でネストしていない）を集計：

| window | 状況 | tick/s | top-level ms/s | **µs/tick** | frames/s | tick/frame |
|---|---|---:|---:|---:|---:|---:|
| 23:35:33 | Idle | 109.4 | 0.33 | 3.0 | 470.1 | 0.23 |
| 23:36:04 | Landing | 8.9 | 0.81 | 91.5 | 8.9 | 1.00 |
| 23:36:19 | InVehicle | 17.9 | 4.93 | **276.1** | 17.9 | 1.00 |
| 23:36:34 | Waiting | 270.1 | 17.07 | **63.2** | 270.0 | 1.00 |
| 23:36:49 | Waiting | 126.5 | 5.60 | **44.3** | 706.2 | 0.18 |
| 23:37:04 | Waiting | 90.4 | 6.27 | **69.3** | 593.9 | 0.15 |
| 23:37:19 | InVehicle | 18.9 | 5.33 | **282.7** | 18.9 | 1.00 |

**1回あたりでは Waiting(44〜69µs) は InVehicle(276〜283µs) の 1/4〜1/6。**
体積で重く見えたのは tick 数が最大 15 倍違っていたためだった。

## 9. 真因：メニュー中の `OperateAerialVehicle` Waiting 分岐にガードが無かった

`CheckAllEvents` の呼ばれた回数と、その Waiting 分岐が実際に走らせた
サブチェックの回数を比べると一発で決着した：

| window | CheckAllEvents | CheckDespawn 実行 | **メニュー中だった割合** |
|---|---:|---:|---:|
| 23:36:19 | 26 | 26 | 0.0% |
| 23:36:34 | 4051 | 221 | **94.5%** |
| 23:36:49 | 1897 | 0 | **100.0%** |
| 23:37:04 | 1356 | 68 | **95.0%** |
| 23:37:19 | 107 | 107 | 0.0% |

Waiting の tick の **95〜100% はメニュー／ポップアップ／フォトモード中**。
そして `Modules/core.lua` の該当分岐が：

```lua
if self.event_obj:IsInVehicle() and not self.event_obj:IsInMenuOrPopupOrPhoto() then
    self.av_obj:Operate(actions)
elseif self.event_obj:IsWaiting() then          -- ← menu ガード無し
    self.av_obj:Operate({{Def.ActionList.Idle, 1}})
end
```

**`Engine:Update` はメニュー中なら即 return する**（`Modules/engine.lua`）。
つまりこの分岐で計算した制御ターゲットは**物理層に一切届かない**。
純粋に死んだ仕事だった：

```
Waiting/GetActions              4050 回 / 15s  = 270/s
Waiting/CalculateAddVelocity    4050
Waiting/CalculateIdleMode       4050
Waiting/GetGroundPosition       4050  ← SyncRaycastByQueryFilter 270 本/秒
```

### fix (21)：メニューガードを分岐共通の早期 return に引き上げる

```lua
function Core:OperateAerialVehicle(actions)
    if self.is_locked_operation then return end
    if self.event_obj:IsInMenuOrPopupOrPhoto() then return end   -- ← 追加
    if self.event_obj:IsInVehicle() then
        self.av_obj:Operate(actions)
    elseif self.event_obj:IsWaiting() then
        self.av_obj:Operate({{Def.ActionList.Idle, 1}})
    end
end
```

InVehicle 側の挙動は従来と完全に同一。Waiting 中、メニューを開いている間は
**Lua 遷移 0 回**になる（テストで実測：old 400 → new 0 / 100 calls）。

リスクは低い：`Engine:Update` が止まっているので計算結果の行き先が無く、
メニューを閉じれば通常どおり再開する。

## 10. 副次：ループ効率がフレームレート依存

`Cron.Every(0.01)` は「`delta >= timeout` なら毎フレーム発火」なので、
実効レートが **18Hz（運転中）〜270Hz（待機中）** に振れている。
設計は 100Hz で、上振れも下振れも無制御。

- 上振れ：待機中に設計の 2.7 倍の仕事をする
- 下振れ：運転中に 18Hz しか制御が回っていない（これはこれで別問題）

→ 実時間基準＋キャッチアップ上限での額面 100Hz 固定は**未実施**。
挙動に直結するため、フレームレート依存の回帰テストを先に用意したい。

## 11. fix (22)：`ToggleOriginalMPHDisplay` の retry ストーム

ログに `mph_text widget not resolvable yet, will retry` が
**搭乗ごとに約 1.5 秒で 13 回**。ダッシュボードの widget ツリーが入れ替わる
間は解決に失敗し続けるが、この関数は `CheckHUD` からループレートで呼ばれるため、
1 秒で約 40 回の失敗ルックアップ＋13 回の Warning（＝ログ書き込み自体が C# 呼び出し）。

対策（`Modules/hud.lua`）：

| 項目 | 変更 |
|---|---|
| 解決失敗中の再試行 | `mph_retry_interval = 0.1` で間引き（100Hz → 10Hz） |
| ログ | エピソード最初の 1 回だけ Warning、以降は Debug（既定でフィルタ） |
| 新しい要求 | `mph_requested_on` が変わったらバックオフを解除して即時試行 |
| 解決済みハンドル | キャッシュされているなら throttle しない（元々ただなので） |
| HUD 再マウント | `OnInitialize` / `OnMountingEvent` で全状態をリセット |

効果（テスト実測）：1 秒間 100Hz で unresolved →
**試行 100 回 → 10 回、Warning 13 本 → 1 本**。

## 12. 一過ヒッチ（未修正）

`Waiting/CheckLanded` **1 回 9.00 ms**（23:36:07、Landing→Waiting 遷移時）。
中身は `StopGameSound` / `PlayGameSound` / `ChangeSoundResource` の
音声リソース切替。迁移時のみ発生する可視ヒッチだが、音声設計に手を入れる
必要があり優先度低として見送った。

## 13. 第2部の検証

`tests/situation_cost_test.lua` に 2 セクション追加（**54 passed, 0 failed**）：

- **section 10**（fix 21）
  - Waiting / 非メニュー → 制御は走る
  - Waiting / メニュー中 → 制御は走らない、**遷移 0 回**
  - InVehicle / 非メニュー・メニュー中 → 従来どおり
  - Normal → 一切 operate しない（従来どおり）
- **section 11**（fix 22）
  - 1 秒 unresolved で試行 10 回（毎 tick ではない）
  - Warning は 1 本だけ、以降は Debug
  - 新しい要求はバックオフに縛られず即時
  - 同一要求の繰り返しは間引かれる
  - 解決できたら状態がラッチされ、以後仕事はゼロ

### 第2部で変更したファイル

| ファイル | 変更 |
|---|---|
| `Modules/core.lua` | `OperateAerialVehicle` にメニューガード（fix 21） |
| `Modules/hud.lua` | `ToggleOriginalMPHDisplay` の retry ペーシング＋ログ抑制（fix 22） |
| `tests/situation_cost_test.lua` | section 10 / 11 追加（38 → 54 assertions） |
