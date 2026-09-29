# 性能解析：`init.lua:441` が太って見える現象の分解

対象: DriveAerialVehicle v3.3.0
計測: 静的解析（`tools/interop_tick_audit.py`）＋ ソース読解
関連: `docs/PERFORMANCE_FIX_PLAN.md`（fix (1)〜(15) までの履歴）

---

## 0. 結論

**`init.lua:441` は犯人ではなく「漏斗（funnel）」。**

```lua
441| registerForEvent('onUpdate', function(delta)
442|     Cron.Update(delta)                    -- 全 Cron タイマーがここで毎フレーム走る
443|     if DAV.core_obj ~= nil and DAV.core_obj.av_obj ~= nil
             and DAV.core_obj.av_obj.engine_obj ~= nil then
444|         DAV.core_obj.av_obj.engine_obj:Update(delta)
445|     end
446| end)
```

CET の `onUpdate` はこの Mod の**唯一のフレーム入口**なので、行ベースのプロファイラは
Mod の 1 フレーム分の Lua 仕事を全部この 1 行に付けます。
「init.lua:441 が重い」は観測として正しくても、原因の所在地ではない。

本当の中身は **Lua → C#（REDscript）の言語境界を跨ぐ回数**です。
跨ぎ 1 回は Lua 演算の数百〜数千倍する上に、`Vector4.new` 等の managed
アロケーションを随伴するので GC にも効きます。

---

## 1. なぜ「召喚前は軽く、召喚後に一気に重い」のか

`DAV.time_resolution = 0.01`（=100 Hz）のループは **`Core:Init()` から常時走っています**。
召喚前も毎 tick 呼ばれている。なのに軽いのは、**全部の手が早期 return で止まる**から。

| 経路 | 召喚前 | 召喚後 |
|---|---|---|
| `Engine:Update` (engine.lua:77) | `if not self.is_finished_init then return end` で即 return。<br>`engine_obj` は `AV:New` で作られるので nil ガードは抜けるが、ここで止まる | `Engine:Init` 済み → 全パス実行 |
| `Core:OperateAerialVehicle` (core.lua:1109) | `IsInVehicle()` でも `IsWaiting()` でもない → 何もしない | 毎 tick `AV:Operate` |
| `Event:CheckAllEvents` (event.lua:271) | `Normal` 分岐 = `UpdateGarageInfo` **のみ**（1 Hz にスロットル済み） | `Waiting`=7 チェック / `InVehicle`=**10 チェック** を毎 tick |

**召喚は「タイマーを増やす」のではなく「既存 100 Hz タイマーの中身を起こす」。**
これが現象の核心。

---

## 2. 静的監査の実測値

`tools/interop_tick_audit.py`（本解析用に追加）

```
A  Normal（未召喚）              ~1 遷移/秒      実質アイドル
B  Waiting（車両地上・外）     4,500 遷移/秒
C  InVehicle（手動飛行）       4,900 遷移/秒
D  InVehicle + autopilot       7,100 遷移/秒
```

内訳（D）:

```
SyncRaycast=34, REDscript=12, FlyAVSys=8, entity:=7, widget=7,
player:=1, inkTextRef=1, GameSettings=1
```

---

## 3. コスト源の分解

### ① エンティティハンドルが一切キャッシュされていない（最大項）

`av.lua` に **`Game.FindEntityByID` が 29 箇所**。全 accessor が毎回ハンドルを
解決し直している。

```lua
function AV:IsPlayerIn()          -- av.lua:151
    local entity = Game.FindEntityByID(self.entity_id)   -- 跨ぎ 1
    return entity:IsPlayerMounted()                    -- 跨ぎ 2
end
```

`GetPosition / GetForward / GetRight / GetUp / GetQuaternion / GetEulerAngles /
IsEngineOn / IsDestroyed / IsDespawned / GetDoorState / MoveThruster` … 全部この形。

**1 accessor 2〜3 跨ぎ × 毎 tick × 100 Hz。**

`GetEulerAngles` は `FindEntityByID + GetWorldOrientation + ToEulerAngles` で 3 跨ぎ、
しかも `CalculateAVMode` と `Engine:Run` の**両方**で毎 tick 呼ばれる。

`entity_id` の代入箇所は `AV:Spawn`（av.lua:360）と `AV:Despawn`（av.lua:425）の
**2 箇所だけ**。＝キャッシュの無効化ポイントを特定するのは容易。

### ② `CheckHeight` が毎 tick 同期レイキャストを撃つ

