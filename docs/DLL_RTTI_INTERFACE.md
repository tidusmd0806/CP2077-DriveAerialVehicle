# DLL の RTTI インターフェイス一覧

最終更新: 2026-10-17

RED4ext DLL（`DriveAerialVehicle.dll`）が Lua に公開しているネイティブ関数と、
DLL がゲーム側 RTTI を逆に使う箇所を全部まとめる。引数の受け渡し規約とスレッドモデルもここ。

---

## 1. 全体図

```
┌────────────────────────── CET / Lua ──────────────────────────┐
│  core.lua ─ event.lua ─ engine.lua ─ hud.lua ─ av.lua ...     │
│        │                                        ▲             │
│        │ FlyAVSystem.new():SetXxx(...)          │ Observe     │
│        │ （ネイティブ関数呼び出し＝RTTI 越し）    │             │
└────────┼────────────────────────────────────────┼─────────────┘
         ▼                                        │
┌────────────────────────── DLL ──────────────────┼─────────────┐
│  ① Lua→DLL: FlyAVSystem クラスにネイティブ関数 34 本を RTTI 登録 │
│     （状態は atomic / ダブルバッファ slot に書き込むだけ）      │
│                                                                │
│  ② 物理スレッド: vehiclePhysicsInsert1 フック                  │
│     mode 1/2/3/4 を毎物理ティック適用（flight model / hover）  │
│                                                                │
│  ③ ゲームスレッド: GameState OnUpdate（毎フレーム）            │
│     MonitorTick（高さ/距離/乗り込み閾値） SoundEdgeTick  ...    │
│         │                                                      │
│  ④ DLL→Lua 通知: gameActionEvent を作って puppet に QueueEvent │
└─────────┼──────────────────────────────────────┼─────────────┘
          ▼                                      │
┌────────────────────────── ゲーム RTTI ─────────┴─────────────┐
│  cpPlayerSystem::GetPlayer / entEntity::QueueEvent           │
│  gameISpatialQueriesSystem::SyncRaycastByQueryFilter         │
│  FindEntityByID / GetWorldPosition / SetLocalOrientation     │
│                    │                                         │
│  ActionEvent 配信 → REDscript cb（OnDAVMonitorEvent /        │
│  OnDAVSoundEvent）→ CET Observe → Lua ハンドラ               │
└──────────────────────────────────────────────────────────────┘
```

Lua→DLL は**呼び出しWhenever 状態を渡すだけ**（push-on-change）。DLL→Lua は
**閾値またぎ・音エッジのみ**（poll 無し）。両方向とも RTTI 経由で、共有メモリ直読みは無い。

---

## 2. Lua → DLL（`FlyAVSystem` に登録されたネイティブ関数）

すべて `FlyAVSystem.new():関数(...)` で呼ぶ。**ref 型引数は禁止**（CET の
マシャリングが壊れる。`Float` / `Int32` / `Vector3` / `Vector4` / `String` のみ）。

### 2.1 車両バインド・物理状態

| 関数 | 引数 | 戻り | 内容 |
|---|---|---|---|
| `SetVehicle` | `hash: Int64` | 0/1 | 対象車両エンティティの ID ハッシュ。0 で解除（despawn 時に必須） |
| `GetMass` | - | Float | 車両質量（物理データ解決済みなら） |
| `HasGravity` | - | Bool | 車両の重力フラグ（`unk1B0`） |
| `EnableGravity` | `on: Bool` | 0/1 | 重力 ON/OFF 要求（物理フックが毎ティック反映） |
| `EnableOriginalPhysics` | `on: Bool` | 0/1 | ゲーム本来の物理パスを戻す（着陸・ブロッキング時） |
| `GetPhysicsState` | - | Float | 物理状態 enum（未解決時 -1） |
| `UnsetPhysicsState` | - | -1/1 | 物理状態リセット |
| `IsOnGround` | - | Bool | 接地フラグ（DLL が接地エッジで学習） |
| `GetNativeTickCount` | - | Float | 物理フックが一度でも走ったかの判定用カウンタ |

