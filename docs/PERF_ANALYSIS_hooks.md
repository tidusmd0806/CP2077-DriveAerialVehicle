# 性能解析：onUpdate の外側 — 常時発火するグローバルフック

対象: DriveAerialVehicle v3.3.0
計測: `docs/cet_functions.csv`（CET フックレベルプロファイル, 4322 フレーム実測）
解析ツール: `tools/analyze_cet_csv.py` / `tools/map_profile_to_source.py` /
`tools/classify_hooks.py` / `tools/frame_budget.py`
関連: `docs/PERF_ANALYSIS_init441.md`（fix (1)〜(2) の履歴）

---

## 0. 結論

**前回の解析は `init.lua:441/448` の漏斗の中だけを見ていた。
DAV の Lua コストの 24.2% は漏斗の外にある。**

| | ms | µs/frame | DAV 比 |
|---|---|---|---|
| 全 Mod 合計 | 3200.0 | 740.4 | — |
| **DAV 合計** | **1445.1** | **334.4** | 100%（全 CET Lua の **45.2%**） |
| onUpdate 漏斗（Cron + Engine） | 1096.0 | 253.6 | 75.8% |
| **onUpdate 以外** | **349.1** | **80.8** | **24.2%** |

60fps のフレーム予算（16,667µs）に対する DAV の占有率は 2.01%。
漏斗の外だけを削っても **約 55µs/frame** が浮く。

漏斗の内側（fix (3)〜(6)）と**直交**している。前回効かなかった分は別軸で削れる。

---

## 1. ⚠️ この CSV の読み方（前回の解析とズレる理由）

`cet_functions.csv` が計測しているのは **CET フックの入口だけ**。

- DAV の行は 32 本。全て `registerForEvent` / `Observe` / `ObserveAfter` /
  `Override` / proxy `callback` の**定義行**。
- `Cron.lua` / `av.lua` / `engine.lua` / `navigation.lua` は **1 行も存在しない**。

```
$ grep -c "navigation.lua\|av.lua\|engine.lua\|Cron.lua" docs/cet_functions.csv
0
```

→ フック内部の素の Lua 関数は個別に計測されず、**呼び出し元フックの
`exclusive_ms` に全部まとまる**。

帰結：

| | この CSV で言えるか |
|---|---|
| `init.lua:448` が漏斗である | ✅ 言える（前回と一致） |
| 漏斗内部の内訳（Cron vs Engine vs AV） | ❌ **確定できない** |
| 漏斗の外のフックの総コスト | ✅ **これが本命** |

`tools/map_profile_to_source.py` が最も情報量が多い。

```
excl_ms    calls  avg_us   max_ms   gc_ms  main_ms   wkr_ms  ofDAV  location
1096.04     4322   253.6    12.01   12.83  1096.04     0.00  75.8%  init.lua:448
 208.70    14106    14.8     0.22    0.64    26.83   181.87  14.4%  Modules/core.lua:404
  55.95    17448     3.2     0.12    0.66    55.95     0.00   3.9%  init.lua:395
  28.71     2744    10.5     0.07    0.00     1.78    26.93   2.0%  Modules/event.lua:188
  22.47     1597    14.1     0.31    0.03     0.93    21.54   1.6%  Modules/core.lua:1239
  17.03     2482     6.9     0.40    0.01     0.37    16.66   1.2%  Modules/core.lua:1234
  ...
```

---

## 2. 常時発火グローバルフック（AV の有無と無関係に発火）

`tools/classify_hooks.py` の出力：

```
  Modules/core.lua:404    208.70 ms   14106 calls   14.8 us/call   worker= 181.9 ms
  init.lua:395             55.95 ms   17448 calls    3.2 us/call   worker=   0.0 ms
  Modules/event.lua:188    28.71 ms    2744 calls   10.5 us/call   worker=  26.9 ms
  Modules/core.lua:1239    22.47 ms    1597 calls   14.1 us/call   worker=  21.5 ms
  Modules/core.lua:1234    17.03 ms    2482 calls    6.9 us/call   worker=  16.7 ms
  ...
  TOTAL 341.6 ms = 23.6% of DAV, 43270 calls
```

**漏斗の外の 97.8% が、AV が存在しなくても発火するフック。**
＝ Mod を何も使っていないときにも払い続けている固定費。

---

## 3. 各項目の詳細

