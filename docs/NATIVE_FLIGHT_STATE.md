# 飛行制御のネイティブ化 — 現状まとめ

最終更新: 2026-10-13（Lua フォールバック削除）

CET の Lua が毎フレームやっていた飛行制御の駆動を、RED4ext の DLL 側へ移した結果の
現在地をまとめるもの。設計の背景と判断の理由は §1 と §7 に置いてあり、コード中のコメントは
この文書に依存しない（コード単体で読める短さにしてある）。

---

## 1. 目的と到達点

### 目的
CET の `onUpdate` / Cron から「毎フレーム物理を押しにいく」ループを消す。
物理への作用は物理フック（イベント駆動のネイティブ側）で行い、Lua は**状態が変わったときだけ**
コマンドを push する、という形にする。

### 到達点
| 状態 | 变更前 | 現在 |
|---|---|---|
| 未搭乗（Waiting）の飛行駆動 | `Engine:Update` が毎フレーム（約 60 回/秒）、1 回につき地面レイキャスト 1 本＋ゲーム API 約 6 呼び | **Lua からのゲーム呼び出し 0**。DLL が物理ティック（約 60 Hz）で高度と姿勢を保持 |
| 未搭乗時の地面レイキャスト | 約 20 本/秒（Lua） | **DLL が 2 本/秒**（ゲームスレッド） |
| 搭乗中の手動飛行 | Lua が毎フレーム演算 | DLL の flight model（mode 3）。Lua は入力のエッジのみ |
| 入力アクション | キューを毎ティック poll | 入力コールバックから直接 drain |
| メニュー／ポップアップ／フォト判定 | 毎フレーム poll | UI のオブザーバからのエッジ通知 |

---

## 2. DLL の飛行モード

`SetFlightControl(mode, ...)` で Lua が push する。物理フックが毎ティック読む。

| mode | 内容 |
|---|---|
| 0 | off。DLL は何も適用しない（Lua 駆動のフォールバックは削除済み。DLL 必須） |
| 1 | トルク／フォース加算（搭乗中の従来系） |
| 2 | 速度・角速度を直接保持。**push-on-change**（値が変わったときだけ Lua が push、以降 DLL が保持） |
| 3 | 手動飛行の flight model 全体を DLL が演算（`Engine:CalculateAddVelocity` / `Run` の移植） |
| 4 | 未搭乗時のホバー調整器（高度＋姿勢復元）を DLL が演算 |

mode 4 は `SetIdleHoverParams` で 17 個のゲインを渡す（順序は `IdleParams` 構造体と一致させる）。
mode 4 は Lua のターゲットが非ゼロのあいだは自動的に mode 2 として振る舞う。
（スクリプトで降下などを命令されている最中に調整器が上書きできないようにするため）

---

## 3. Lua 側で入れた変更

### 3.1 速度保持を DLL に移し、変化時だけ push
未搭乗時の「今の速度を保持し続ける」処理を mode 2 に移した。Lua はターゲットが動いたときだけ
push し、デッドバンド（`native_hold` との比較。直前のコマンドではなく **DLL が実際に保持している値**
に対して測る）以内なら push しない。

### 3.2 メニューゲートのイベント化
`IsInMenuOrPopupOrPhoto()` を毎フレーム呼ぶのをやめ、UI のオブザーバからエッジで受け取る。

### 3.3 `Engine:Update` を削除
毎フレームのモード決定を全廃し、**状態が変わった地点だけで**モードを決める
（`Engine:ApplyControlMode`）。ここが今回の主役で、他の変更はこれに続く回帰修正。

### 3.4 離陸旋回ユニットの誤り
`AutoLeaving` の終盤旋回が **度数を rad/s として扱っていた**（最大 10 rad/s ≒ 570 deg/s）。
有界の `turn_rate` に置換（`leaving_yaw_align_deg = 2.0`、`leaving_yaw_min_rate = 0.06`）。

