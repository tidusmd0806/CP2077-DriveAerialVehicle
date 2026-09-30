# 性能解析：`CheckAllEvents` の上位 3 項目（同期レイキャスト／メーター書き込み／FPP ロック）

対象: DriveAerialVehicle v3.3.1
解析: 静的解析（遷移モデル）→ 実装 → `tests/meter_cadence_test.lua` で挙動検証
関連: `PERFORMANCE_FIX_PLAN.md`、`PERF_ANALYSIS_situations.md`、`PERF_ANALYSIS_enter_exit.md`
本ドキュメントの修正は通し番号で **fix (28)〜(30)**

---

## 0. 前提：1 tick のコストは何で決まるか

CET の Lua から REDscript を呼ぶ**言語境界の跨ぎ回数**が支配コスト。
跨ぎ 1 回では中身によって桁が違う。

| 記号 | 内容 | 概算 |
|---|---|---|
| `T` | 素の getter / setter（userdata ラッパ返却込み） | 0.5〜2 µs + 50〜150 B |
| `V` | `Vector4.new` 等の managed ctor | 1T + alloc |
| `R` | `SyncRaycastByQueryFilter`（**同期**物理クエリ） | 10〜80 µs ≒ **getter 20〜80 本分** |
| `W` | ink widget 書き込み（`SetText` / `EvaluateRPMMeterWidget`） | 2〜10 µs ＋ **再レンダリング無効化** |
| `A` | Lua アロケーション（クロージャ／テーブル／文字列連結） | 48〜100 B |

`Cron.Every(0.01)` は 1 フレーム 1 回しか発火しないので、実効レートは
`min(fps, 100)`。メニュー中で fps が跳ね上がればそのまま上振れする。

---

## 1. 修正前の 1 tick あたり（理論値）

### Waiting（搭乗エリア内にプレイヤー）

| チェック | 内訳 | コスト |
|---|---|---|
| `CheckDespawn` | `GetEntity`（frame cache 済み） | 1T |
| `CheckInEntryArea` | 位置・姿勢・プレイヤー位置 等 | 5T + 9A |
| `CheckInAV` | `IsPlayerMounted` | 1T |
| `CheckDestroyed` | `IsDestroyed` | 1T |
| `CheckDistance` | 0.5 s にスロットル済み | 0.2T |
| `CheckHeight` | 位置 + `Vector4.new`×2 + **同期レイキャスト** | **4T + 1R + 2V** |
| `CheckDoor` | `GetVehiclePS` + `GetDoorState` | 2T |
| | **合計** | **≈14T + 1R + 11A** |

### InVehicle（手動飛行）

| チェック | 内訳 | コスト |
|---|---|---|
| `CheckHUD` 消費アイテム枠 | pcall + `GetRootCompoundWidget` + `.visible` | 2T + 1A |
| `CheckHUD` HP | pcall + `SetText`（**無傷でも毎 tick**） | 1T + 1W + 2A |
| `CheckHUD` 速度取得 | `GetVelocity`+`GetAngularVelocity`+`Vector3To4`+`Length` | 4T |
| `CheckHUD` 速度計 | pcall + `GameSettings.Get` + `SetText` | 2T + 1W + 1A |
| `CheckHUD` 回転計 | pcall + `EvaluateRPMMeterWidget` | 1T + 1W + 1A |
| `CheckEngine` | `IsEngineTurnedOn` | 1T |
| `CheckDestroyed` | | 1T |
| `CheckCombat` | `GetPlayer` + `PSIsInDriverCombat` | 2T |
| `CheckHeight` | 同上 | 4T + 1R + 2V |
| `CheckPerspective` | **トグルバグ（下記 ③）** | 1.5T + 0.5A |
| | **合計** | **≈18T + 3W + 1R + 7A** |

上位 3 項目がこのうち **`R` の 100%、`W` の 3 本中 3 本、そして
InVehicle では 単独で ~5T** を占めていた。

---

## 2. fix (28)：`CheckHeight` の同期レイキャストに周期を与える

### 問題

`Navigation:GetHeight()` は `AV:GetGroundPosition()` →
`SyncRaycastByQueryFilter` に落ちる。**同期物理クエリ 1 本は getter 数十本分。**
これが Waiting / Landing / InVehicle / TalkingOff の**全状況で毎 tick** 走っていた。
地上に駐機している機体は高さが動かないのに、である。