### ① `Observe("PlayerPuppet", "OnAction")` — core.lua:404
**208.70ms / 14.4% / 14,106 call / 14.8µs avg / 87% が worker thread**

Mod 全体で **第 2 位**なのに前回解析に一切登場しない。
ゲーム中の**全プレイヤー入力アクション**に発火する。

| # | 無駄 | 箇所 |
|---|---|---|
| 1a | **Discard 確定の Debug 文字列連結を毎回実行**。`MasterLogLevel = Info` なので `Record(LogLevel.Debug, ...)` は即 return するが、**連結は呼び出し前に済んでいる**。約 5.6 万個の死んだ文字列 | core.lua:457 |
| 1b | フィルタ前に `GetName`/`GetType`/`GetValue` で 3 回 interop | core.lua:410-412 |
| 1c | `exception_in_veh_list`(17) 等を `pairs()` で**線形スキャン**。4 箇所 | core.lua:415,430,441,449 |
| 1d | `Game.GetPlayer()` + `PSIsInDriverCombat()` で追加 2 interop | core.lua:421-422 |
| 1e | 406 行で `current_situation` を**既に読んでいる**のに、414 行で `IsInVehicle()` により situation を再読 + C# 往復。既存の `IsInAVSituation()`（純 Lua）が未使用 | core.lua:406/414 |
| 1f | `IsMountedCombatSeat()`（C# 往復）を、**popup 例外リストに該当しないアクションに対しても**呼ぶ | core.lua:428 |
| 1g | `StorePlayerAction` で `local cmd_list = {}` 確保→即上書き。**毎回無駄なテーブル** | core.lua:624 |

**worker thread 181.9ms の意味**：CET の Lua VM は単一ロック。
worker 発火は「空き時間で並列」ではなく**メインスレッドの onUpdate と直列化して競合**する。
`init.lua:448` の `max_ms = 12.01`（avg の 47 倍）はこれと整合する。

### ② `Input/Axis` proxy — init.lua:395
**55.95ms / 3.9% / 17,448 call（4.04 回/frame）**

- `GetKey().value` + `GetValue()` を**フィルタ前**に実行
- `key:find("IK_Pad")` は Lua パターンマッチ（`sub` 比較で置き換え可）
- situation チェックが**高コスト処理の後**
- `ConvertAxisAction`（core.lua:1028）が**呼び出し毎に `axis_key_list` テーブルを新規確保**
- init.lua:407-408 は空の `else end`（死コード）
- AV が存在しなくても発火し続ける

### ③ Mappin observers — core.lua:1234 + 1239
**39.50ms / 2.7% / 4,079 call**

`BaseMappinBaseController` の `IsTracked` / `UpdateRootState` は
**ゲーム中の全 mappin（数百個）で発火**。1 個探すのに毎回
`GetMappin` → `GetVariant`（+条件により `IsPlayerTracked` / `GetWorldPosition`）。

さらに `SetCustomMappin` → `SetDestinationMappin` → `FindNearestFastTravelPosition`
（core.lua:1428）は **`fast_travel_position_list` への O(N) ループ + 毎要素
`Vector4.Distance`** がホット経路にぶら下がっている。

→ DAV は自分の mappin を**自分で作っている**ので、有効時のみフックする／ID を先に
比較するだけでほぼ消える。

### ④ `Override("VehicleComponentPS", "GetHasAnyDoorOpen")` — event.lua:188
**28.71ms / 2.0% / 2,744 call @ 10.5µs**

**AV だけでなく世界中の全車両のドア判定**を横取り。
毎回 `IsInVehicle()` → `IsPlayerIn()` → `GetEntity()` + `IsPlayerMounted()`。

→ 入口で `current_situation ~= InVehicle`（純 Lua）を見て即 `wrapped_method()`。

### ⑤ `AV:IsPlayerInEntryArea()` — av.lua:1197（共有プリミティブ）
10 箇所から呼ばれる。`hud.lua:92` で **32.4µs/call**。内訳：

- interop 約 5 回（`GetPosition` / `IsZero` / `GetQuaternion` / `GetPlayer` / `GetWorldPosition`）
- **テーブル約 9 個**。`Utils:RotateVectorByQuaternion` だけで 5 個
  （共役・`{r=0,...}` リテラル・`QuaternionMultiply`×2・戻り値）

`GetHeight` と同じ**フレーム単位キャッシュ**が未適用。