### 3.5 停止距離ブレーキ
障害物減速が `autopilot_min_speed_rate = 0.4`（= 10 m/s）を床としていたため、壁手前で
10.5 m 以内に入ったときだけ減速して時速 36 km のまま衝突していた。
停止距離から逆算した速度上限に変える:

```
v_cap = sqrt(2 * autopilot_brake_decel * max(0, min_fwd_dist - autopilot_brake_margin))
```

この上限はクルーズ下限の**後**に適用する（下限は快適性の制限であって衝突の制限ではないため）。
`autopilot_brake_decel = 6.0`、`autopilot_brake_margin = 3.0`。
上限は毎ティッククリアする（A* フェーズが古い上限を引き継がないように）。

### 3.6 未搭乗ホバーの DLL 化（mode 4）
`CalculateIdleMode` と `Engine:Run` の姿勢復元をそのまま移植した。**意図的に二重の復元を再現**して
ある（この重複が「ホバーが硬い」という感触の正体）。地面 Z は DLL が公開する値を使い、
Lua はホバー開始時に 1 回だけ seed する。

### 3.7 入力の直接 drain
`Core:EnqueueAction` が即座にドレインする。ただし `Def.ActionList.Enter` 以上の**操作系**は
ループ側に回す（入力コールバック内でゲームへ再入するのは安全でないため）。

### 3.8 地面と高度を DLL から読む
DLL がゲームスレッドで `av_z` / `on_ground` / `ground_z` を公開し、Lua は Waiting 中に
レイキャストしなくなった。`waiting_loop_interval` を 0.05 → 0.15 s に延ばせるようになった
（退避・エリア・距離・高度は歩きプレイヤーに対して 0.15 s では区別できない）。

### 3.9 DLL 発の地面レイキャスト
`GetSpatialQueriesSystem()` ＋ `SyncRaycastByQueryFilter` を DLL から呼ぶ。
**シグネチャを一切ハードコードしていない**（下表）。

| 読むもの | 方法 |
|---|---|
| 引数の役割（from / to / filter / bool / out） | 宣言型名と `isOut` / `isReturn` |
| フィルタの `mask1` / `mask2` オフセット | 型名に `QueryFilter` を含むパラメータのプロパティ検索 |
| ヒット位置の z | out 型の `position` プロパティ + 8 |

読み解けない場合は**レイキャスト自身を無効化**して Lua 側に任せる。レイアウト違いは例外ではなく
アクセス違反なので呼び出しは例外ガードで覆ってある。実行はゲームステートの OnUpdate、
**ネイティブホバーが動いている間だけ** 30 フレームに 1 回（約 2 本/秒）。

衝突グループはユーザー設定なので Lua が `SetGroundQuery` で 1 回渡す。DLL 側にもデフォルト値を
コンパイルしてあり、渡ってこなくても動く（ただし Lua 側が正しければそちらが優先）。

### 3.10 帰還シーケンス
降車時の「hop → 降下 → 消滅」は着陸用の処理が残っていたもの。降下を削除し、
**上昇しながら一定時間で消える**形にした。上昇は 1 m/s から始まり、タイムアウトにちょうど
最高速（5 m/s）で届くようランプする。進捗は `up_timeout` に対する割合で測る
（`up_timeout` を変えても 2 か所目を触らなくてよい／メニューで停止してもランプが先行しない）。

---

### 3.11 Lua フォールバックの削除（DLL 必須化）
移植済みのものをフォールバックとして Lua に残す意味がなくなったので、以下を削除した:

- `is_enable_native_flight` / `is_enable_native_idle`（開発者スイッチ）と capability pcall ゲート
  （`native_control` / `native_flight_model` / `native_idle_ok` / `native_ground_ok` 等のフラグ群）
- `Engine:DisableNative` と `Engine:WatchNativeTick`（ウォッチドッグ→Lua への切替機構そのもの）。
  `Heartbeat` の物理強制は「フックが一度でも tick したか」（`GetNativeTickCount > 0`）でゲート
