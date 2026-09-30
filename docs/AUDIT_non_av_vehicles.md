# 監査：この Mod は AV 以外の車両に影響を及ぼしているか

対象: DriveAerialVehicle v3.3.1
検証: `tests/enter_exit_cost_test.lua` 節 2・3・8
（`Override` / `Observe` / `ObserveAfter` を no-op ではなく**レジストリに捕捉**し、
AV でない車両で各フックを直接駆動している）
関連: `PERF_ANALYSIS_enter_exit.md` / `PERF_ANALYSIS_hooks.md`

---

## 0. 結論

| | 判定 |
|---|---|
| **AV 以外の車両の挙動が変わるか** | **1 件だけある**（入力ヒントの抑制が source 単位） |
| AV 以外の車両の**性能**に影響するか | する。ただし本監査で大半をゼロにした |
| 既存のゲームデータ（TweakDB）を書き換えているか | **いない**（新規レコードの clone のみ） |
| Mod を入れていない状態と同一に復元できるか | できる（Override/Observe は CET 側の機構で、Mod 除去で消える） |

**「AV 以外の車に乗ったら挙動がおかしい」と報告されうるのは §3 の 1 件だけ。**
それ以外は全部「通るだけ」で、通るためのコストが問題だった。

---

## 1. この Mod が仕掛けているフックの全一覧

`enter_exit_cost_test` 節 2 で実行時に捕捉した 25 本 + `init.lua` の 3 本。
**スコープが「AV 以外にも発火」のものは、AV が存在しなくても払い続ける固定費。**

### 1-1. 車両クラスに対する Override（7 本）

| フック | 発火スコープ | AV 以外での挙動 |
|---|---|---|
| `VehicleComponentPS.GetHasAnyDoorOpen` | **全車両のドア状態判定** | `wrapped_method()` にそのまま返す |
| `VehicleTransition.IsUnmountDirectionClosest` | **全車両の降車トランジション** | 同上（`AV:Unmount()` は呼ばれない） |
| `VehicleTransition.IsUnmountDirectionOpposite` | 同上 | 同上 |
| `VehicleSystem.SpawnActivePlayerVehicle` | **全アクティブ車両召喚**（電話・クエスチョン・クイックハック） | DAV レコードでなければ `wrapped_method()` |
| `PlayerPuppet.ActivateIconicCyberware` | プレイヤー全体 | AV 以外では素通し |
| `hudCarController.OnSpeedValueChanged` | **全車両の速度計** | `wrappedMethod()` を呼ぶ |
| `hudCarController.OnRpmValueChanged` | **全車両のタコメータ** | 同上 |

### 1-2. UI / ダイアログに対する Override（3 本）

| フック | 発火スコープ | AV 以外での挙動 |
|---|---|---|
| `InteractionUIBase.OnDialogsData` | 全ダイアログデータ | 搭乗エリアにいなければ素通し |
| `InteractionUIBase.OnDialogsSelectIndex` | 同上 | 同上 |
| `dialogWidgetGameController.OnDialogsActivateHub` | 同上 | 同上 |

→ **AV の搭乗エリアに立っているときだけ**自分の choice hub を差し込む。
搭乗エリアにいなければ一切触らない。

### 1-3. Observe / ObserveAfter（15 本）

| フック | 発火スコープ | 備考 |
|---|---|---|
| `PlayerPuppet.OnAction` | **全入力アクション** | situation が Waiting/InVehicle のときだけ本体が走る |
| `UISystem.QueueEvent`（Observe） | **全 UI イベント**（最も熱い） | §3 の副作用はここ |
| `UISystem.QueueEvent`（ObserveAfter） | 同上 | exception アクションの抑制 |
| `BaseMappinBaseController.IsTracked` | **全マッピング（数百個）** | 未削減。`PERF_ANALYSIS_hooks.md` 優先度 2 |
| `BaseMappinBaseController.UpdateRootState` | 同上 | 同上 |
| `VehicleComponent.ReactToHPChange` | **全車両の HP 変化** | 戦闘中に多数発火。未削減 |
| `Entity.ScheduleAppearanceChange` | 全エンティティ | 即 return で安い |
| `InteractionUIBase.OnInitialize` / `OnDialogsData` | UI 初期化 | 安価 |
| `hudCarController.OnInitialize` / `OnMountingEvent` | 車両 HUD のマウント | mph ラベルのキャッシュ破棄のみ |
| `PopupsManager.OnPlayerAttach` | ポップアップ | 安価 |
| `HotkeyConsumableWidgetController.OnInitialize` | HUD | 安価 |
| `PhoneHotkeyController.Initialize` | HUD | 安価 |
| `gameuiPhotoModeMenuController.OnPhotoModeLastInputDeviceEvent` | フォトモードのみ | 安価 |