### ⑥ `UISystem.QueueEvent` を二重観測 — hud.lua:154 + 193
ゲームで最も熱い UI メソッドの一つに別々に入っている。
`StringToName("gameuiUpdateInputHintEvent")` を**イベント毎に生成**、
`CName.new(hint)` を**ループ内で生成**。定数化対象。

---

## 4. 優先度（漏斗の外のみ）

| 優先 | fix# | 対策 | 現在 | 目標 | 状態 |
|---|---|---|---|---|---|
| 1 | **(3)** | OnAction: Debug 連結のガード／例外リストの集合化／situation 使い回し／`IsMountedCombatSeat` の後置ガード／`cmd_list={}` 削除 | 208.7ms | 60〜90ms | **完了（§5）** |
| 2 | — | Mappin observer を有効時のみ／ID 先比較／`FindNearestFastTravelPosition` を目的地変更時のみ | 39.5ms | <5ms | 未着手 |
| 3 | **(4)** | Axis proxy: situation 先頭化／dead zone 先判定／`Def.AxisKeySet` でキー先絞り込み／`axis_key_list` の毎回確保を除去 | 56.0ms | 20〜30ms | **完了（§6）** |
| 4 | — | `GetHasAnyDoorOpen`: situation ガード | 28.7ms | 8〜12ms | 未着手 |
| 5 | — | `IsPlayerInEntryArea` のフレームキャッシュ＋回転演算のテーブル除去 | ⑤全体 | 1/5 | 未着手 |
| 6 | — | QueueEvent 二重観測の統合・名前定数化 | 2.6ms | <1ms | 未着手 |

> 優先度は推定効果順。`fix#` は `PERF_ANALYSIS_init441.md` の (1)(2) からの
> 通し番号で、**実装順**に振っている（なので 2 番目が飛んでいる）。

---

## 5. fix (3)：`PlayerPuppet.OnAction` の削減

`docs/PERF_ANALYSIS_init441.md` の fix (1)(2) に続く通し番号として **(3)** とする。

### 5.1 追加した基盤：`Log:IsEnabled(level)`

`Etc/log.lua` にレベル判定の公開メソッドを追加。

```lua
--- Whether a record at `level` would actually be emitted.
--- Record() decides *after* the caller has already built the message string.
--- On a hot path that means paying for concatenation that is then thrown away.
--- Callers that build their message from concatenation must gate on this first.
function Log:IsEnabled(level)
    local setting_level = self.setting_level
    if MasterLogLevel > setting_level then
        setting_level = MasterLogLevel
    end
    return level <= setting_level
end
```

**判定ロジックは `Record()` と同一**にして、ゲートを通したときだけ
`Record` が実際に出力する＝出力内容は無変更。

### 5.2 例外リストを集合化

`Utils:ReadJson` が返す**配列**を、ロード時に**ハッシュ集合**へ。
`pairs()` 線形スキャン（最大 17 比較）が O(1) 参照になる。

```lua
local function to_exception_set(list)
    local set = {}
    if list then
        for _, name in ipairs(list) do
            set[name] = true
        end
    end
    return set
end
```

JSON ファイルは**変更しない**（ユーザーが編集できる設定のまま）。
集合化は Lua 側のみ。

### 5.3 situation の使い回し

406 行で読んだ `current_situation` をローカルに保持し、
`IsInVehicle()` による再読 + C# 往復を避ける。

```lua
local situation = self.event_obj.current_situation
if situation ~= Def.Situation.Waiting and situation ~= Def.Situation.InVehicle then
    return
end
...
if situation == Def.Situation.InVehicle and self.av_obj:IsPlayerIn() then
```

`Event:IsInVehicle()` の定義
（`current_situation == InVehicle and av_obj:IsPlayerIn()`）と**等価**。

### 5.4 `IsMountedCombatSeat()` を後置ガードに

修正前は「コンバットシートでないなら popup 例外を全部舐める」。
→ **「popup 例外に該当する時だけコンバットシートを確認する」** に反転。
該当しないアクション（大多数）では C# 往復がまるごと消える。

```lua
-- 修正前
if not self.av_obj:IsMountedCombatSeat() then
    for _, exception in pairs(exception_in_popup_list) do
        if action_name == exception then consumer:Consume() break end
    end
end
-- 修正後
if exception_in_popup_set[action_name] and not self.av_obj:IsMountedCombatSeat() then
    consumer:Consume()
end
```

論理値は同一（`¬mounted ∧ (∃ exception)` ≡ `(∃ exception) ∧ ¬mounted`）。

