# 性能解析：車両の乗り降りで画面がカクつく

対象: DriveAerialVehicle v3.3.1
計測: `tests/enter_exit_cost_test.lua`（実モジュール + CET/REDscript API スタブ、
Lua→C# 遷移回数・ディスクオープン回数・ ウィジェット 生成数を実測）
ランナー: `python tests/run_enter_exit_cost_test.py`
関連: `PERF_ANALYSIS_hooks.md` / `PERF_ANALYSIS_situations.md` / `AUDIT_non_av_vehicles.md`
本ドキュメントの修正は通し番号で **fix (23)〜(27)**

---

## 0. 報告された現象

> 車両の乗り降りで画面がカクつくことがあります。

乗り降りは 1 フレームで完結しない。**キー入力から運転可能になるまで 3 秒、
降車開始からプレイヤー着地まで 1〜3 秒**の間に、MOD 側の仕事とゲーム側の
仕事（HUD 差し替え・搭乗アニメ・物理引き継ぎ）が重なって走る。
なので「乗り降りの瞬間に重い」を切り分けるには、**経路を時刻順に分解して
各ブロックの実コストを数える**しかない。

それをやったのが `tests/enter_exit_cost_test.lua`。

---

## 1. 乗り降りのタイムライン（実コードの経路）

### 搭乗（Waiting → InVehicle）

| 時刻 | 実行されるもの | 箇所 |
|---|---|---|
| t=0 | `Core:SetEvent(Enter)` → `Event:EnterVehicle()` → `AV:Mount()` | core.lua / event.lua / av.lua:727 |
| t=0 | └ `Camera:SetPerspective(seat)` → **TweakDB SetFlat ×36** | camera.lua:60 |
| t=0 | └ `Game.GetMountingFacility():Mount()` → ゲームが搭乗アニメ開始・HUD 差し替え | av.lua |
| t=0 | └ `ToggleCrystalDome()`（該当車種） / `StartObstacleRecording()`（既定 off） | av.lua |
| t+0.01 | `Event:CheckInAV()` 遷移 tick：`SaveLocks.Add` / `HideChoice` / `EnableOriginalPhysics(false)` / `SetControlType(AddForce)` | event.lua:430 |
| **t+1.5s** | `ForceShowMeter()` + `ShowLeftBottomHUD()` → `CreateHPDisplay()`（**ink ウィジェット 生成**） | event.lua → hud.lua:271,388 |
| **t+3.0s** | `ShowCustomHint()` → `SetCustomHint()`（**JSON 読込 + ローカライズ + イベント構築**） | hud.lua:1190→ |

### 降車（InVehicle → Waiting）

| 時刻 | 実行されるもの | 箇所 |
|---|---|---|
| t=0 | `VehicleTransition.IsUnmountDirectionClosest` override → `AV:Unmount()` | event.lua:222 / av.lua:779 |
| t=0 | └ `ControlCrystalDome()` / `ChangeDoorState(Open)`（ドア毎 PS イベント） | av.lua |
| t=0 | `Event:CheckInAV()` 遷移 tick：`HideLeftBottomHUD` / `HideCustomHint` / `EnableManualMeter(false)` / `ToggleOriginalMPHDisplay` / **`EnableOriginalPhysics(true)`** / `InterruptAutoPilot` / `SaveLocks.Remove` | event.lua:430 |
| t+exit_duration | 100Hz ポーリング → **`Game.GetTeleportationFacility():Teleport(player, …)`** | av.lua:809 |

`exit_duration` は車種ごとに 0.8〜2.3 秒（init.lua の `exitDelay` 相当）。

---

## 2. 実測（修正前 → 修正後）

`enter_exit_cost_test` を同じハーネスで、修正前（git HEAD を stash したもの）と
修正後の両方走らせた実数。**tr = Lua→C# 遷移回数**。