```
Event:CheckHeight (event.lua:569)
  -> Navigation:GetHeight (navigation.lua:3425)
    -> AV:GetPosition()                       2 跨ぎ
    -> AV:GetGroundPosition (av.lua:276)
      -> AV:GetPosition()                    2 跨ぎ（重複）
      -> SyncRaycastByQueryFilter (av.lua:286)   物理同期レイキャスト
```

**100 回/秒の同期シーン照会**。しかも `GetPosition` が二重解決。

### ③ autopilot の local avoidance = 32 レイキャスト/tick

```lua
Navigation:CollectSphericalRepulsion (navigation.lua:5601)
    for _, dir in ipairs(self.local_ray_angles) do   -- Fibonacci sphere N=32
        SyncRaycastByQueryFilter(...)                -- navigation.lua:5620
```

`ComputeLocalAvoidanceDirection` は local 回避フェーズの**毎 tick** でこれを呼ぶ
→ **3,200 同期レイキャスト/秒**。
スタック脱出の `HasSphericalCollision`（navigation.lua:5648）はさらに 32 本。
D が C より 2,200/s 多いのはほぼこれ。

### ④ 同じ判定を 1 tick で 2 回やっている

```lua
-- Event:CheckInAV (event.lua:388)
if self.av_obj:IsPlayerIn() then ...        -- 跨ぎ 2

-- Core:OperateAerialVehicle (core.lua:1111)
if self.event_obj:IsInVehicle() ...        -- -> Event:IsInVehicle (event.lua:672)
                                          --    -> av_obj:IsPlayerIn() 跨ぎ 2
                                          --    （同一 tick で 2 回目）
```

fix(13) で C# 往復を避ける `IsInAVSituation()` を作ったのに、
`OperateAerialVehicle` は今も重い `IsInVehicle()` を使っている。

### ⑤ `Cron` が毎フレーム全タイマーを線形走査

`Cron.Update`（Cron.lua:151）は `#timers` を毎フレーム舐める。
`Cron.Halt`（Cron.lua:107）も線形探索で、**Update のループ内から呼ばれるので O(n)**。

100 Hz タイマーの内訳：av.lua 3 本 / core.lua 2 本 / navigation.lua 3 本。
held button ごとに 0.01s タイマーが増える（core.lua:811）ため、
キー長押し中に timer 配列が太る。

---

## 4. 副次所見：tick レートとフレームレートの不整合

性能とは別軸だが体感の不安定さにつながっている。

- `Cron.Update` は**フレーム毎**にしか各タイマーを起こせない（1 frame = 最大 1 fire）。
  → 30 fps では「100 Hz」タイマーが実際 30 Hz になり、`delta` も無視される固定増分なので
    **加速度・応答がフレームレートに依存して変わる**。
- 一方 `Engine:Update`（init.lua:444）は 100 Hz ではなく**フレームレート直結**で走る。
  → 144 fps では同じ force を 60 fps の 2.4 倍の頻度で適用する。

`Cron.Update(delta)` と `Engine:Update(delta)` が別レートを参照している設計になっている。

---

## 5. 優先度付き改善案

| 優先 | 対策 | 期待削減 | 状態 |
|---|---|---|---|
| **1** | **`AV` に entity ハンドルキャッシュ**。<br>フレーム単位で解決し全 accessor で共有。29 箇所の `FindEntityByID` を 1 回/frame に | 手動飛行 **−28.6%**、待機 **−33.3%** | **実装済み（§6）** |
| **2** | `GetHeight` を 1 フレームで 1 回だけ計算し共有。<br>`GetPosition` 二重解決の解消 + 地面レイキャストの間引き | レイキャスト **200/s → 60/s**、`GetWorldPosition` **400/s → 60/s** | **実装済み（§6B）** |
| **3** | `CollectSphericalRepulsion` の間引き。<br>既知セルは base image（RAM）から引くので、レイキャストは未知/境界近傍のみ | autopilot の 3,200/s を 1/4〜0 に | 未着手 |
| **4** | `OperateAerialVehicle` の `IsInVehicle()` → `IsInAVSituation()` | 200 跨ぎ/s | 未着手 |
| **5** | `Engine:Update` を Cron 経由（100 Hz 統一）で `delta` を実使用 | 挙動の安定化 | 未着手 |
| 6 | `Cron` のハッシュ化 or 停止済みタイマー即時除去 | 長押し時の走査コスト | 未着手 |

---

## 6. fix (1)：AV entity ハンドルキャッシュ（今回実装）

### 設計