- `Engine:ApplyLuaFlightModel` と `PushVelocityHold` の直接 `ChangeVelocity` 書き込み
- `Engine:Run` / `CalculateAddVelocity` の**手動飛行フォールバックとしての使用**（`AV:Operate` のレガシー経路）。
  関数自体はオートパイロット（navigation.lua）と `DespawnFromGround` が現役で使うので残す
- `PushNativeCommands` のレガシーコマンド詰め（`native_cmd_ok`）、`Core:PushNative` の capability ゲート、
  `LoopTick` の「DLL なしは毎ティック書き続ける」分岐、`AddForce`/`AddVelocity`/`ChangeVelocity`/`SetForce`/`SetTorque` の
  Lua 駆動用ラッパー

## 4. DLL が新たに備えたもの

| 機能 | 内容 |
|---|---|
| ゲームステート | `EGameStateType::Running` で登録。**ゲームスレッドで毎フレーム**走る。物理フックは物理スレッドなので、ワールドを触る仕事はこちら |
| 公開値 | `av_z` / `on_ground` / `ground_z` / `valid`（`GetGroundInfo` が Vector4 で返す） |
| `SetGroundReference(z)` | Lua からの初期 seed |
| `SetGroundQuery(offset, distance, mask1, mask2)` | DLL 発レイキャストのパラメータ引き継ぎ |
| `SetIdleHoverParams(...)` | mode 4 のゲイン 17 個 |
| 地面学習 | **接地したフレームのみ**地面 Z を覚える（毎フレーム覚えると発振する） |

---

## 5. はまりどころ（再現すると必ず当たる）

| 事象 | 原因 |
|---|---|
| 着陸直前に機体が激しく揺れて消える | 接地中に毎フレーム地面を再学習 → 高度が常に 0 と読める → 調整器が押し上げ → 浮いて古い地面基準に戻る → 再接地、の無限ループ。**接地エッジのみ学習**で解消 |
| 障害物に衝突した姿勢のまま固まる | Lua は `not IsCollision()` のときだけ高度項を使っていた。これをホバー開始時に焼き付けたため、接地していても上へ押し続けて接触体と互いに押し合った。フック内で公開済みの接地フラグを見て高度項を切る |
| 姿勢が変な方向に復元して固まる | 姿勢を物理クォータニオンから計算していた。flight model が検証済みで優先する**エンティティ上のクォータニオン**を優先するよう統一 |
| respawn 後のホバーが変な高度へ飛ぶ | 前の車両の地面基準が残っていた。車両差し替え時にリセット |
| 離陸直後にホバーが上昇を打ち消す | `SetControlType` がホバー所有権を再判定して mode 4 が発火する。スクリプトで駆動する間は明示的に解除する |
| 未搭乗で鈎が動かない | 物理フックは**未搭乗でもフルレートで発火する**（ドキュメント 0.10 の記述は誤り） |

---

## 6. 残っているもの

### 6.1 `Core:ControlTick`（残る。消せない）
`main_loop_timer = Cron.Every(applied, ...)` で約 20 Hz。Waiting では大半が `sleep`
（ゲーム呼び出し 0、`os.clock()` 比較のみ）で、`waiting_loop_interval` = 0.15 s ごとに `run` して
`CheckAllEvents()` と `GetActions()` を実行する。個々のチェックはさらに独自スロットルで間引かれる。

残す理由:
1. 状況機械の心拍。ゲームは「プレイヤーが離れた」「AV が流れた」をプッシュしない
2. `GetActions()` — 操作系アクションは意図的にループ側で drain する
3. 実測 dt のサンプラーが一定レートを前提にする
4. Landing / TalkingOff / InVehicle の閾値はティック数依存で、ティックを飛ばすと止まる位置が変わる

### 6.2 `Engine:Heartbeat`（0.5 s の Cron）
質量解決・物理有効化の担当（ネイティブ停止ウォッチドッグはフォールバック削除とともに消えた）。