| 経路 | 修正前 | 修正後 | 差分 |
|---|---|---|---|
| `AV:Mount()` 1回目 | 93 tr / TweakDB書込 **36** | 93 tr / **36** | 初回は必要 |
| `AV:Mount()` 同シート再搭乗 | 93 tr / **36** | **9 tr / 0** | **−90%** |
| Waiting→InVehicle 遷移 tick | 5 tr | 5 tr | — |
| +1.5s グループ（メータ＋HP表示） | 53 tr / ウィジェット 3 | 53 tr / ウィジェット 3 | — |
| +3.0s `ShowCustomHint` 初回 | 22 tr / disk 1 / loc 3 | 23 tr / disk 1 / loc 3 | 初回は必要 |
| `ShowCustomHint` 2回目以降 | 22 tr / **disk 1 / loc 3** | **17 tr / disk 0 / loc 0** | **−23%** |
| InVehicle→Waiting 遷移 tick | 16 tr | 16 tr | — |
| `SetInputHintController`（解決済み） | 3 tr / ink walk 1 | **0 tr / 0** | **−100%** |
| `GetExpectedHintTexts` 再呼び出し | 5 tr / **disk 2 / loc 2** | **0 tr / disk 0 / loc 0** | **−100%** |
| `ReconstructInputHint` | 711 tr / **disk 1** | 711 tr / **disk 0** | disk −100% |
| 非AV車両の降車トランジション | 2 tr（`GetPlayer`） | **0 tr** | **−100%** |

`loc` = `GetLocalizedText`（C# ローカライズ参照）。

---

## 3. 原因と修正

### fix (23)：設定 JSON をセッションで 1 回しか読まない（`Etc/utils.lua`）

`Utils:ReadJson()` は **呼ばれるたびに `io.open` + 全読み込み + JSON デコード**。
そして乗り降りの経路上に 4 箇所あった。

| ファイル | 旧呼び出し元 | 頻度 |
|---|---|---|
| `Data/input_hint.json` | `HUD:SetCustomHint` | 搭乗毎・入力デバイス変更毎 |
| `Data/input_hint_override.json` | `HUD:ReconstructInputHint` / `GetExpectedHintTexts` | 走行中 2 秒毎 |
| `Data/input_hint_mapping.json` | `HUD:Init` | `Core:Reset` 毎 |
| `Data/exception_input_hint.json` | `HUD:SetObserve` | 起動時 |

`Utils:ReadJsonCached(path)` を追加。初回だけディスクし、以降はメモリ上の
デコード済みテーブルを返す。**読み取り専用**で使う前提（呼び出し側が
変更する場合はコピーしてから）。ファイル欠損も `false` としてキャッシュするので、
パスのタイプミスが「呼び出し毎に失敗し続ける」ことにはならない。

### fix (24)：`Camera:SetPerspective` の冗長な TweakDB 書き込みを止める

搭乗 1 回で **`TweakDB:SetFlat` ×36 + `TweakDBID.new` ×36 + `Vector3.new` ×12**。
しかもこれは **ゲームが HUD を差し替え、搭乗アニメを始め、物理を引き継いでいる
まさにそのフレーム**で走る。

シート index・モデル index・ratio/offset テーブルのいずれもが変わっていなければ
**36 書き込みをまるごとスキップ**。末尾の FPP フォールバック
（FPP 非対応車種を FPP に置かない）は毎回実行するので挙動は不変。

| ケース | 修正前 | 修正後 |
|---|---|---|
| 初回搭乗（シート1） | 36 書込 | 36 書込 |
| 再搭乗（同シート） | 36 書込 | **0 書込** |
| 別シートを指定 | 36 書込 | 36 書込 |

### fix (25)：ヒント生成を状態キーでメモ化（`Modules/hud.lua`）

`SetCustomHint()` は毎回「ファイル読む → フィルター → 全ラベルをローカライズ
→ イベント構築」をやっていた。入力内容が決まるのは
**(flight mode, 入力デバイス, コンバットシート) の 3 つだけ**なので、
その組み合わせで計算結果をキャッシュ。

`HUD:HintStateKey()` = `flight_mode | keyboard | combat_seat`。

- 同一状態の再呼び出し：**disk 0 / GetLocalizedText 0**
- 入力デバイスが変わったら → 新しいキーで**ちゃんと計算し直す**
- `IsMountedCombatSeat()`（C# 往復）も 1 回で済む
  （旧：フィルタの要素数だけ呼んでいた）

**`SetCustomHint` は読み出したテーブルを `table.remove` で破壊していた**ため、
共有キャッシュを守るために**浅いコピーに対してフィルタ**している。
フィルタロジックと順序は旧コードから 1 文字も変えていない
（§5 の等価性テストで保証）。

キーは `HUD:HintStateKey(include_combat_seat)` の 2 形状：

| 使い道 | キー | C# 往復 |
|---|---|---|
| ヒント一覧そのもの（シートでフィルタされる） | `flight_mode \| device \| combat_seat` | あり（1 回） |
| `GetExpectedHintTexts`（旧コードもシートに依存しない） | `flight_mode \| device \| 0` | **なし** |