### 2.2 飛行制御（mode は `SetFlightControl` の 1 文字目）

| 関数 | 引数 | 内容 |
|---|---|---|
| `SetFlightControl` | `mode: Int32, vel: Vector3, ang: Vector3, gain: Float` | **mode 0=off / 1=AddForce / 2=速度保持 / 3=flight model / 4=未搭乗ホバー**。ダブルバッファ `g_fc_buf` に書いて idx スワップ |
| `SetFlightModel` | `V4 ×10` | flight model の状態: `v1=(flight_mode, has_gravity, dt_scale, ncmd)`, `v2=(reset, act1..3)`, `v3..v5=(act4..6, val1..6)`, `v6=姿勢`, `v7=エンティティクォータニオン`。**搭乗時に必ず呼ぶ**（flight_mode がここだけで伝わる） |
| `SetFlightParams` / `2` / `3` | `V4 ×3 / ×3 / ×1` | flight model のチューニング値（AV 用・ヘリ用・姿勢境界）。順序は `FlightParams` 構造体と一致させる |
| `SetIdleHoverParams` | `V4 ×4`（17 ゲイン + valid） | mode 4 のホバー調整器ゲイン。`ground_z` は DLL 公開値で上書きされる |
| `SetNativeCommand` | `id: Int32, value: Float` | 入力のエッジ 1 本。`id` は `Def.ActionList` 値（内部 idx は +1）。`id=0` で全消去、`value=0` で単独解除 |
| `SetFlightFlags` | `bits: Int32` | 自動 mode 再確言のゲート: **bit0=搭乗 / bit1=オートパイロット / bit2=ヘリモード**（bit2 立ったら mode 2→3 再確言をスキップ） |

### 2.3 旧物理ラッパー（Lua 駆動時代の残骸。現役は `GetVelocity` あたり）

| 関数 | 引数 → 戻り |
|---|---|
| `AddVelocity` / `ChangeVelocity` | `vel: Vector3, ang: Vector3[, switchIndex]` → 0/1 |
| `AddForce` / `ChangeForce` | `force: Vector3, torque: Vector3[, switchIndex]` → 0/1 |
| `GetVelocity` / `GetAngularVelocity` / `GetForce` / `GetTorque` | → `Vector3`（物理データ直読み） |

### 2.4 閾値モニタ・地面

| 関数 | 引数 | 内容 |
|---|---|---|
| `SetThresholds` | `height, dist, radius, keepalive: Float, mask: Int32, entry_off: Vector4` | モニタの閾値と mask（1=高さ / 2=距離 / 4=乗り込み）。`entry_off` はドアのローカルオフセット（エンティティクォータニオンで回転して使用） |
| `SetLandingVFX` | `en: Float, offset: Vector4` | VFX 有効フラグ（en≠0 の間だけ `dav_evt_height_tick` を送る。offset は現在未使用） |
| `SetGroundQuery` | `offset, distance: Float, mask1, mask2: Int64` | DLL 発レイキャストの検索範囲と衝突マスク。**Lua の push が `fly_av_system` 生成より早いと破棄される**ため Engine が保持して再送する |
| `SetGroundReference` | `z: Float` | 地面 Z の初期 seed（以降は DLL の接地学習が更新） |
| `GetGroundInfo` | → `Vector4(ground_z, av_z, on_ground, valid)` | Lua 側の高度・接地読み（Waiting の poll 削減用） |

### 2.5 スラスター・音・RPM

| 関数 | 引数 | 内容 |
|---|---|---|
| `SetThrusterSetup` | `en, step, restore, max_angle: Float, axis: Int32, engine_names, fx_names: String` | スイングアニメの有効化・速度（deg/s）・回転軸（0=X+..5=Z-）・対象コンポーネント名（`,` 区切り小文字）。DLL は**エンティティのメモリ walk**（`+0x70+0x30` FlatArray、CName ハッシュ比較）で探す |
| `SetThrusterCommand` | `fwd, back: Float` | 前後入力のエッジ（スイング目標角の符号） |
| `SetSoundParams` | `grace: Float, accel_ids, thr_ids: String` | 音レイヤーの grace tick とイベント名（`,` 区切り）。`SoundEdgeTick` が保持入力のエッジで音を発火 |
| `GetNativeRPM` | → Float | flight model の RPM 積分値（HUD 表示用） |

