# 性能解析：Engine の red4ext 往復 — 1 tick 8 回を 2 回に

対象: DriveAerialVehicle v3.3.x / DAV red4ext plugin v3.1.1 → **v3.2.0**
関連: `docs/PERF_ANALYSIS_hooks.md`（onUpdate 漏斗の内側）
計測ツール: `tools/interop_tick_audit.py`（静的な遷移回数監査）
回帰テスト: `tests/run_engine_interop_test.py`

---

## 0. 結論

**制御ループは 1 tick に 8 回 plugin を往復していた。うち 4 回は
読み捨てか重複だった。**

| 経路（InVehicle / AddForce） | 修正前 | 修正後 |
|---|---|---|
| `Engine:Update` — 物理状態のpoll | 1 | 0（snapshot） |
| `Engine:Update` — 角速度の読み | 2（うち 1 は読み捨て） | 0（C++ 内で完結） |
| `Engine:Update` — force/torque 書込 | 1 | 1 |
| `Engine:Run` — 速度の読み | 2（うち 1 は読み捨て） | 0（snapshot） |
| `Engine:Run` — 重力判定 | 1 | 0（snapshot） |
| `AV:GetCurrentSpeed` | 2 | 0（snapshot） |
| **計** | **9** | **2** |

`tools/interop_tick_audit.py` の FlyAVSys 列で追える:

| situation | 修正前 / tick | 修正後 / tick |
|---|---|---|
| B Waiting | 4 | 2 |
| C InVehicle（手動） | 8 | 2 |
| D InVehicle + autopilot | 8 | 2 |

100 Hz なので **C なら 600 回/秒** の往復が消えている。
加えて `AV:GetForward/GetRight/GetUp` がフレームキャッシュになり、
REDscript 側の entity 呼び出しも 1 tick に 2〜3 回減った。

---

## 1. 何が起きていたか

修正前の `Engine:Update`（AddForce 分岐）:

```lua
if self:GetPhysicsState() ~= 0 then            -- ① 読む
    self:UnsetPhysicsState()
end
...
elseif self.engine_control_type == Def.EngineControlType.AddForce then
    local direction_velocity = self:GetDirectionVelocity()      -- Lua 内
    local angular_velocity = self:GetAngularVelocity()          -- Lua 内
    local _, actual_angular_velocity = self:GetDirectionAndAngularVelocity()
    --                                ^^^^ ② GetVelocity() の結果を捨てている
    --                                     それでも 1 回往復している
    local angular_velocity_diff = Vector3.new(target - actual)  -- 引き算 3 回
    self.force  = Vector3.new(direction_velocity * mass)
    self.torque = Vector3.new(angular_velocity_diff * torque_gain)
    self:AddForce(self.force, self.torque)      -- ③ 書く
```

`Engine:Run` 側:

```lua
local vel_vec, _ = self:GetDirectionAndAngularVelocity()
--                 ^^^^^ 角速度を捨てている。GetVelocity() 1 回で済む
...
if self.flight_mode == Def.FlightMode.Helicopter or self:HasGravity() then
--                                               ^^^^ ④ 重力は Lua 側で
--                                                    設定している値なのに読む
```

`GetDirectionAndAngularVelocity()` は `GetVelocity()` と
`GetAngularVelocity()` を**両方**返す関数で、呼び出し側は毎回片方しか
使っていなかった。REDscript の native は 1 戻り値なので、2 値を取りに
いく = 2 回往復する。使わない 1 値のためだけに。

**1 tick の内訳（InVehicle / AddForce）**

```
Engine:Update   GetPhysicsState            1
                GetVelocity        (捨て)  1
                GetAngularVelocity        1
                AddForce                  1
Engine:Run      GetVelocity             1
                GetAngularVelocity (捨て) 1
                HasGravity              1
AV:GetCurrentSpeed  GetVelocity         1
                    GetAngularVelocity  1
                                        ───
                                        9
```

`GetPhysicsState` に至っては、安定飛行中は常に 0 を返す値を
**毎 tick 読みに行っていた**。0 なら何もしないのに。

---

## 2. 設計方針

「Lua 側で賢くする」では削れない。往復の回数は呼び出し構造で決まる。
なので **plugin 側に 2 つの native を足して、読み書きのサイクルそのものを
畳む**。

### 2.1 `GetFlightState() -> Vector4` — 決めるために必要な全部を 1 回で