`entity_id` の代入箇所が `AV:Spawn` / `AV:Despawn` の 2 箇所しかないため、
**フレーム単位キャッシュ**で安全に成立する。

```lua
-- AV:New
obj._entity       = nil   -- キャッシュした Game.FindEntityByID の結果
obj._entity_frame = -1    -- そのキャッシュが属するフレーム番号

-- AV:GetEntity()
function AV:GetEntity()
    if self.entity_id == nil then
        self._entity = nil
        return nil
    end
    local frame = DAV.frame_seq or -1
    if self._entity ~= nil and self._entity_frame == frame then
        return self._entity            -- 今フレームは解決済み
    end
    local entity = Game.FindEntityByID(self.entity_id)
    self._entity = entity
    self._entity_frame = frame
    return entity
end
```

`nil` は決してキャッシュしない（`_entity ~= nil` 条件で毎回再解決）。
よって spawn 直後「まだエンティティが生成されていない」期間の挙動は従来どおり。

### 更新タイミング

`init.lua` の `onUpdate` 先頭で `DAV.frame_seq` をインクリメントする。

```lua
registerForEvent('onUpdate', function(delta)
    DAV.frame_seq = (DAV.frame_seq or 0) + 1
    Cron.Update(delta)
    ...
end)
```

`onUpdate` はメニュー中も毎フレーム走るため、`tick_seq` が止まって
キャッシュが永久に古くなる、という事故が起きない。

### 無効化ポイント

| 箇所 | 処理 |
|---|---|
| `AV:Spawn`（`CreateEntity` 直後） | `_entity = nil`, `_entity_frame = -1` |
| `AV:Despawn`（`DeleteEntity` 後） | `_entity = nil`, `_entity_frame = -1` |
| `Core:Reset` | 新しい `AV:New` なのでキャッシュは空 |

### 変更した呼び出し箇所

`av.lua` の 29 箇所すべてを `self:GetEntity()` に置換。

```lua
-- 置換前
local entity = Game.FindEntityByID(self.entity_id)
-- 置換後
local entity = self:GetEntity()
```

特殊箇所 1 つ:

```lua
-- av.lua:557（置換前）— nil 参照の危険があった
local vehicle_ps = Game.FindEntityByID(self.entity_id):GetVehiclePS()
-- 置換後 — 直近フレームで non-nil を確認済みのハンドルを使う
local vehicle_ps = self:GetEntity():GetVehiclePS()
```

併べて `event.lua`（LTBF 互換 10 Hz パス）と `ui.lua` の
`Game.FindEntityByID(self.av_obj.entity_id)` も `self.av_obj:GetEntity()` に統一。

### 効果（`tools/interop_tick_audit.py` で再現可能）

`before` は「現在のソースの `self:GetEntity()` を全て `Game.FindEntityByID(self.entity_id)`
に戻したもの」。同じチェックアウトから再現できるので基準がコードから乖離しない。

```
situation                                        before   after f(1)    saved
A  Normal（未召喚）                                 1/s        1/s      0.0%
B  Waiting（車両地上・外）                        4,500/s    3,000/s    33.3%
C  InVehicle（手動飛行）                          4,900/s    3,500/s    28.6%
D  InVehicle + autopilot（local avoidance）       7,100/s    6,400/s     9.9%
```

| | 置換前 | 置換後 |
|---|---|---|
| `FindEntityByID` の回数 | accessor 呼び出し毎（InVehicle で 15 回/tick × 100 Hz = 1,500/s） | **1 回 / frame**（60 fps で 60/s） |
| 手動飛行の総 interop | 4,900/s | 3,500/s（**−28.6%**） |
| 鮮度 | 呼び出し毎に解決（＝フレーム内でも結果が食い得る） | フレーム 1 回。実効鮮度は従来と同等以上 |

`FindEntityByID` が消えるので、それに紐づく wrapped オブジェクト生成も消え、
GC プレッシャも下がる。

> D（autopilot）の相対削減が 9.9% と小さいのは、`CollectSphericalRepulsion` の
> 32 レイキャスト（3,200/s）が総量の半分を占めているため。
> そこを削るのが fix (3) の本命。

### 安全性の議論

- ** staleness（鮮度）**: 最悪でも 1 フレーム（60 fps で 16.7 ms）。
  従来も「同一フレーム内で accessor ごとに解決結果が食い得る」だけで、
  フレーム跨ぎの鮮度は従来と変わらない。