---

## 3. DLL → ゲーム RTTI（DLL が呼び出す側）

| ゲーム側 | 使い道 | 備考 |
|---|---|---|
| `IGameInstance::GetSystem(cpPlayerSystem)` → `GetPlayer()` | puppet 解決（QueueEvent の宛先） | **Handle\<T\> は 0x10 バイト**。8 バイト slot に受けるとスタック破壊 |
| `entEntity::QueueEvent(evt)` | `gameActionEvent` を puppet に配信 → Lua 通知 | 引数は handle slot（`&slot` 形式） |
| `gameActionEvent`（RTTI クラス） | `CClass::CreateInstance` + RTTI プロパティ `timeToLive` / `eventAction` を `CProperty::SetValue`（親チェーン探索）で設定 | Lua の `ActionEvent.new()` と同じもの。**timeToLive は高さペイロードに流用**（unknown action は無視する） |
| `IGameInstance::GetSystem(gameISpatialQueriesSystem)` → `SyncRaycastByQueryFilter` | 地面レイキャスト（モニタが毎フレーム） | **`GetSpatialQueriesSystem` というグローバル関数は存在しない**。シグネチャは RTTI から解決（`Bool` 2 つは実引数。`isOut` 判定、`position`+8 で z） |
| `FindEntityByID`（グローバル） | 車両エンティティ解決（ハッシュ→handle） | 物理フック内で SEH ガード |
| puppet の `GetWorldPosition` | 距離モニタ（`dav_evt_dist_*`） | |
| `SetLocalOrientation`（コンポーネント） | スラスター角度書き込み | 基底クラス（`entComponent` 等）にしかないため**基底チェーンを辿って**取得 |
| `entEntity + 0x70 → componentsStorage(+0x30/+0x38)` | **メモリ walk** でコンポーネントを CName ハッシュ検索 | `FindComponentByName` は DLL から呼ぶとクラッシュ（SEH でも守れない）ため禁止。Lua 側では可 |
| `vehiclePhysicsInsert1` フック | 物理スレッド。mode 適用・接地学習・重力強制 | 毎物理ティック |
| GameState `OnUpdate`（Running） | ゲームスレッド。`MonitorTick` / `SoundEdgeTick` / `ThrusterTick` / 地面レイ。**必ず false を返さないと 1 回で止まる** | |

---

## 4. DLL → Lua 通知（イベントの戻り経路）

```
DLL: QueueDavEvent(className, name, ttl)
  └ gameActionEvent{ eventAction=CName(name), timeToLive=ttl } を CreateInstance
     └ puppet:QueueEvent(evt)
        └ ゲームの ActionEvent 配信
           ├ REDscript cb OnDAVSoundEvent(event)   → CET Observe → Lua 音ハンドラ
           └ REDscript cb OnDAVMonitorEvent(event) → CET Observe → Event:OnDavThresholdEvent(name, ttl)
              （cb 本体の n"dav_evt_*" 比較がロード時に CName を登録するしかけ。
                Lua の CName.new() は登録しないので .value が空文字列になる）
```

| イベント名 | 発火条件 | timeToLive |
|---|---|---|
| `dav_evt_height_low` / `dav_evt_height_high` | 高さ閾値のまたぎ（ヒステリシス ±0.5 m） | **実測高さ（m）** |
| `dav_evt_height_tick` | 警告ゾーン内のみ毎フレーム | **実測高さ（m）** |
| `dav_evt_dist_near` / `dav_evt_dist_far` | プレイヤー距離のまたぎ（±2 m） | 1.5 |
| `dav_evt_entry_in` / `out` | 乗り込みエリアのまたぎ。in は keepalive（既定 1 s）で再発火 | 1.5 |
| `dav_av_accel_start/stop`、`dav_heli_accel_start/stop`、`dav_heli_thruster_start/stop` | 保持入力のエッジ（`SoundEdgeTick`。搭乗・オートパイロット フラグでゲート） | 1.5 |