後者を `combat_seat` 込みのキーにすると、**値が変わらないのに 2 秒ごとに
`IsMountedCombatSeat()`（C# 往復）を払う**ことになる。旧コードはそれを
払っていなかったので、キーも旧コードの依存関係に合わせてある。

### fix (26)：`SetInputHintController` を解決済みなら何もしない

旧コードは 2 秒ごとに
`Game.GetInkSystem()` → `GetLayer("inkHUDLayer")` → `GetGameControllers()` →
`controller:ToString()` ループ、という **C# の HUD レイヤー総なめ**をやっていた。

解決済みハンドルがあれば即 return。
ハンドルが古くなって後段の `pcall` が失敗した場所（`ReconstructInputHint` /
`IsVisibleCustomInputHints`）で `input_hint_controller = nil` にするので、
次回呼び出しで自動的に再解決される（自己回復）。

### fix (27)：車両全体 Override の先頭を純 Lua ゲートに（`Modules/event.lua`）

`GetHasAnyDoorOpen` / `IsUnmountDirectionClosest` / `IsUnmountDirectionOpposite` は
**AV だけでなく Night City の全車両**に発火する。
`Event:IsInVehicle()` は C# 往復（`FindEntityByID` + `IsPlayerMounted`）で答えるが、
その**第 1 条件はただの Lua フィールド読み**なので、そこを先に見て
AV でないなら即 `wrapped_method()` に返す。

```lua
if self.current_situation ~= Def.Situation.InVehicle then
    return wrapped_method()
end
if self.av_obj ~= nil and self.av_obj:IsPlayerIn() then
    return false
end
return wrapped_method()
```

`IsInVehicle()` との等価性：この 2 チェックの間で `current_situation` を
変える処理は走らない。`av_obj ~= nil` は念のための堅牢化。

効果は `VehicleTransition` 側で実測 **2 tr → 0 tr**（非AV降車毎）。
`GetHasAnyDoorOpen` 側は `IsInVehicle()` の `and` 短絡が既に効いていたため
実測差はゼロ。**この修正は「AV を触りにいかない」ことを明示する保証修正**で、
性能上の目玉ではない。

---

## 4. 修正しなかったもの（重要：次回の候補）

### 4-1. `ReconstructInputHint` の 711 遷移 / 87 ウィジェット 生成

**今回見つかった一発コストとしては最大項。**
`Event:CheckInput()` は走行中 2 秒ごとに

```
SetInputHintController()      … HUD レイヤー総なめ（fix 26 で 0 に）
IsVisibleCustomInputHints()   … 設定読込＋ローカライズ（fix 25 で 0 に）
  ↓ ヒントが見えていないと判定されたら
ReconstructInputHint()        … 711 遷移 / 87 ウィジェット 生成
```

を走らせる。**ヒントが何らかの理由で見えていない状態が続くと 2 秒ごとに 87 個
の ink ウィジェット を作り直す**。搭乗 2 秒後ちょうどにこれが落ちると、それはもう
「乗り降りのカクつき」にしか見えない。

今回ここには手を入れなかった理由：

- `IsVisibleCustomInputHints()` の判定は `for i = 0, 50` のインデックス走査で
  **ink の `IsVisible()` が自身の可視性か実効可視性かに依存**する。
  名前指定（`hint_1`〜`hint_N`）に替えると判定の意味が変わり、
  「ヒントが消えているのに再構築されない」系のバグを踏みうる。
- 生成済み ウィジェット のプール化は、`delete_custom_input_flag`（LTBF 互換で
  ヒントを強制削除する経路）との相互作用を確認しないと壊せる。

**次の一手として最有力。** いじるなら
`IsVisibleCustomInputHints` の実装を先に実機で計装して、
「再構築が実際に何回走っているか」を先に測るべき。

### 4-2. ゲーム側の仕事（MOD では削れない）

| 項目 | 内容 |
|---|---|
| HUD 差し替え | `hudCarController` の mount/unmount。MOD のフックは観察しているだけ |
| 搭乗/降車アニメ | `MountingFacility:Mount()` 側 |
| 物理の引き継ぎ | `EnableOriginalPhysics(true/false)`。降車時にゲーム本来の車両物理を復元する。**この処理自体が重い** |
| `Teleport` | 降車時のプレイヤー転送。セルストリーミング・物理・カメラの再初期化。**カスタム降車位置の実装には必須** |
| 保存ロック | `SaveLocksManager.RequestSaveLockAdd/Remove` |