- **エンティティがゲーム側で消えた場合**: 次のフレームで `GetEntity` が
  `FindEntityByID` を再実行し `nil` を返す。`IsDespawned` / `CheckDespawn` は
  従来どおり 100 Hz で `nil` を検出する。
- **spawn 直後**: `nil` はキャッシュしないので、
  `AV:Spawn` の 0.1 秒ポーリング（av.lua:363）は従来どおり機能する。

### 検証

**新規テスト `tests/entity_cache_test.lua`（`python tests/run_entity_cache_test.py`）**
`Game.FindEntityByID` にカウンタを載せて実 `Modules/av.lua` を動かし、9 節すべて PASS:

| 節 | 検証内容 |
|---|---|
| 1 | `entity_id == nil` なら解決を一切しない |
| 2 | 同一フレーム内で 21 回呼んでも解決は 1 回 |
| 3 | フレームが進むと必ず再解決 |
| 4 | `nil` はキャッシュしない（消滅検知が鈍らない） |
| 5 | 10 個の accessor を同一フレームで呼んでも `FindEntityByID` は 1 回 |
| 6 | `InvalidateEntityCache()` で強制再解決、以降は再びキャッシュ |
| 7 | `Despawn` がハンドルを落とす |
| 8 | `Spawn` が旧ハンドルを落とす（新 entity で再解決） |
| 9 | `DAV.frame_seq` 欠落時に落ちない |

```
entity_cache_test: 30 passed, 0 failed
構文ゲート: 41 files, 0 problems
```

**既存テストについて（本変更とは無関係の既存環境ギャップ）**
`run_resident_cache_test.py` / `run_grid_integration_test.py` は
`Data/map`（legacy テキストマップ）を要求するが、このチェックアウトには存在しない
（`Data/map_bin` のみ）。変更を stash して実行しても**同一の理由で同じく失敗**する
ことを確認済み。本変更は navigation / 障害物マップコードに一切触れていない。

---

## 6B. fix (2)：地面計測（GetHeight）のフレーム単位共有（今回実装）

### 問題

`Navigation:GetHeight()` は同期ワールドレイキャストを撃つのに、
**呼び出し元ごとに 1 回**走っていた。しかも 1 回の呼び出しで
**車両位置を 2 回解決**している。

```lua
-- 修正前
function Navigation:GetHeight()
    return self.av_obj:GetPosition().z - self.av_obj:GetGroundPosition()
    --     ^^^^^^^^^^^^^^^^^^^^^^^^ 1 回目      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    --                                      中でさらに GetPosition() = 2 回目
end
```

1 tick の中に呼び出し元が 2 つある：

| 呼び出し元 | 場所 |
|---|---|
| `Event:CheckHeight` | event.lua:569 |
| `Engine:CalculateIdleMode` | engine.lua:697 |

→ **レイキャスト 200 回/秒 + `GetWorldPosition` 400 回/秒**。

### 設計：フレーム単位キャッシュ

**車両はフレーム内では動けない**（物理はフレーム間にステップする）。
よって同一フレーム内の全呼び出し元は**同じ数を聞いている**。
`AV:GetEntity` と同じ方式でフレーム単位キャッシュにする。

```lua
function Navigation:GetHeight()
    local frame = DAV.frame_seq
    if frame ~= nil and self._height_frame == frame then
        return self._height
    end
    local position = self.av_obj:GetPosition()
    if position == nil then
        return 0
    end
    -- 既に解決した位置を下の関数に手渡す。GetGroundPosition もこれを使う。
    local height = position.z - self.av_obj:GetGroundPosition(position)
    if frame ~= nil then
        self._height = height
        self._height_frame = frame
    end
    return height
end

function Navigation:InvalidateHeightCache()
    self._height = nil
    self._height_frame = nil
end
```

`DAV.frame_seq` が無い場合はキャッシュを**バイパス**する。
動かないカウンタに対して鮮度を論じられないので、
古い値を永久に返すくらいなら毎回計測する。

### `AV:GetGroundPosition(from_pos)`：位置を受け取る＋入力を壊さない

```lua
function AV:GetGroundPosition(from_pos)
    local base = from_pos or self:GetPosition()
    ...
    local start_z = base.z + self.search_ground_offset
    local is_success, trace_result = Game.GetSpatialQueriesSystem():SyncRaycastByQueryFilter(
        Vector4.new(base.x, base.y, start_z, 1.0),
        Vector4.new(base.x, base.y, start_z - self.search_ground_distance, 1.0),
        self.collision_query_filter, false, false)
    if is_success then return trace_result.position.z end
    return start_z - self.search_ground_distance - 1
end
```