| | 内容 |
|---|---|
| `x, y, z` | `physicsData->velocity` |
| `w` | フラグ bitfield（下記） |

| bit | 意味 |
|---|---|
| 0 | `isOnGround` |
| 1 | 重力 ON（`physicsData->unk1B0`） |
| 2 | 物理無効（`physicsState != Enabled`）→ 再有効化が必要 |
| 3 | ハンドル有効（`g_fly_vehicle` が lock できている） |

REDscript の native は戻り値が 1 個しか持てず、この SDK バージョンには
新しい struct 型を登録する手段がない（`CStruct` が未公開）。なので
**boolean 4 個を `w` に packed** している。`w` は float ではなく
整数 bitfield と扱う。展開は `Engine:RefreshSnapshot` の中だけ。

### 2.2 `AddForceTracked(force, targetAngular, torqueGain) -> Vector3`

追従トルクを plugin 内で閉じる。

```cpp
physicsData->force += force;
applied = (targetAngular - physicsData->angularVelocity) * torqueGain;
physicsData->torque += applied;
return applied;   // Lua 側の self.torque はそのまま有効
```

Lua は「引き算のために 1 回往復する」のをやめられる。
戻り値として適用トルクを返すので `engine_obj.torque` の意味は変わらない
（デバッグ表示もそのまま）。

さらに **書き込み時に物理状態を自己修復**する。Lua 側の snapshot は
フレームの先頭で取るので、もしフレーム途中で stale になっても、
無効な body に force を入れ続けることがない。

### 2.3 Lua 側: フレーム単位 snapshot

```lua
Engine:RefreshSnapshot()   -- DAV.frame_seq でガード、1 フレーム 1 回だけ読む
Engine:GetVelocity()       ─┐
Engine:IsOnGround()         ├ snapshot から返す（plugin を跨がない）
Engine:HasGravity()         │
Engine:Update() の物理判定 ─┘
```

`AV:GetEulerAngles` と同じフレームカウンタ契約。返すテーブルは共有なので
**読み専用**。

`DAV.frame_seq` が無い環境（テストハーネス等）ではキャッシュせず毎回読む。
鮮度が判断できないものを無限に cache しない、という既存と同じ防御。

### 2.4 1 tick の内訳（修正後）

```
Engine:Run      GetVelocity            0   snapshot
Engine:Update   ReadSnapshot           1   GetFlightState
                AddForceTracked        1   読み込み込みの書き込み
                                        ───
                                        2
```

`Engine:Run` は Cron 側（`Core:ControlTick` → `AV:Operate`）で、
`Engine:Update` は `init.lua` の `onUpdate` で走る。同じフレーム内なので
`Run` 側の最初の要求が読み、`Update` はそれに乗る。
間に物理ステップは入らないので、**鮮度も落ちていない**。

---

## 3. 削らなかったもの

### 3.1 「読み 1 回 + 書き 1 回」を「合計 1 回」にはしなかった

書き込み call が次の tick 用の状態も返せば 1 回で済む。が、その値は
**物理ステップ前**の値になる。次の tick で使ったとき、制御則は
物理 1 ステップぶんの遅れを背負う。

現状の制御則は 100 Hz の rate-target + boundary layer で、tick 長に合わせて
調整されている（`Engine:RestoreRate` / `restore_boundary_deg`）。そこに
さらに 1 フレームぶんの位相遅れを足すと発振しかねない。
**1 往復のために制御特性を賭ける価値はない**と判断した。

### 3.2 `AV:GetPosition` はフレームキャッシュしなかった

`navigation.lua` の `check_collision_at_point` が返り値を**破壊的に
オフセット**している:

```lua
local current_position = self.av_obj:GetPosition()
current_position.x = current_position.x + right_vec.x * offset_right + ...
```

共有テーブルを返すと、2 回目の呼び出しがオフセット済みの位置から始まって
衝突判定が壊れる。`GetForward/GetRight/GetUp` は全呼び出し箇所
（engine.lua 5 箇所・navigation.lua 2 箇所）を読み取り専用と確認できたので
キャッシュした。`GetPosition` はしていない。

---

## 4. 変更ファイル

### red4ext 側（`RED4ext_DAV/src/Main.cpp`）