### 5.5 死んだ Debug 連結をガード

```lua
-- 修正前：MasterLogLevel=Info のとき連結だけ無駄に発生
self.log_obj:Record(LogLevel.Debug, "Action Name: " .. action_name .. ...)

-- 修正後
if self.log_obj:IsEnabled(LogLevel.Debug) then
    self.log_obj:Record(LogLevel.Debug, "Action Name: " .. action_name .. ...)
end
```

**デバッグログを有効にした時の出力内容は従来と同一**。

### 5.6 `StorePlayerAction` の無駄テーブル除去

```lua
-- 修正前：確保した瞬間に上書き
local cmd_list = {}
cmd_list = self:ConvertActionList(action_name, action_type, action_value)
-- 修正後
local cmd_list = self:ConvertActionList(action_name, action_type, action_value)
```

### 5.7 不変条件

| 項目 | 保証 |
|---|---|
| `consumer:Consume()` が呼ばれる条件 | 全分岐で論理同値（集合化・順序反転は論理演算の交換） |
| デバッグログ有効時の出力 | 従来と同一 |
| `StorePlayerAction` の引数 | 同一 |
| 例外リストの JSON 形式 | 無変更（ユーザー編集可能のまま） |
| 早期 return の条件 | 同一 |

### 5.8 検証

**`tests/onaction_cost_test.lua`（`python tests/run_onaction_cost_test.py`）**

実 `Modules/core.lua` をロードし `Observe` を捕捉してコールバックを直接駆動。
**40 passed, 0 failed**

| 節 | 検証内容 |
|---|---|
| 1 | 例外集合が出荷 JSON と同じ成员数（17 / 4 / 1） |
| 2 | `Normal` 状況では interop ゼロで return |
| 3 | InVehicle +  veh 例外 → `Consume()` される／非例外はされない |
| 4 | popup 非該当アクションでは `IsMountedCombatSeat()` を**呼ばない** |
| 5 | メニュー/popup/フォト/オート + popup 例外 → `Consume()` |
| 6 | Waiting + エリア内／エリア外 の挙動 |
| 7 | Debug 無効時、ログ行が 1 行も出ない（＝連結していない） |
| 8 | Debug 有効時、出力文言が**修正前とバイト単位で同一** |
| 9 | `IsEnabled` が全レベル組合せで `Record` の実出力と一致 |
| 10 | `current_situation` の読み出しが**正確に 1 回** |
| 11 | `StorePlayerAction` が受け取る引数が従来と同一 |
| **12** | **差分同値：5376 通りの (状況 × アクション × 状態) 全組合せで `Consume()` 判定が修正前と一致** |
| **13** | **コスト台帳：各ケースで新パスが旧パスより高くつかないこと** |

#### セクション 12 の設計

修正前のコールバックをテスト内に**そのまま書き写し**、同じ入力行列を
新旧両方に流して結果を突き合わせる。差分があればテストが落ちる構成なので、
「レビューで読んだ限り等価」ではなく**網羅的に等価**であることを保証する。

#### セクション 13：コスト台帳（実測）

```
  case                                 C# round trips dead strings  saved
                                          old    new    old    new
  ------------------------------------------------------------------------------
  Normal (no AV)                            0      0      0      0   -0
  InVehicle, plain action                   3      3      1      0   -1
  InVehicle, veh exception                  3      3      1      0   -1
  InVehicle, combat, non-popup              4      3      1      0   -2
  InVehicle, combat, popup exception        4      4      1      0   -1
  InVehicle, auto mode, non-popup           3      3      1      0   -1
  Waiting, in entry area                    1      1      1      0   -1
  ------------------------------------------------------------------------------
  TOTAL across cases                       18     17      6      0   -7 (29%)
```

**`dead strings` 列が本修正の主戦果**。`Record` に渡す前に連結が消えたので、
Info レベルでは**アクション毎の死んだ文字列アロケーションが 1 → 0**。
14,106 call × 4 連結 ≒ **5.6 万個のアロケーションが消えた**ことになる。

C# 往復は `IsMountedCombatSeat()` の 1 回分（combat 中かつ非 popup アクション）
だけが減った。残る 3 回（`IsPlayerIn` / `GetPlayer` / `PSIsInDriverCombat`）は
判定に必要なのでそのまま。

### 5.9 実測できなかったもの