---

## 5. スレッドと受け渡しの規約

| 領域 | スレッド | 内容 |
|---|---|---|
| ネイティブ関数 | Lua の呼び出し元（ゲームスレッド or CET コンテキスト） | 引数を atomic / slot に書くだけ。ゲーム API は呼ばない |
| 物理フック | 物理スレッド | `g_fc_buf` / `g_fm_buf` / `g_idle_buf` を **idx スワップのダブルバッファ**で読む |
| GameState OnUpdate | ゲームスレッド | レイキャスト・puppet 解決・QueueEvent などワールドを触る仕事は全部こちら |

- **ref 型（`entIComponent` / `IScriptable` / `ScriptRef`）は CET を一切通せない**（全パターンマシャリング失敗）。境界を跨ぐのは単純型のみ
- **`Handle<T>` は 0x10 バイト**。戻り値・引数とも実体で受ける
- CName は REDscript の `n"..."` でしか登録されない
- DLL から `FindComponentByName` 禁止（メモリ walk で代替）

### 終了時ハング対策（quit-to-desktop）

**確定した犯人: ワールド破棄中にゲームスレッドから発行する同期レイトレース
（`SyncRaycastByQueryFilter`）**。破棄中の物理シーンへの同期クエリはデッドロックする。
SEH は例外にしか効かず、待ち（ロック）には無効。機能二分探索で実証:

| ビルド | レイトレース | ForceEnablePhysics | 結果 |
|---|---|---|---|
| A | OFF | OFF | 正常終了 |
| B | ON | OFF | **ハング** |

→ 対策は**物理活性ゲート**（DLL 完結、Lua 不要）:

- `g_phys_alive` = 「物理フックが直近 15 フレーム以内に tick したか」
- レイトレース（MonitorTick の高度計・ホバー用地面クエリ）は **物理が実際にステッピング中のみ**発行
- 終了フローは必ず「ポーズ→物理停止」を経由して detach まで約 4 秒あるので、危険窓より十分に早く停止
- ポーズ中（物理停止）にクエリするのは安全（メニューで分単位で固まらない実証済み）。危険なのは「**破棄中**のシーン」

補助レイヤ（多層防御）:

| 層 | 場所 | やること |
|---|---|---|
| 宣言的終了 | `DavGameState_OnExit` | `g_shutting_down` を立て、車両ハンドル・hash・モニタ mask を捨てる。以降 OnUpdate は即 return |
| ワールド離脱 | `SetWorldGone` ネイティブ（手動/デバッグ用） | `g_world_gone`。OnUpdate 全体を停止。※自動配線は無し（Lua Observe ブリッジは真因判明に伴い撤去。`PlayerPuppet.OnAttach` は存在せず、`OnDetach` のみの再武装はセーブロードで再武装不能になるため不採用) |
| 読み取りガード | `VehicleBodyAlive()` | エンティティの `physicsData` を SEH で 1 回読む。**全ネイティブ getter と OnUpdate/MonitorTick はこれを通ってから本体を触る** |
| レートガード | `MonitorTick` | `dt < 1/240 s`（＝終了ムービーの非スロットルド実行）では何もしない |
| イベント停止 | `QueueDavEvent` | `g_shutting_down` 以降はイベント投入を停止（遅延ディスパッチでのクラッシュ防止） |

**落とし穴**: CET v1.37 に `GameObserver`/`RegisterForGameReload` API は**存在しない**
（旧 API、バイナリ・ソースで消滅確認）。ワールド離脱の Lua 検知は `Observe("PlayerPuppet", "OnDetach")`
で行う（CET 自身がこのフックを internal hook している）。CET 側 `onShutdown` でも `SetVehicle(0)` を
pcall して返す（CET リロード時の保険）。物理スレッド（フック）はエンティティ自身のステップ内で
動くのでこの問題なし（hash 不一致で素通り）。