| 追加 | 内容 |
|---|---|
| `GetFlightState` | 速度 + 4 boolean を Vector4 で返す |
| `AddForceTracked` | force 加算 + 追従トルク計算 + 物理自己修復 |
| `PostRegisterGetFlightState` / `PostRegisterAddForceTracked` | 登録 |
| `DAVStateFlags` | bitfield 定義（Lua 側と同期させること） |
| version | 3.1.1 → **3.2.0** |

既存 native（`AddForce` / `ChangeVelocity` / `GetVelocity` / 他）は
**そのまま残している**。後方互換。

### Lua 側

| ファイル | 内容 |
|---|---|
| `Modules/engine.lua` | `RefreshSnapshot` / `ReadSnapshot` / `InvalidateSnapshot`、`GetVelocity` `IsOnGround` `HasGravity` を snapshot 経由に、`Update` の AddForce 分岐を `AddForceTracked` に |
| `Modules/av.lua` | `GetForward/GetRight/GetUp` をフレームキャッシュ化、`GetCurrentSpeed` を `GetVelocity` に |
| `Modules/navigation.lua` | 角速度を読み捨てていた 1 箇所を `GetVelocity` に |

`Engine:GetDirectionAndAngularVelocity()` は残してあるが、hot path から
呼ばれなくなったため doc に「uncached: 2 回往復する」と明記した。

---

## 5. デプロイ

**plugin と Mod は必ず対で更新すること。** Lua 側は
`FlyAVSystem:GetFlightState` / `AddForceTracked` を前提にしている。

```
RED4ext_DAV/build/release/bin/DriveAerialVehicle.dll
  → <game>/bin/x64/plugins/DriveAerialVehicle.dll
```

旧 DLL + 新 Mod の組み合わせは `GetFlightState` が無く落ちる。
新 DLL + 旧 Mod は動作する（既存 native は消していない）。

ビルド:

```
cd RED4ext_DAV/src
MSBuild.exe RED4ext_DAV.vcxproj -p:Configuration=Release -p:Platform=x64
```

`Release_FlyTank` 構成でも同じ native が入る（`FLY_TANK_MOD` はクラス名の
切替のみで、追加した 2 native は共通）。

---

## 6. 検証

```
python tools/check_lua_syntax.py            # 50 files, 0 problems
python tests/run_engine_interop_test.py     # 38 passed, 0 failed
python tests/run_situation_cost_test.py     # 54 passed, 0 failed
python tests/run_enter_exit_cost_test.py    # 52 passed, 0 failed
python tests/run_entity_cache_test.py       # 40 passed, 0 failed（5b/5c 追加）
python tests/run_meter_cadence_test.py      # 42 passed, 0 failed
python tests/run_onaction_cost_test.py      # 40 passed, 0 failed
python tests/run_axis_proxy_cost_test.py    # 31 passed, 0 failed
python tests/run_timescale_landing_test.py  # 188 passed, 0 failed
```

`engine_interop_test.lua` が担保しているのは 2 点:

1. **コスト** — 1 tick の plugin 往復が 2 回であること。
   物理状態を要求する箇所がどれだけ増えても増えないこと
   （節 8: 6 消費者 + 書き込んでも 2 回のまま）
2. **等価性** — plugin に移したトルクが修正前の Lua 計算と一致すること。
   言語境界を跨いで移動したからといって、計算式を変えていい理由にはならない。
   修正前分岐を書写して 3 成分すべて突き合わせている（節 4）

`run_situation_cost_test.py` の方では、修正前が 400 遷移していた
menu-open Waiting が 0 になること、および situation 間の順序が崩れていない
ことを確認している。

---

## 7. 残っているもの

`interop_tick_audit.py` が示す通り、situation C で依然 23 遷移/tick あり、
その内訳は:

| 分類 | /tick | 備考 |
|---|---|---|
| `entity:` | 11 | `GetPosition`（未キャッシュ、§3.2 参照）が 3、他 |
| `SyncRaycast` | 2 | 地面探知。`Navigation:GetHeight` のフレームキャッシュで further 削減余地 |
| `REDscript` | 3 | `Game.*` 呼び出し |
| `widget` | 4 | HUD 書き込み |
| `FlyAVSys` | 2 | **これ以上は §3.1 の理由で削らない** |

red4ext 側はこれで底を打った。次に効くのは
`AV:GetPosition` の呼び出し側破壊的書き込みを直してキャッシュに乗せること。