`exclusive_ms` はフック入口にまとまるため、**この修正が 208.7ms をいくら減らしたか
の実測値は次回のプロファイルまで出せない**。台帳は「呼び出し回数」の削減であり、
実時間の削減はアロケーション除去の分だけ GC 側に効く（`gc_ms` で確認）。

再プロファイル時に確認すべき列：

| 列 | 期待 |
|---|---|
| `core.lua:404` の `exclusive_ms` | 208.7 → 60〜90ms |
| 全体の `gc_ms` | 14.28ms から減少 |
| `init.lua:448` の `max_ms` | 12.01ms のスパイクが低下（worker 競合の軽減） |

### 5.10 変更ファイル

| ファイル | 変更 |
|---|---|
| `Etc/log.lua` | `Log:IsEnabled(level)` 追加。`Record` はそれを呼ぶように変更（挙動同一） |
| `Modules/core.lua` | `to_exception_set` 追加／`SetInputListener` 書き換え／`StorePlayerAction` の無駄テーブル除去 |
| `tests/onaction_cost_test.lua` | 新規（40 assertions） |
| `tests/run_onaction_cost_test.py` | 新規ランナー |

**テスト実行中に検出した実バグ**：`IsEnabled` の初版は `level <= setting_level`
だけを見ており、`LogLevel.Nothing`（6）が閾値は通るが `level <= Debug` の
ブロック外にあるケースで `Record` の実出力と不一致だった。
セクション 9 がこれを検出し、`and level <= LogLevel.Debug` を追加して解消。


---

## 6. fix (4)：`Input/Axis` プロキシの削減（本回）

**55.95ms / 3.9% / 17,448 call（4.04 イベント/frame）** — 優先度 3。

### 6.1 修正前の構造

```lua
-- init.lua:395
local key = event:GetKey().value     -- 2 interop（フィルタ前）
local value = event:GetValue()      -- 1 interop（フィルタ前）
if math.abs(value) > DAV.axis_dead_zone then
    if key:find("IK_Pad") then      -- Lua パターンマッチ
        local current_situation = Def.Situation.Idle
        if DAV.core_obj ~= nil then
            current_situation = DAV.core_obj.event_obj.current_situation or Def.Situation.Idle
        end
        if current_situation == InVehicle or Waiting or Normal then
            DAV.core_obj:ConvertAxisAction(key, value)
        end
    else                            -- 空の死コード
    end
end
```

**コストの順序が逆**。タダで読める situation を後回しにして、
C# を跨がないと読めない `GetKey`/`GetValue` を先に払っていた。

さらに `ConvertAxisAction`（core.lua:1043）が
`local axis_key_list = {"IK_Pad_LeftAxisX", "IK_Pad_LeftAxisY"}` を
**呼び出し毎に新規確保**し、flight mode の分岐ごとにそれを 2 度歩いていた。

### 6.2 修正

**(a) `Etc/def.lua` に共有集合を追加**

```lua
Def.AxisKeySet = {
    IK_Pad_LeftAxisX = true,
    IK_Pad_LeftAxisY = true,
}
```

Mod が実際に処理するのはこの 2 本だけ。それ以外の axis イベントは
アクションに到達し得ないのだから、プロキシと変換関数の両方で
事前に落とせる。

**(b) プロキシを「安い順」に並べ替え**

| 順 | 判定 | コスト |
|---|---|---|
| 1 | `core` / `event_obj` の nil | 純 Lua |
| 2 | situation ∈ {InVehicle, Waiting, Normal} | 純 Lua |
| 3 | `GetValue()` の絶対値 > dead zone | interop 1 回 |
| 4 | `Def.AxisKeySet[key]` | interop 1 回 + ハッシュ参照 |

`GetValue` は `GetKey`（ラッパーを返して `.value` をもう読む）より安いので
**dead zone を先に**置く。通過できないイベントで `GetKey` が丸ごと消える。

**(c) `ConvertAxisAction` から毎回確保を除去**

```lua
function Core:ConvertAxisAction(key, value)
    if not Def.AxisKeySet[key] then return end
    if self.av_obj.is_blocking_operation then ... return end
    local flight_mode = self.av_obj.engine_obj.flight_mode   -- 旧コードは 2 回読んでいた
    if flight_mode == Def.FlightMode.AV then
        self:ConvertAVAxisAction(key, value)
    elseif flight_mode == Def.FlightMode.Helicopter then
        self:ConvertHeliAxisAction(key, value)
    end
end
```