### 1-4. init.lua の入力フック（3 本）

| フック | 発火スコープ | 状況 |
|---|---|---|
| `NewProxy Input/Key` | **全キー入出力** | `IACT_Release` は situation 非依存で `ConvertHoldButtonAction(key)` を呼ぶ（§4-参照） |
| `NewProxy Input/Axis` | **全軸入力** | fix (4) で situation ゲート済み。非 AV 時は C# を跨がない |
| `Observe SettingsSelectorControllerKeyBinding.ListenForInput` | キーバインド設定時 | 安価 |

---

## 2. 挙動が変わらないことの検証（節 3）

ハーネス上のワールド状態：
**AV はテスト対象ではない**（`entity_id = nil` または停車中、situation = Normal）、
プレイヤーはただの車に乗っている。各フックを叩いて、
**Mod が無いときゲームが出したはずの答えを返すか**を確認した。

| 検証 | 結果 |
|---|---|
| 他人の車の `GetHasAnyDoorOpen` → ゲーム自身の答えが返る | PASS |
| 他人の車のドア判定で **AV を覗きにいかない**（`IsPlayerMounted` 0 回） | PASS |
| AV 停車中でも他人の車のドア状態は抑制されない | PASS |
| 他人の降車トランジションで **`AV:Unmount()` が呼ばれない** | PASS |
| 非AV降車トランジションで `Game.GetPlayer()` を呼ばない（fix 27 の効果） | PASS（2 回 → 0 回） |
| AV 外で `ActivateIconicCyberware` がブロックされない | PASS |
| 非 DAV レコードの `SpawnActivePlayerVehicle` はゲーム側にフォールスルー | PASS |
| `GetActivePlayerVehicle` が nil のケースもフォールスルー | PASS |
| 他人の車の速度計・タコメータはゲームのハンドラに届く | PASS |
| **壊れた AV を降りた後に残る `is_manually_setting_speed` が、他人の車の HUD を凍結できない** | PASS |

最後の 1 件は実ゲームで到達しうる状態なので特意検証している。
`Event:CheckDestroyed()` は `EnableManualMeter(false, …)` を呼ばないので、
**AV が爆発したあと manual-meter フラグが true のまま残る**。
それでも `hudCarController` のゲートが

```lua
if not DAV.core_obj.event_obj:IsInAVSituation() or not self.is_manually_setting_speed then
    result = wrappedMethod(speedValue)
end
```

と **situation を先に見ている**ため、situation が Normal の限り他人の車の
HUD は正常に描画される。**situation ベースのゲートだったからこそ助かっている箇所。**

---

## 3. 挙動が変わる唯一の箇所：`VehicleDriver` 入力ヒントの抑制

```lua
Observe("UISystem", "QueueEvent", function(this, event)
    if DAV.core_obj.event_obj:IsInEntryArea() or DAV.core_obj.event_obj:IsInVehicle() then
        if event:IsA(StringToName("gameuiUpdateInputHintEvent")) then
            if event.data.source == CName.new("VehicleDriver") then
                -- DeleteInputHintBySourceEvent を積んで消す
```

**抑制のキーが「車両エンティティ」ではなく「ヒントの source」になっている。**

結果：

| プレイヤーの位置 | 効果 |
|---|---|
| AV の搭乗エリア内（`entry_area_radius`、車種により 2.5〜4.0m） | `VehicleDriver` source のヒントが全部消える。**AV の隣に止めた普通の車の「乗る」ヒントも含む** |
| AV から離れている | 消えない |
| situation = Normal（AV 未召喚） | 消えない |
| 別の source（例：`FootDriver`） | 消えない |

`enter_exit_cost_test` 節 8 で 4 パターン全部を実測で固定している。

### これはバグか

設計上の意図は「AV に対してゲーム標準の『乗る』ヒントを出さない」こと。
ただし source 単位の抑制なので、**AV の隣に停車した一般車両にも効く**。

- 厳密にやるなら `event.data` から対象エンティティを解決して AV と比較する必要がある
  が、`gameuiUpdateInputHintEvent` は対象エンティティを持っていない
- 実害は「AV の隣に車を停めると、その車の乗るヒントが一瞬消える」程度で、
  搭乗自体はキー入力で可能