`EnableOriginalPhysics(true)` と `Teleport` は「降車時に必ず走る重い処理」として
切り分け済み。どちらも機能上消せない。

### 4-3. Lua GC

上記すべてのアロケーション（JSON テーブル、CName、イベント、ウィジェット ハンドル）は
Lua GC に載る。CET の Lua VM は単一ロックなので、GC ステップが乗ったフレームは
どこでカクついてもおかしくない。
`gc_spike_probe.lua` で実機確認すること。

---

## 5. 検証

`python tests/run_enter_exit_cost_test.py` — **52 passed, 0 failed**

| 節 | 内容 |
|---|---|
| 1 | ハーネス健全性（実モジュールロード、フック捕捉 25 本） |
| 2 | **グローバルフック一覧のピン留め**。監査済みの 25 本以外に新規グローバルフックが増えたら落ちる |
| 3 | 非AV車両で全車両フックを駆動 → 挙動がゲーム単体と同一（詳細は `AUDIT_non_av_vehicles.md`） |
| 4 | 搭乗経路のコスト台帳：`AV:Mount()` 初回/再搭乗/別シート、遷移 tick、+1.5s、+3.0s |
| 5 | 降車経路のコスト台帳：`AV:Unmount()`、転送ポーリング、遷移 tick |
| 6 | 走行中 2 秒周期のヒント更新：cold/warm 解決、`ReconstructInputHint` の実到達確認 |
| **7** | **等価性：修正前の `SetCustomHint` 本体を書写し、6 状態（AV/Heli × keyboard/pad × シート1/2）× 5 フィールドで全一致** |
| 8 | 入力ヒント抑制のスコープ検証（AV 隣接車両への副作用の実在確認） |

第 7 節が最重要。「キャッシュしたから速い」だけでなく、
**キャッシュ前の計算と 1 フィールドも違わない**ことを網羅で示している。

既存テストへの影響（すべて従来どおり pass）：

```
situation_cost_test    54 passed
onaction_cost_test     40 passed
axis_proxy_cost_test   31 passed
entity_cache_test      30 passed
height_cache_test      31 passed
```

`run_resident_cache_test.py` は `Data/map`（テキスト形式）が存在せず失敗するが、
packed-only 移行時の既存事象で本変更とは無関係。

---

## 6. 実機での確認手順

1. `debug.txt` を CET フォルダに置いてデバッグモードで起動
2. 同一セーブで AV に **5 回乗り降り**（毎回同じシート）
3. 乗り降りのたびにフレームタイムを観察
   （`DAV.is_debug_situation_ledger = true` で状況別集計も出る）
4. 入力デバイスを実際に変えて（キーボード→パッド）ヒントが出直すのを確認
   → ここが再計算されるべき唯一のタイミング
5. 車種切り替え（`toggle_appearance`）後にシート位置・カメラが正しいか確認
   → fix (24) のキャッシュキーが壊れていないかの確認

### 期待できる体感

- **2 回目以降の搭乗**でカメラ書き込み 36 回が消える
- **ヒント関連のディスクアクセスがセッション中 1 回以下**になる
- 走行中の 2 秒周期処理が軽くなる（ヒント再構築が走らなければほぼゼロ）

### 消えないもの

- 初回搭乗の 36 TweakDB 書き込み（初回は必要）
- `ReconstructInputHint` が走ったときの 87 ウィジェット 生成（§4-1）
- 降車時の `Teleport` と `EnableOriginalPhysics(true)`（機能上必須）

---

## 7. 変更ファイル

| ファイル | 変更 |
|---|---|
| `Etc/utils.lua` | `ReadJsonCached` / `InvalidateJsonCache` / `JSON_CACHE` 追加 |
| `Modules/camera.lua` | `ApplyFppFallback()` 抽出、`SetPerspective` に 4 要素のキャッシュキー |
| `Modules/hud.lua` | 4 つの JSON 読みをキャッシュ化、`HintStateKey` / `GetPreparedCustomHints` 追加、`SetCustomHint` を非破壊＋メモ化に、`GetExpectedHintTexts` メモ化、`SetInputHintController` を解決済みスキップ＋自己回復 |
| `Modules/event.lua` | 車両全体 Override 3 本を純 Lua ゲート先行に |
| `tests/enter_exit_cost_test.lua` | 新規（52 assertions） |
| `tests/run_enter_exit_cost_test.py` | 新規ランナー |