旧コードの `keybind_name` は一致時に `key` と同値なので、そのまま渡している。

### 6.3 不変条件

| 項目 | 保証 |
|---|---|
| キューに積まるアクション | **2160 組合せで全同一**（§6.4 節 2） |
| dead zone の閾値挙動 | 境界値含む 5 ケースで同一 |
| 4 つの実アクションの写像 | 大きさ含む全同一 |
| `is_blocking_operation` の抑制 | 同一 |
| 例外 | 非 axis キーが `ConvertAxisAction` に到達しなくなった結果、`Trace` レベルのログ（常時無効）が出ない。**機能差ゼロ** |

### 6.4 検証

**`tests/axis_proxy_cost_test.lua`（`python tests/run_axis_proxy_cost_test.py`）**

実 `init.lua` をロードし `NewProxy` から `OnAxisInput` コールバックを捕捉、
修正前パイプライン（プロキシ + 旧 `ConvertAxisAction`）を書き写して
**エンドツーエンドで**突き合わせる。**31 passed, 0 failed**

| 節 | 検証内容 |
|---|---|
| 1 | `Def.AxisKeySet` が変換関数の実処理集合と一致（2 成员） |
| **2** | **差分同値：2160 組合せ（6 状況 × 2 flight mode × 非停止 × 10 キー × 9 値）でキュー内容が全同一** |
| 3 | dead zone 境界（`0.1` / `0.1001` / `-0.1` / `-0.1001` / `0`）が同一挙動 |
| 4 | 非 AV 状況（Idle / Landing / core なし）は **GetValue も GetKey も 0 回** |
| 5 | dead zone 未満で `GetKey` が呼ばれない（`GetValue` のみ 1 回） |
| 6 | 非 axis キー（右スティック / キーボード）はアクション生成なし |
| 7 | 4 実アクションの写像 + 大きさ保持 + ヘリ 2 本 |
| 8 | `is_blocking_operation` の抑制 |
| **9** | **コスト台帳** |

#### セクション 9：コスト台帳（実測）

```
  case                         C# reads        tables built
                                  old    new    old    new
  --------------------------------------------------------------
  Idle (no AV)                      2      0      0      0
  Landing                           2      0      0      0
  Normal, below dead zone           2      1      0      0
  InVehicle, below dead zone        2      1      0      0
  InVehicle, right stick            2      2      1      0
  InVehicle, keyboard axis          2      2      0      0
  InVehicle, LeftAxisX              2      2      1      0
  Waiting, LeftAxisY                2      2      1      0
  --------------------------------------------------------------
  TOTAL                            16     10      3      0   -9 of 19 (47%)
```

**非 AV 状況で C# 読み取りが 2 → 0**になったのが最大の効き。
マウス操作・メニュー・徒歩中の axis イベントは**一切 C# を跨がらない**。

`tables built` は全経路で **0**。`axis_key_list` の毎回確保が消えた。

### 6.5 変更ファイル

| ファイル | 変更 |
|---|---|
| `Etc/def.lua` | `Def.AxisKeySet` 追加 |
| `init.lua` | `OnAxisInput` コールバックを安い順のゲートに再構成、空 `else` 削除 |
| `Modules/core.lua` | `ConvertAxisAction` を共有集合 + `flight_mode` 1 回読みに簡略化 |
| `tests/axis_proxy_cost_test.lua` | 新規（31 assertions、2160 組合せ差分同値を含む） |
| `tests/run_axis_proxy_cost_test.py` | 新規ランナー |

---

## 7. 実機での切り分け方（次の調査向け）

今の `profprobe` は Navigation のメソッドしか wrap していない
（navigation.lua:5680 以降）。漏斗の内側を見るには：

```lua
Prof.wrap_methods(AV, {
    {"IsPlayerIn",        "av.is_player_in"},
    {"IsPlayerInEntryArea", "av.in_entry_area"},
    {"GetEulerAngles",    "av.get_euler"},
    {"GetGroundPosition", "av.ground_raycast"},
})
Prof.wrap_methods(Engine, {
    {"Update", "eng.update"},
    {"Run",    "eng.run"},
})
Prof.wrap_methods(Core, {
    {"StorePlayerAction", "core.store_action"},
    {"FindNearestFastTravelPosition", "core.find_ft"},
})
```

`IsPlayerInEntryArea` と `CollectSphericalRepulsion` の `total_ms` が、
この Mod が他 Mod より悪目立ちしている正体。