**副次的に潰したバグ**：修正前は
`current_position.z = current_position.z + self.search_ground_offset` と
**呼び出し元から渡された Vector4 を直接書き換えて**いた。
現在は `GetPosition()` が返す新しいうえに破棄されるテーブルしかなかったので
表面化していなかったが、`from_pos` を渡せるようにした以上、
入力を mutate するのは事故る。新しいベクタを構築する形にした。

### 無効化ポイント

| 箇所 | 処理 |
|---|---|
| `AV:Spawn`（`CreateEntity` 直後） | `self.navigation_obj:InvalidateHeightCache()` |
| `AV:Despawn`（`DeleteEntity` 後） | 同上 |
| `Core:Reset` | 新しい `AV`/`Navigation` なのでキャッシュは空 |

`AV:InvalidateEntityCache()` にも**高さキャッシュの無効化は入れていない**。
名前と挙動を一致させておくため、`Spawn` / `Despawn` で明示的に 2 つ呼ぶ。

### 効果（`tools/interop_tick_audit.py` で再現可能）

```
Ground probe (Navigation:GetHeight -> SyncRaycastByQueryFilter)
  situation                          before f(2)      after f(2)
  B  Waiting                        200/s (400)      60/s (60)
  C  InVehicle 手動飛行              200/s (400)      60/s (60)
  D  InVehicle + autopilot          200/s (400)      60/s (60)
       （レイキャスト/秒、( ) は GetWorldPosition/秒）
```

| | 修正前 | 修正後 |
|---|---|---|
| 地面レイキャスト | 200/s（呼び出し元数 × 100 Hz） | **60/s**（60fps、フレーム毎 1 回） |
| `GetWorldPosition` | 400/s | **60/s** |
| レイキャストのジオメトリ | `pos.z + offset` → `start - distance` | **同一（テストで保証）** |
| 応答遅延 | なし | 最大 1 フレーム（60fps で 16.7ms）。降下 5m/s で 8cm |

### 検証

**新規テスト `tests/height_cache_test.lua`（31 passed, 0 failed）**
`SyncRaycastByQueryFilter` と `GetWorldPosition` にカウンタを載せ、12 節：

| 節 | 検証内容 |
|---|---|
| 1 | 11 回呼んでもレイキャストは 1 回 |
| 2 | フレームが進むと再計測 |
| 3 | キャッシュは世界を追う（同一フレーム内では保持、次フレームで新値） |
| 4 | `GetHeight` 1 回 = `GetWorldPosition` 1 回・`FindEntityByID` 1 回（**修正前は 2 回**） |
| 5 | レイキャストのジオメトリが修正前と同一（start=+2 / target=−48 / x,y 不変） |
| 6 | `GetGroundPosition` が呼び出し元のベクタを書き換えない |
| 7 | 引数なしなら自前で位置を解決（後方互換） |
| 8 | レイキャストミス時のフォールバック値が従来と同一 |
| 9 | `InvalidateHeightCache` で強制再計測 |
| 10 | `Spawn` / `Despawn` がキャッシュを落とす |
| 11 | `frame_seq` 欠落時はキャッシュをバイパス（古い値を返さない） |
| 12 | 同一フレームの 2 呼び出し元が 1 レイキャストを共有し同値を見る |

```
python tests/run_entity_cache_test.py
  entity_cache_test : 30 passed, 0 failed
  height_cache_test : 31 passed, 0 failed
構文ゲート: 42 files, 0 problems
```

---

## 7. 実機での切り分け方（次の調査向け）

今の `profprobe` は **Navigation のメソッドしか wrap していない**
（navigation.lua:5680 以降）。だから AV / Event / HUD / Engine の interop は
**計測から丸ごと見えていない**。init.lua:441 しか太って見えないのはこれが理由。

```lua
Prof.wrap_methods(AV, {
    {"IsPlayerIn",     "av.is_player_in"},
    {"GetPosition",    "av.get_pos"},
    {"GetEulerAngles", "av.get_euler"},
    {"GetGroundPosition", "av.ground_raycast"},
    {"Operate",        "av.operate"},
})
Prof.wrap_methods(Engine, {
    {"Update",         "eng.update"},
    {"Run",            "eng.run"},
    {"GetDirectionAndAngularVelocity", "eng.get_vel"},
})
```

`GetGroundPosition` と `CollectSphericalRepulsion` の `total_ms` が、
この Mod が他 Mod より悪目立ちしている正体。