**現状は「既知の副作用」として据え置き。** 報告が上がったらここを見ること。

同系統でもう 1 本：`ObserveAfter("UISystem", "QueueEvent")` が
`exception_input_hint.json` のアクションを `IsInVehicle()` 中に隠す。
これは AV 搭乗中にしか効かないので他車両への影響はない（節 8 で検証済み）。

---

## 4. 性能だけの影響（挙動不変だがコストを払っていた箇所）

`PERF_ANALYSIS_hooks.md` の計測（4322 フレーム）で、
**DAV の Lua コストの 24.2% は `onUpdate` の漏斗の外**にあった。
そのうち「AV の有無と無関係に発火する」グローバルフックが 341.6ms / 43,270 call。

今回の修正でそのうち動いた分：

| フック | 修正前（非AV時） | 修正後 |
|---|---|---|
| `VehicleTransition.IsUnmountDirectionClosest/Opposite` | 2 tr（`Game.GetPlayer`） | **0 tr** |
| `VehicleComponentPS.GetHasAnyDoorOpen` | 0 tr（`and` 短絡で既に安かった） | 0 tr（保証として明示） |
| `Input/Axis` proxy | fix (4) で 0 tr 済み | 0 tr |

**動かなかった主要項（次回の対象）：**

| フック | 実測（hooks doc） | 状態 |
|---|---|---|
| `PlayerPuppet.OnAction` | 208.7ms / 14.4% | fix (3) で削減済み。Waiting 中はまだ `IsPlayerInEntryArea()` を払う |
| `BaseMappinBaseController.IsTracked` + `UpdateRootState` | 39.5ms / 2.7% | **未着手**。全マッピングで `GetMappin()` + `GetVariant()` |
| `UISystem.QueueEvent`（Observe + ObserveAfter） | 2.6ms | **未着手**。`StringToName(...)` をイベント毎に生成している（定数化可能） |
| `Input/Key` proxy | 小 | `IACT_Release` が situation 非依存。キーリリース毎に keybind 表を線形スキャン（最大 27 比較） |

---

## 5. TweakDB / ゲームデータへの書き込み

`registerForEvent("onTweak")` と `Camera:SetPerspective` が書くのは
**すべて DAV が新規に clone したレコード**のみ：

- `Vehicle.*_dav`（excalibur / manticore / atlus / surveyor / valgus / mayhem）
- `Camera.VehicleTPP_4w_Preset_*_DAV`（12 preset）
- `Vehicle.VehicleDriverFPPCameraParamsDefault_DAV`

**バニラの車両レコード・カメラプリセットは 1 つも書き換えていない。**
Mod を消せば残るような永続的な変更はない。

注意すべき点として、`Vehicle.av_zetatech_surveyor_inline0_dav` は
`Vehicle.av_zetatech_atlus_inline0` から clone されている
（他の AV が自車種から clone しているのに対し surveyor だけ atlus 由来）。
**元レコードの書き換えではないので他車両への影響はない**が、
意図した clone 元かどうかは一度確認しておいてよい箇所。

---

## 6. 監査の再現方法

```
python tests/run_enter_exit_cost_test.py
```

- **節 2**：グローバルフックの全一覧をピン留め。
  新規グローバルフックを追加してこのリストに載せないとテストが落ちる。
  → 「いつの間にやら全車両にフックが伸びる」ことを構造的に防げる
- **節 3**：非AV車両で全車両フックを駆動し、透過性と `AV:Unmount()` 非起動を確認
- **節 8**：入力ヒント抑制のスコープを実測

`init.lua` の `Observe:SettingsSelectorControllerKeyBinding.ListenForInput` と
`NewProxy Input/Key` / `Input/Axis` は CET エントリポイント側なので
このハーネスでは捕捉していない。**手で監査済み**（§1-4）。

---

## 7. 残っているリスク（次回に回すもの）

| # | 内容 | 影響 |
|---|---|---|
| 1 | 入力ヒント抑制が source 単位（§3） | AV 隣接車両の「乗る」ヒントが消える |
| 2 | Mappin observer が全マッピングで発火 | 39.5ms / 4322f。ID 先比較でほぼ消せる |
| 3 | `StringToName` を UI イベント毎に生成 | 定数化で消せる |
| 4 | `Input/Key` の release 経路が situation 非依存 | 歩行中の全キーリリースで keybind 表を舐める |
| 5 | `VehicleComponent.ReactToHPChange` が全車両で発火 | 戦闘時に多数。`av_obj.entity_id == nil` で早期 return 済み |