探知結果が供給先としているのは 2 つだけ：

- 着地警告 VFX（閾値 `projection_max_height_offset + minimum_distance_to_ground` ≒ 5 m のブール）
- その VFX スロットの Z オフセット

どちらも 100 Hz を必要としない。

### 実装（`Modules/event.lua`）

**前回の測定値から次回を予測**する。高さは 1 間隔で大きく動けないので、
前回見た値が「次に取りこぼし得る範囲」を規定する。

| 条件 | 周期 | 根拠 |
|---|---|---|
| プレイヤーが 60 m 以上離れている | **0.5 s** | 投影そもそも誰にも見えない |
| 縦速度 \|vz\| ≤ 0.5 m/s | **0.25 s** | 高さは動かない |
| 高度 > 20 m | **0.1 s** | 閾値まで十分遠く、降下速度が速くても 7 間隔分の余裕 |
| それ以外（低所＋移動中） | **毎 tick** | 従来どおり |

```lua
function Event:CheckHeight()
    local now = os.clock()
    if now < self.next_height_check_time then
        return
    end
    self.next_height_check_time = now + self:PickHeightInterval()
    local height = self.av_obj.navigation_obj:GetHeight()
    self.last_height = height
    ...
end
```

`PickHeightInterval()` のコストは**探知 1 回につき 1 回**だけ。
探知と探知の間、`CheckHeight` は `os.clock()` と 1 回の比較で return する。

付随して `Event:GetPlayerDistanceToAV()` を新設し、`CheckDistance` と
**距離を共有キャッシュ**（0.5 s）にした。両者別々に 4 遷移していた分が 1 本で済む。
`Game.GetPlayer()` が nil のときは**「不明」であって「遠く」ではない**ので、
その場合は周期を伸ばさない（B7 テストで固定）。

`Engine:GetVelocity()`（`Modules/engine.lua`）を追加。
`GetDirectionAndAngularVelocity()` は角速度まで一緒に解決して 2 遷移かかるが、
この用途で必要なのは線形速度だけ。

### 期待効果

| 状態 | 修正前 | 修正後 |
|---|---|---|
| 駐機中（縦速度 0） | 100 本/s | **4 本/s** |
| 巡航（高度 20 m 超） | 100 本/s | **10 本/s** |
| 低空飛行 | 100 本/s | 100 本/s（変更なし） |
| プレイヤーから 60 m 以上離間 | 100 本/s | **2 本/s** |

---

## 3. fix (29)：メーターを表示値でエッジトリガー

### 問題

`SetSpeedMeterValue` / `SetRPMMeterValue` / `SetHPDisplay` は
**表示される数字が変わらなくても毎 tick 書き込んでいた**。
書き込みは C# 呼び出しであるだけでなく **ink widget を dirty にして再レンダリングを
誘発する**方が高い。無傷の機体を駐機しているだけで、

- 速度計：同じ数字を 100 回/s
- 回転計：同じ数字を 100 回/s
- HP：同じ文字列を 100 回/s（＋パディング用の文字列生成）

計 **~300 回/s の widget 無効化**を発生させていた。

### 実装（`Modules/hud.lua`）

各 setter に「最後に書き込んだ表示値」のラッチを持たせ、**同じなら書かない**。

```lua
local display_value = math.floor(speed_value * self:GetSpeedUnitFactor())
if display_value == self.last_speed_display_value then
    return
end
local success, error_msg = pcall(writeSpeedText, self, display_value)
if success then
    self.last_speed_display_value = display_value
end
```

ラッチは**書き込みが成功したときだけ**確定する。widget ハンドルが死んでいる間は
ラッチされない自己回復型（C10 テスト）。

ラッチを落としてはいけないエッジを 2 箇所塞いだ：

| エッジ | 対処 |
|---|---|
| `EnableManualMeter(false, ...)` → 手動返上 | そのメーターのラッチを破棄。ゲームが値を書き換えるので、再手動時に最初の 1 回を飛ばすと誤表示のまま |
| HUD 再マウント（`OnInitialize` / `OnMountingEvent`） | `ResetMeterCaches()` を呼ぶ |

あわせて 2 点：