### 6.3 オートパイロットの障害物回避（次の対象）
**32 本 × 20 Hz = 640 レイキャスト/秒**が現在最大の出費。
方針案: DLL にバッチレイを 1 本追加し、32 回のスクリプト invoke を 1 回の native invoke にまとめる
（Lua の回避ロジックは無変更）。回避ロジックごと DLL へ移す案は Lua のレイキャストを 0 にできるが、
停止距離ブレーキと A* との結合の再実装が必要で回帰リスクが中〜大。

### 6.4 A* 経路探索
ゲームスレッド上で実行中。別スレッド化は未着手。

---

## 7. ビルドとデプロイ

```
# DLL（別リポジトリ: /c/Users/sdxeq/Documents/div/red4ext/CP2077-RED4EXT-DAV）
MSBuild.exe RED4ext_DAV.sln -p:Configuration=Release -p:Platform=x64 -m -v:minimal
# 出力: build/release/bin/DriveAerialVehicle.dll
```

デプロイ先（**両方**に置く）:
- `<game>/red4ext/plugins/DriveAerialVehicle/DriveAerialVehicle.dll`
- `source/resources/red4ext/plugins/DriveAerialVehicle/DriveAerialVehicle.dll`

Lua は `source/resources/bin/x64/plugins/cyber_engine_tweaks/mods/DriveAerialVehicle/` と
`<game>/bin/x64/plugins/cyber_engine_tweaks/mods/DriveAerialVehicle/` の両方。
改行は CRLF。`Data/user_setting_v3.json` はゲーム側に上書きしない。

---

## 8. トラブルシュート

red4ext のログに出る行:

| 行 | 意味 |
|---|---|
| `DAV dbg: game state OnUpdate live (tid=..., physics tid=...)` | ゲームスレッド鈎が生きている。tid が物理スレッドと**別**であること |
| `DAV dbg: ground ray ready (ok) params=5 filter=16 m1=0 m2=8 out=48 hit_z=8` | DLL 発レイキャストの署名解析に成功 |
| `DAV dbg: ground ray off (<理由>)` | 署名が読み解けずレイキャスト無効。`why` が読み違えた箇所を指す |
| `DAV dbg: FindEntityByID params=N ret=...` | エンティティ解決に使っているスクリプト関数の署名 |

診断プローブ（`init.lua`）: `is_debug_probe_hook_tick`（鈎のレート）、`is_debug_probe_yaw`（旋回）、
`is_debug_probe_avoid`（停止距離ブレーキ）。いずれも測定済みで現在は `false`。

---

## 9. コミット履歴

### cp-av（Lua / mod）
| commit | 内容 |
|---|---|
| `3706269` | 未搭乗の速度保持を DLL フックへ、変化時だけ push |
| `1fbcd2b` | メニューゲートをイベント駆動に、フレーム毎アロケーション廃止 |
| `a62ecc0` | `Engine:Update` 削除。状態変化だけでモードを決める |
| `29082a2` | 前項の回帰修正（メニューでネイティブ経路が壊れていた） |
| `e0a5591` | 障害物マップ欠落を放置しない／デプロイ手順 |
| `4259b6f` | push のデッドバンドを「DLL が実際に保持する値」基準に |
| `9877e38` | （revert 済み）巡航ヨーのゲート置換 |
| `bcf756a` | 離陸旋回の度数/rad/s 誤り修正 |
| `ea8627d` | 停止距離ブレーキ |
| `b148866` | 未搭乗ホバーの DLL 化（mode 4） |
| `f8e5143` | 入力コールバックから直接 drain |
| `4de051d` | 地面と高度を DLL から読む |
| `fc4a6cb` | 帰還を上昇ランプに変更 |
| `032b4fe` | DLL の地面クエリに必要な値を渡す |
| `2fe21ec` | プローブ OFF、死んだコード削除 |

### DLL リポジトリ
| commit | 内容 |
|---|---|
| `5f4566c` | mode 4（ネイティブホバー）＋ `SetIdleHoverParams` |
| `dda6dd5` | ゲームステートで地面・接地状態を公開 |
| `85739ec` | ゲーム自前のクエリ系で地面レイキャスト |
| `08ffd73` | 恒久失敗した署名解析を打ち切り |