- **`GameSettings.Get("/interface/SpeedometerUnits")` を 1 s 周期でキャッシュ**。
  表示値を計算するのに単位が必要なので、毎 tick 呼ぶと「何も書かない」ときも
  1 遷移残る。1 s リフレッシュで単位変更は拾える。
- **`pcall(function() ... end)` を `pcall(fn, hud, value)` に変更**。
  クロージャ形式は `self` と値を捕捉して書き込みごとにゴミテーブルを 1 個生成する。
  明示形式はアロケーションゼロ。`writeSpeedText` / `writeRpmMeter` / `writeHpText`
  をモジュールスコープに置いた。
- `Event:CheckHUD()` が `SetHPDisplay()` を丸ごと `pcall` で包んでいたのを削除。
  例外の起き得るのは内部の `SetText` だけで、そこはもう守られている。
  毎 tick クロージャ 1 個の削減。

### 期待効果

| 状態 | 修正前 | 修正後 |
|---|---|---|
| 定速巡航 | 速度 100 + 回転 100 書き込み/s | 桁が変わる **数回〜20 回/s** |
| 駐機（無傷） | 300 書き込み/s | **0** |
| 単位ルックアップ | 100 回/s | **1 回/s** |
| pcall クロージャ | ~5 個/tick | 書き込み時にのみ、かつ 0 アロケーション |

---

## 4. fix (30)：`CheckPerspective` のトグルバグ

### 問題

これは最適化ではなく**ロジックの欠陥**。

```lua
if self:IsFPP() and not self.is_locked_showing_meter then
    self.hud_obj:ForceShowMeter()
    self.is_locked_showing_meter = true
else
    self.is_locked_showing_meter = false   -- ← FPP でも else に落ちる
end
```

FPP で `locked == true` の間も条件が偽になって **`else` に落ち、ラッチが解かれる**。
結果として FPP を維持している間もラッチが **tick ごとに true / false を交互**に
切り替わり、`ForceShowMeter()`（`ShowRequest()` + `OnCameraModeChanged(true)`
＝ 2 遷移 + クロージャ 1 個）が **ループレートの半分、約 50 回/s** 発火していた。
**すでに force 済みのメーターを、毎 2 tick 目に force し直していた。**

意図は「FPP のあいだ一度だけ force し、FPP を抜けたら解く」。

### 実装

```lua
function Event:CheckPerspective()
    if self:IsFPP() then
        if not self.is_locked_showing_meter then
            self.hud_obj:ForceShowMeter()
            self.is_locked_showing_meter = true
        end
    else
        self.is_locked_showing_meter = false
    end
end
```

### 期待効果

| | 修正前 | 修正後 |
|---|---|---|
| FPP 維持 64 tick での `ForceShowMeter` | 32 回 | **1 回** |
| 搭乗 1 回あたり | ~50 回/s | **1 回** |

テスト節 A に**修正前のコードを書写した sanity check** を入れてあり、
「本当に元コードがスラッシュしていた」ことを同時に検証している。

---

## 5. 検証

`python tests/run_meter_cadence_test.py` — **42 passed, 0 failed**

| 節 | 検証内容 |
|---|---|
| **A** | FPP 維持 64 tick で `ForceShowMeter` は 1 回／ラッチは保持／FPP 離脱で解除／再進入で再度 1 回／**修正前コードを書写して実際にスラッシュしていたことの確認** |
| **B** | 離間 100 m → 約 2 探知/s／駐機 → 約 4/s／高度 50 m 降下 → 約 10/s／**低所＋移動中は毎 tick（変更なし）**／Init 直後の初回探知は遅延しない／閾値Crossing で警告は確実に ON/OFF／**プレイヤー不明は「遠い」扱いしない**／駐機中は VFX オフセット書き込み ≤1 回 |
| **C** | 同一表示値 100 回で書き込み 1 回／単位ルックアップ 1 回／実変化は通る／単位変更は 1 s 後に反映／手動↔ゲームの切替でラッチ再武装／RPM も同様／HP のパディング（100 / " 87" / "  9"）維持／`ResetMeterCaches` で全メーター再書き込み／手動無効時は書き込みゼロ／**widget 欠損時はラッチせず、現れたら自己回復** |

既存テストへの非回帰（すべて従来どおり pass）:

```
situation_cost_test    54 passed
enter_exit_cost_test   52 passed
onaction_cost_test     40 passed
entity_cache_test      31 passed
axis_proxy_cost_test   31 passed
tools/check_lua_syntax.py  47 files, 0 problems
```

### `situation_cost_test` の状況別合計が動いた

同一ハーネスで、fix (27) まで（`git stash`）と fix (30) 後を比較:

| situation | fix ≤27 | fix 28〜30 | 削減 |
|---|---:|---:|---:|
| Normal（未召喚） | 1.0 | 1.0 | 0% |
| Landing | 5.0 | 3.2 | **−36.4%** |
| Waiting（搭乗エリア内） | 19.5 | 17.6 | **−9.7%** |
| Waiting（プレイヤー離脱） | 19.1 | 17.1 | **−10.5%** |
| TalkingOff（leaving） | 4.1 | 2.2 | **−46.3%** |
| InVehicle（手動飛行） | 22.0 | 18.1 | **−17.7%** |

> **この数字は削減を過小評価している。** 当該ハーネスは
> `SyncRaycastByQueryFilter` を素の getter と同じ「1 遷移」として数えるため、
> fix (28) の本命である `R` の削減（1 本 ≒ getter 数十本分）が
> 1 遷移分としてしか反映されない。実機のフレーム時間に効くのは
> 遷移カウントではなく `R` と `W` の方。

---

## 6. 変更ファイル

| ファイル | 変更 |
|---|---|
| `Modules/event.lua` | `height_check_interval_*` / `height_slow_threshold` / `height_still_speed` / `height_skip_distance` 追加／`PickHeightInterval()` 新設／`CheckHeight` を周期制に／`GetPlayerDistanceToAV()` 新設（`CheckDistance` と共有）／`CheckPerspective` のラッチ修正／`CheckHUD` の `pcall` 包み除去／`Init` で新状態をリセット |
| `Modules/hud.lua` | 表示値ラッチ 3 種＋単位キャッシュ追加／`ResetMeterCaches()` / `GetSpeedUnitFactor()` 新設／`SetSpeedMeterValue` / `SetRPMMeterValue` / `SetHPDisplay` をエッジトリガー化／書き込み関数をモジュールスコープに移して `pcall(fn, a, b)` 化／HUD 再マウント時 `ResetMeterCaches()` |
| `Modules/engine.lua` | `GetVelocity()` 追加（角速度を解決しない線形速度のみ） |
| `tests/meter_cadence_test.lua` | 新規（42 assertions） |
| `tests/run_meter_cadence_test.py` | 新規ランナー |

---

## 7. 残っているもの（今回見送った）

理論値で次点の項目。優先度順:

| # | 項目 | 現状 | 理論削減 |
|---|---|---|---|
| ④ | `AV:GetDoorState` が毎回 `entity:GetVehiclePS()` | 1T/tick（Waiting） | VehiclePS を frame cache |
| ⑤ | `AV:GetCurrentSpeed()` が 4 遷移 | 4T/tick（InVehicle） | `GetVelocity()` 1 本 + Lua `sqrt` で **1T** |
| ④ | `CheckCombat` が毎回 `Game.GetPlayer()` | 1T/tick | `GetPlayer` の frame cache |
| ⑦ | `CheckDespawn` と `CheckDestroyed` の 90% 重複 | 2T/tick | 単一の entity liveness 判定で **1T** |
| ⑧ | `CheckDoor` / `CheckEngine` / `IsVisibleConsumeItemSlot` の 100 Hz ポーリング | 5T/tick | 5〜10 Hz で **−4.5T/tick** |
| ⑨ | `Utils:RotateVectorByQuaternion` が 1 点のために 9 テーブル | 9A/frame | スカラー演算にインライン化で **0A** |
| ⑩ | 状況変化 tick の後続チェック | 遷移時のみ 6 チェック | `if self:CheckDespawn() then return end` |
| ⑪ | `os.clock()` の多重呼び出し | 3〜5 回/tick | tick 先頭で 1 回取り回し |
| ⑫ | ループレート自体が fps 依存（メニュー中で 270 Hz 級） | — | 実時間アキュムレータ＋キャッチアップ上限 |

`CheckAllEvents` の 1 tick は ④〜⑧ まで手を付けると
InVehicle で **≈18T → ≈6T** まで理論上下がる。
