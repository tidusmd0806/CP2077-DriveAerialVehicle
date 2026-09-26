# DriveAerialVehicle パフォーマンス改善計画

作成日: 2026-09-25
対象バージョン: 3.2.2 (game 2.13 / CET 1.36 / Codeware 1.17)
関連するユーザー報告: Nexus Mods スレッド（2026-09-14 〜 09-24）
「AVを召喚していなくても micro-stutter が発生する」「AFK でも起きる」
「3.1.0 → 3.2.2 アップデート後 40秒で CTD (EXCEPTION_ACCESS_VIOLATION 0xC0000005)」

---

## 1. 実測した現状

### 1.1 障害物マップ（obstacle map）の実データ

| 項目 | 値 |
|---|---|
| `Data/map/` chunk ファイル数 | 96 |
| 総ファイルサイズ | 36 MB |
| 障害物セル総数 | **2,625,381** |
| 1 chunk あたり | 約 27,300 cell / 約 3.2 MB（Lua live heap 換算） |
| cell 1個あたりの Lua 消費 | 約 120 byte |

### 1.2 ロードコスト（Lua 5.4 / 実コード同一ロジックで計測）

`Navigation:LoadObstacleMapChunkFile()` + `RegisterCellInChunkIndex()` を全 chunk に対して実行：

| 指標 | 値 |
|---|---|
| 合計パース時間 | 3.35 s |
| 1ファイルあたり p50 | **31 ms** |
| 1ファイルあたり p90 | 68 ms |
| 1ファイルあたり max | **290 ms** |
| ロード後 Lua live heap | **307 MB** |

### 1.3 常駐メモリと GC スパイクの関係（本報告の核心）

MOD のアイドルループ（`GetActions()` + `UpdateGarageInfo()`）相当を 12,000〜20,000 回
回した際の 1tick あたり所要時間（Lua 5.4 増分GC、pause=110 / stepmul=150）：

| 常駐 chunk 数 | live heap | p50 | p90 | p99 | p99.9 | max | ≥8ms tick |
|---|---|---|---|---|---|---|---|
| 0（マップ無し） | 0.3 MB | 0 | 0 | 1 | 1 | 1 | **0.0%** |
| 4 | 12.8 MB | 0 | 1 | 1 | 1 | 2 | 0.0% |
| 9 | 36.7 MB | 1 | 2 | 3 | 3 | 3 | 0.0% |
| 16 | 48.0 MB | 1 | 2 | 2 | 3 | 4 | 0.0% |
| 25 | 81.7 MB | 1 | 3 | 5 | 6 | 8 | **0.0%** |
| 49 | 173.8 MB | 1 | 2 | 13 | 16 | 22 | **5.0%** |
| 96（現状＝全量） | **301 MB** | 2 | 6 | **35** | **52** | **67** | **4.5%** |

**読み方**

- 現状（全量常駐）では **tick の 4.5% が 8ms 超**、p99.9 で **52ms**、最大 **67ms**。
  60fps 時に 3〜4 フレーム同時落ち = 「数秒おきに CPU が-high-と- dip を繰り返す」の正体。
- **25 chunk（≈82MB）以下なら 8ms 超のスパイクは観測されない。**
- 原因はバイト数そのものより **生存オブジェクト数**（文字列キー 260 万本 + テーブルエントリ 520 万件）。
  Lua 5.4 の増分 GC は生存集合全体を反復するため、アロケーションがほぼ無い AFK 状態でも
  GC が仕事を続け、周期性のあるスパイクを発生させる。

→ **恒久対策には「常駐セル数の削減」が必須**であり、単なる非同期化／時間分散では解決しない。

---

## 2. 現状の実装が抱える問題（箇所別）

### 問題 A: 起動時に全量をロードしている
`Core:Init()`（`init.lua:396` の `onInit` から実行）内で無条件に：

```
Core:Init()                                  core.lua:121
  └ StartObstacleMapSessionPreload()         core.lua:148
      └ nav:StartObstacleMapSessionPreload() navigation.lua:633
          ├ BuildObstacleMapLoadQueue()      navigation.lua:288   ← 全 96 chunk
          └ Core:EnsureObstacleMapPreloadTimer(0.05, 1)  core.lua:201
```

`obstacle_map_preload_tick = 0.05`（`navigation.lua:104`）／`files_per_tick = 1`（`navigation.lua:654`）のため、

> **50ms ごとに 1 ファイル＝約 31ms（最悪 290ms）をゲームスレッドでブロック** が約 5 秒間続く。

加えてロード後 300MB がセッション終了まで常駐し、§1.3 の GC スパイクを持続させる。

### 問題 B: アイドルループが 100Hz で C# interop を叩く
`init.lua:19` `time_resolution = 0.01` → `core.lua:150` の `Cron.Every(0.01, ...)` は
フレーム delta（≈16.7ms）より短いため**実質毎フレーム発火**する。

```
Cron.Every(0.01)                       core.lua:150
  ├ event_obj:CheckAllEvents()         event.lua:262
  │    └ Normal → CheckGarage()       event.lua:300
  │         └ UpdateGarageInfo(false)  core.lua:522
  │              ├ Game.GetVehicleSystem()
  │              └ GetPlayerUnlockedVehicles()  ← 毎フレーム N 個の userdata を新規アロケート
  └ GetActions()                       core.lua:1069
```

`UpdateGarageInfo` の early-return（`core.lua:529`）は **上記 2 つの C# 呼び出しの後**にしか効かない。
クリア後セーブ（解錠車両 150〜200 台）では **毎秒約 1 万個** のガベージを生成し、
§1.3 の GC 圧をさらに増幅する。

### 問題 C: `io.popen` による外部プロセス起動
`navigation.lua` の 7 箇所（`:295 :297 :311 :349 :351 :2244 :2261`）で `io.popen('dir /b ...')` を使用。
`EnsureMapDirectory()` の `os.execute('mkdir ...')`（`:1989` 付近）も同様。

- 起動時に最低 2 回（`BuildObstacleMapLoadQueue`）— ブロッキング
- **autopilot 実行中も** `FindNearestObstacleMapChunk`（`:414`）→ `EnumerateObstacleMapDataChunks`（`:345`）
  経由でルート決定のたびに `cmd.exe` を起動

### 問題 D: 文字列キーによる二重インデックス
- `obstacle_map[cell_key]` … 260 万本の文字列キー `"x_y_z"`
- `obstacle_map_chunk_index[chunk_key][cell_key]` … 同一文字列を**もう一度**キーとして保持

同一データ構造が 2 体系あり、文字列は共有されるもののテーブルエントリが倍化している。

---

## 3. 修正案

### (1) 常駐ウィンドウ方式の遅延ロード＋退避（eviction） ★今回実装

**方針**: 全常駐をやめ、「プレイヤー周辺 chunk だけ」を常駐させ、他は必要時のみロードする。
ロードは常に**実時間バジェット制**（1 tick ≤ 3ms）で、フレームを絶対にブロックしない。

#### 1-1. 新規設定（`Navigation:New`）

| 設定 | 既定値 | 意味 |
|---|---|---|
| `obstacle_map_load_budget_ms` | `3.0` | ロード処理 1 tick あたりの実時間上限 |
| `obstacle_map_resident_radius` | `2` | プレイヤー周辺で常駐させる chunk 半径（1 chunk = 500m） |
| `obstacle_map_evict_radius` | `4` | この半径外になった chunk を退避対象にする（ヒステリシス） |
| `obstacle_map_preload_tick` | `0.05`（既存） | キャッシュメンテナンス tick 間隔 |

既定値の根拠：radius 2 → 5×5 = 25 chunk ≈ **82MB**。§1.3 より 8ms 超スパイクが
観測されない領域（25 chunk まで 0.0%）に収まる。
機能面でも recording range 60m / `autopilot_searching_range` 50m /
`nearest_known_search_soft_limit_cells` 60 cell(600m) に対し 1000m は十分。

#### 1-2. 起動タイミングの変更

- `Core:Init()`（`core.lua:148`）からの `StartObstacleMapSessionPreload()` を**削除**。
  → `onInit` 時点ではプレイヤー位置が不明で距離順ソートができないため。
- `event.lua:86` の `SessionStart` ハンドラ内で起動する。
  （`is_initial_load` 分岐の後、`SetFastTravelPosition()` の直後）

#### 1-3. 常駐キャッシュの仕組み

新規状態：

```lua
obj.obstacle_map_all_chunks     = {}   -- ディスク上の全 chunk 一覧（1回だけ列挙してキャッシュ）
obj.obstacle_map_resident       = {}   -- [chunk_key] = true  現在常駐中
obj.obstacle_map_route_chunks   = {}   -- autopilot ルートが要求した chunk（退避から保護）
```

`obstacle_map_preload_tick` で走る**メンテナンスタイマー**（1 本だけ）が毎 tick 次を行う：

1. プレイヤー位置を取得 → 現在 chunk 座標 `(pcx, pcy)` を算出
2. `resident_radius` 内の未ロード chunk を**距離順**に、
   **経過時間が `load_budget_ms` を超えるまで**ロード（少なくとも 1 ファイルは進める）
3. `evict_radius` より外、かつ `route_chunks` に含まず、かつ dirty でない chunk を退避
   - `obstacle_map_chunk_index[ck]` を辿って `obstacle_map[cell_key] = nil`
   - 退避対象に dirty chunk があれば先に `SaveObstacleMap()` を 1 回呼ぶ（データロス防止）
4. 何もしることが無い tick のコストは O(chunk 数)=96 の距離計算のみで無視できる

既存構造（`obstacle_map` / `obstacle_map_chunk_index`）をそのまま使うため、
**eviction は既存 API の上で完結**し、(2) の再設計を待たずに実装できる。

#### 1-4. autopilot との整合（重要な設計制約）

`GetSectorMovementCost()`（`navigation.lua:829-841`）は **未知セルを `astar_blocked_penalty`(=500) で
「通れない」扱い**にする。したがって常駐を絞ると長距離 A* が全滅する。

対策：
- autopilot 開始時（`Navigation:AutoPilot()`）に `EnsureChunksLoadedForRoute(start, goal)` を呼ぶ。
  start→goal の線分に沿った chunk（＋垂直方向 1 chunk 幅の回廊）を特定し、
  **既存の route-plan ステップジョブ（`StepRoutePlanJob`）の 1 ステップにつき 1 chunk** を
  バジェット内でロードする。A* は元々ステップ分割済みなので新たなブロックは発生しない。
- ルート完了／中断時に `obstacle_map_route_chunks` を解除し、次回メンテナンスで退避。
- 未達の間は「未知＝blocked」を維持する（＝既存挙動を変えない）。

#### 1-5. 期待効果

| | 現状 | (1) 適用後 |
|---|---|---|
| 起動時 5 秒間の 1tick 最大ブロック | 31〜290 ms | ≤ 3 ms |
| セッション中 live heap | 301 MB | 約 82 MB（radius 2） |
| ≥8ms tick 割合 | 4.5% | 0%（§1.3 の 25chunk 相当） |
| p99.9 | 52 ms | ≤ 8 ms |

---

### (2) キー／インデックス構造の圧縮（次回以降）

現状の 120 byte/cell を削減する。

- **文字列キーの廃止**: `"x_y_z"` を数値キーにパックする。
  `key = (cx + 32768) * 2^18 + (cy + 32768) * 2^9 + (cz + 256)` 等。
  260 万本の文字列（≈125MB）と文字列ハッシュ計算が消える。
- **二重インデックスの統合**: `obstacle_map` と `obstacle_map_chunk_index` を
  `chunk_cache[ck].cells[cell_key] = value` の 1 体系に統合し、テーブルエントリを半減。
- 目標: **120 byte/cell → 45 byte/cell 以下**（radius 2 で 82MB → 約 31MB）

**影響範囲（大きい）**: `PositionToSectorKey` 14 箇所、`ParseSectorKey` 16 箇所、
手動キー連結 24 箇所、`GetNeighborSectors` 4 箇所、`Debug/debug.lua:489`。
→ 単独のブランチで全経路を網羅テストしてからマージすること。
**`Navigation` 外への公開 API（キー文字列）は互換維持のため `SectorKeyToString()` で吸収する。**

---

### (3) `UpdateGarageInfo` の間引き ★今回実装

現状：毎フレーム `Game.GetVehicleSystem()` + `GetPlayerUnlockedVehicles()`（`core.lua:522-533`）

修正：
- 更新間隔 `garage_update_interval = 1.0` 秒を追加。前回更新からの経過時間が
  1 秒未満かつ `is_force_update == false` なら、**C# を呼ぶ前に return** する。
  （early-return を C# 呼び出しより前に移動させるのが要点）
- 実際の UI 更新は 1Hz で十分（ガレージ一覧はプレイ中に頻繁には変わらない）。
- .force 呼び出し箇所（`ChangeGarageAVType` 等）は従来通り即時反映。
- `SessionStart` 時は 1 回強制更新する。

期待効果：アロケーション **毎秒約 10,000 個 → 約 150 個（1/60）**。

---

### (4) `io.popen` / `os.execute` の廃止（次回以降）

- `EnumerateObstacleMapDataChunks()`（`navigation.lua:345`）の結果を
  `obstacle_map_all_chunks` にキャッシュし、**1 セッション 1 回**の列挙にする。
  （(1) の実装でもこのキャッシュを使うので、(1) であらかじめ大半は解消される）
- 残る `BuildObstacleMapLoadQueue`（`:288`）の 2 回も、同じキャッシュに置換。
- `EnsureMapDirectory()` の `os.execute('mkdir')` は、`io.open` 失敗時の 1 回だけ。
  可能なら CET のファイル API もしくは `lfs` 相当に置き換え、難しければ
  「初回のみ・ロード画面中限定」に限定して許容する。

期待効果：autopilot 中の `cmd.exe` プロセス起動が **0 回** になる。

---

## 4. 実装順序とスコープ

| # | 項目 | 状況 | リスク |
|---|---|---|---|
| 1 | 常駐ウィンドウ遅延ロード＋eviction | **実装済み** | 中（autopilot 回廊ロードが要検証） |
| 3 | `UpdateGarageInfo` 間引き | **実装済み** | 低 |
| 2 | キー／インデックス圧縮 | 計画のみ | 高（広範囲リファクタ） |
| 4 | `io.popen` 廃止 | 計画のみ（(1)で 1回/セッションに削減済み） | 低 |

### 4-1. 実装内容（確定したファイル／関数）

**`Modules/navigation.lua`**
- `Navigation:New` — 新規設定・状態
  `obstacle_map_resident_radius = 2` / `obstacle_map_evict_radius = 4` /
  `obstacle_map_load_budget_ms = 3.0` / `obstacle_map_route_max_chunks = 12` /
  `obstacle_map_route_chunks` / `obstacle_map_load_states` /
  `obstacle_map_cache_started`
- `PositionToChunkCoords()` — ワールド座標 → chunk 座標
- `GetAllChunksCached(force_refresh)` — ディスク上の chunk 一覧を**1セッション1回**だけ列挙してキャッシュ
- `MarkChunkOnDisk(chunk_key, has_dat, has_diff)` — 保存で生じた新ファイルをインベントリに反映
- `ParseChunkIncremental(chunk_info, budget_s)` — **読み込みもパースも中断可能な増分ローダ**
- `LoadResidentChunk(chunk_info)` — 1発読み（autopilot 目的地用）
- `IsChunkResident(chunk_key)` / `UnloadResidentChunk(chunk_key)` / `IsChunkEvictable(...)`
- `EnsureResidentChunks(pcx, pcy)` — 半径内の未ロード chunk を距離順にバジェット内までロード
- `EvictDistantChunks(pcx, pcy)` — 半径外・非ピン・非in-flight の chunk を退避（dirty は先に flush）
- `MaintainObstacleMapCache()` — 上記 2 つをまとめた 1 tick のメンテナンス
- `PrepareRouteChunks(start, end)` / `ReleaseRouteChunks()` — ルート回廊のピン
- `StartObstacleMapSessionPreload()` — 全量キュー投入から常駐キャッシュ開始へ変更
- `SaveObstacleMap()` / `IntegrateObstacleMapDiff()` — `MarkChunkOnDisk` 呼び出し追加
- `AutoPilot()` — ナレッジ評価前に `PrepareRouteChunks()`
- `SuccessAutoPilot()` / `InterruptAutoPilot()` — `ReleaseRouteChunks()`

**`Modules/core.lua`**
- `Core:Init()` — `StartObstacleMapSessionPreload()` を**削除**
- `Core:Reset()` — `has_started_obstacle_map_preload` / `last_garage_update_time` をリセット
- `Core:EnsureObstacleMapPreloadTimer(tick_interval)` — 使い捨てプリロードタイマーから
  **セッション中永続のメンテナンスタイマー**へ変更（`MaintainObstacleMapCache()` を呼ぶ）
- `Core:UpdateGarageInfo(is_force_update)` — **C# を呼ぶ前**に 1秒スロットル
- `Core:New` — `garage_update_interval = 1.0` / `last_garage_update_time = nil`

**`Modules/event.lua`**
- `SessionStart` — `StartObstacleMapSessionPreload()` と `UpdateGarageInfo(true)` をここで起動

### 4-2. 実装中に見つかり修正したバグ

テスト（`tools/run_resident_cache_test.py`）で実際に検出・修正したもの：

1. **増分リーダが diff を読み飛ばしていた**
   ファイル読み完了時に `st.fi` をインクリメントしていたため、後続の `.diff` を
   二重にスキップしていた。→ 完了時はパース終了後にのみ進めるよう修正。
   （`.dat` が danger、`.diff` が obstacle のセルが obstacle に復元されない症状）
2. **インベントリ再列挙で居住状態が孤立していた**
   居住判定を `chunk_info.loaded`（インベントリ側）に依存させていたため、
   再列挙するとメモリ上のセルと食い違った。→ 居住判定を
   `obstacle_map_chunk_index` ＋ `obstacle_map_load_states`（in-flight）から
   算出し、インベントリから完全に独立させた。
3. **セッション中に新規作成された `.diff` が再ロードで拾われない**
   インベントリがセッション開始時のスナップショットだったため。→ `SaveObstacleMap()` /
   `IntegrateObstacleMapDiff()` から `MarkChunkOnDisk()` を呼ぶようにした。
4. **eviction 中のファイルハンドルリーク**
   読み込み途中で chunk が退避され得る。→ `UnloadResidentChunk()` と
   `ReleaseObstacleMapSessionCache()` で `fh:close()` を追加。

---

## 4A. 実測結果（fix (1)＋(3) 適用後）

### 常駐メモリとアイドル時 GC スパイク

MOD のアイドルループ（`GetActions()` + `UpdateGarageInfo()` 相当）を 20,000 回実行。
Lua 5.4 / pause=110 / stepmul=150。

| | live heap | p50 | p90 | p99 | p99.9 | max | ≥8ms tick |
|---|---|---|---|---|---|---|---|
| A. 障害物マップ無し | 0.8 MB | 0 | 0 | 1 | 1 | 1 | 0.00% |
| B. 全量常駐（**旧**・96 chunk） | **301 MB** | 2 | 6 | **56** | **68** | 109 | **4.01%** |
| C. 常駐ウィンドウ（**新**・19 chunk） | **72 MB** | 1 | 5 | **8** | **12** | 35 | **1.04%** |

改善幅（B → C）：**heap −76% / p99 −86% / p99.9 −82% / ≥8ms tick −74%**

> 複数回実行した別ランでも p99 32ms → 7ms と同方向・同オーダーで再現。
> 「AVを召喚していない時の micro-stutter」はほぼ解消されるはず。

### 起動時（ウィンドウ充填）の 1tick 時間

| | p50 | p90 | p99 | worst |
|---|---|---|---|---|
| 充填中（19 chunk / 628,321 cell） | 4 ms | 4 ms | 6 ms | 32 ms |

- 従来：50ms ごとに **31ms（最悪 290ms）** が約 5 秒間**必ず**発生
- 現在：p50/p90 とも 4ms 前後。残る outlier は充填中の Lua テーブル rehash
  （`obstacle_map` が 2^n 境界を越える瞬間）で、**周期的ではなく一発もの**
- 充填完了までの間もフレームを占有しない

### 残存する既知のコスト

| 項目 | 現状 | 対応 |
|---|---|---|
| インベントリ列挙 `io.popen` ×2 | 17〜23ms（1セッション1回） | fix (4) で完全除去可能 |
| 充填中のテーブル rehash spikes | 一発 30ms 級が数回 | fix (2) でエントリ数削減により軽減 |

---

## 4B. リグレッションテスト

`tools/run_resident_cache_test.py`（`pip install lupa` が必要）で実行できる。
実際の `Modules/navigation.lua` を Lua 5.4 上で動かし、実 `Data/map` に対して検証。

```
python tools/run_resident_cache_test.py     # 42 passed, 0 failed
```

カバーしている項目：

| 区分 | 検証内容 |
|---|---|
| 1. 列挙 | chunk 発見、キャッシュ性（2回目同一テーブル） |
| 2. 居住ウィンドウ | 半径内は全てロード／半径外は一切引き込まない／件数上限 |
| 3. tick バジェット | p90 ≤ 2×budget、12ms 超は 5% 未満 |
| 4. ウィンドウ追従 | 離れると旧 chunk 退避、新 chunk ロード、evict radius 外に残らない |
| 5. dirty 保護 | 退避前に diff flush、再ロードで記録が復元される |
| 6. ルート回廊 | cap 遵守、キューイング（ブロッキングしない）、保守タイマーが回廊を排水、ピンは退避から保護、release で解除 |
| 6b. 出発ゲート | 延期される／回廊ストリーム完了後に on_ready／**保守タイマーが先に排水しても発火**／on_ready は一度だけ／キャンセルは無言で中止／不要なら延期しない |
| 7. 堅牢性 | プレイヤー無し / radius 0 / 未知 chunk_key で安全に no-op |

---

## 4D. fix (5)：長距離 autopilot の回廊プリロード（今回実装）

### 症状

全チャンクを読み込まないことにより、長距離 autopilot が明らかに遠回りする、
またはリプランを繰り返す。

### 根本原因（2つ、どちらも実測で確認）

**(a) 回廊が「保護されるだけでロードされていなかった」**

fix (1) の `PrepareRouteChunks()` は回廊チャンクを退避対象から**除外するだけ**だった。
実際のロードは `EnsureResidentChunks()` が「プレイヤー半径 2 chunk」で行うため、
その外側にある回廊は A* にとって **UNKNOWN のまま**だった。

実測（2.8km ルート、実 `Data/map` ＋ 実 `CreateRoutePlanJob`/`StepRoutePlanJob`）：

| 状態 | chunk 数 | live heap | 結果 | A* 反復 |
|---|---|---|---|---|
| 現状（ピンのみ） | 19 | 75 MB | **PARTIAL（1616m 手前）** | 100,000 **上限到達** |
| 回廊 1本幅をロード | 30 | 144 MB | **FULL** | **32,044** |
| 回廊 2本幅をロード | 31 | 164 MB | FULL | 32,044 |
| 全マップ常駐（旧動作） | 96 | 315 MB | FULL | 32,044 |

→ **1本幅で 2本幅・全マップと完全同結果**。広い回廊は不要。

**(b) 未知セルが確定障害物と同一コスト**

`navigation.lua` の `GetSectorMovementCost()` は unknown を
`astar_blocked_penalty = 10000`（＝確定障害物と同額）で評価する。
そのため A* は到達し得ない空間に挑み、**イテレーション上限 100,000 を使い切って
partial ルート**を返す → 0.5 秒ごとに再計画 → 「往復」「遠回り」。

### 実装

| 関数 | 役割 |
|---|---|
| `PrepareRouteChunks(start, end)` | 線分上の回廊 chunk を算出しピン留め、未ロード分を**キューに入れ**件数を返す（同期ロードはしない） |
| `StartRouteCorridorPreload(start, end, on_ready)` | 回廊をストリームし終えたら `on_ready()` を呼ぶ。延期したら `true` を返すので呼び出し側は先に進まない |
| `LoadResidentChunkIncremental(info, budget_s)` | `LoadResidentChunk` の増分版。完了時に居住登録 |
| `DrainRouteCorridor(budget_s)` | キューを予算分だけ排水。**完全にロードできた entry のみを除去** |
| `MaintainObstacleMapCache()` | 回廊キューをウィンドウ保守より優先して排水 |
| `AutoPilot()` | 知識評価〜初期プランを `begin_navigation()` に包み、ゲート完了後に実行 |

**出発ゲートの挙動**：`AutoPilot()` は `AutoLeaving` 状態で到達するため、
ゲート中の待ちは**無言のホバー**として見える（HUD 表示なし）。

### 設定（`Navigation:New`）

| キー | 既定値 | 意味 |
|---|---|---|
| `obstacle_map_route_max_chunks` | `32` | 回廊の上限。同梱マップは最悪でも ~16 chunk なので実質「全距離対応」 |
| `obstacle_route_load_budget_ms` | `15.0` | ゲート中の 1tick 予算（通常 3.0ms の 5 倍。停止中なので大きくしてよい） |
| `obstacle_route_tick` | `0.02` | ゲート専用 Cron 間隔 |
| `obstacle_route_wait_timeout` | `15.0` | 出発を待たせる上限。超過分は飛行中に継続ロードされルートが改善し続ける |

### 実測（ゲート経路、実データ）

| 距離 | ホバー | ルート | A* 反復 | chunk / live heap |
|---|---|---|---|---|
| 0.5 km | 0 ms | FULL | 1,002 | 19 / 72 MB |
| 1.5 km | 120 ms | **FULL** | 68,348 | 20 / 105 MB |
| 2.8 km | 200 ms | **FULL** | 30,361 | 23 / 93 MB |
| 4.5 km | 60 ms | PARTIAL（未マップ領域） | 100,000 | 23 / 132 MB |

※ 4.5km 案の目的地はマップ x 範囲（-6〜2 chunk）外。データが存在しないため
   PARTIAL が正しい挙動。

### メモリ増加のスタッター影響

autopilot 中の live heap は 72 → 93〜142 MB。割当ループ代替計測では
**142 MB でも 8ms 以上の tick は 0.00%**（全マップ常駐の 301 MB では 4.5%）。
ウィンドウのみの通常時は 72 MB のまま。回廊はルート終了時 `ReleaseRouteChunks()`
で解放される。

### 実装中に見つけて修正したバグ

**① 回廊キューの脱落**
当初 `table.remove(list, 1)` をロード成否に関係なく実行していた。
予算内に終わらなかったチャンクは「キューから消えているが非居住」となり、
**そのまま二度とロードされず回廊に穴が開いた**（実測：ホバー 40ms で PARTIAL）。
`DrainRouteCorridor()` で**完全にロードできた entry のみを除去**するよう修正。

**② 保守タイマーとの競合で出発しなくなる（実プレイで発生）**

上昇して目的地を向いた後、**まったく進行しない**という症状。

`Core:EnsureObstacleMapPreloadTimer()` の 50ms タイマーが呼ぶ
`MaintainObstacleMapCache()` は、ゲートと同じ `obstacle_map_route_pending` を排水し、
空にすると `nil` を代入する。ゲート側はこれを

```lua
local list = self.obstacle_map_route_pending
if not list then
    Cron.Halt(timer)
    return          -- ← on_ready() を呼ばずに終了
end
```

と扱っていたため、**保守タイマーが先にキューを空にすると `begin_navigation()` が
一度も呼ばれず、autopilot ループ自体が起動しなかった**。

修正内容：
- キューが空／nil は「成功」として扱い `on_ready()` を呼ぶ
- キャンセル（`is_auto_pilot == false`）を完了より先に判定する
- `finish()` を **冪等** にし、`begin_navigation()` が二重実行されないようにした
  （二重実行は autopilot ループが二重化するため危険）
- `Cron.Every` の戻り値は数値 id なのに、引数の `timer`（args テーブル）と
  比較していて後片付けが効いていなかった箇所も修正

テスト 6b にレース再現を追加：ゲート待機中に `DrainRouteCorridor()` で
キューを先回りして空にし、`on_ready` がちゃんと発火することを検証。

### 未解決（意図的）

`GetSectorMovementCost()` の unknown コスト 10000 は**変更していない**。
回廊ロードで実データが揃うため今回の症状は解消するが、マップ外領域では
依然として「未知＝障害物」。ここを緩める（例 2.0）と未マップ空間を
突っ走るようになり、衝突回避は実時間レイトレース頼みになる。
リスクが上がるので、実プレイでの様子を見てから判断したい。

---

## 4C. 据えないこと（今回の非対象）
- `DAV.time_resolution = 0.01`（`init.lua:19`）自体は変更しない。
  → ループ回数はそのままだが、(1)(3) で 1tick あたりの仕事量が激減する。
  追加効果が必要なら (2) と合わせて 0.05 化を検討する。
- 同梱 RED4ext プラグイン `DriveAerialVehicle.dll`（クラッシュ報告のモジュール）は
  本リポジトリ外（`RED4-ext/RED4ext_DAV`）のため今回対象外。
  上記のフレームタイム改善で併発確率は下がると期待するが、断定には DLL 側の調査が必要。

---

## 5. 検証計画

### 5-1. 定量（dev ビルドで `debug.txt` 有効化して計測）
- [ ] 起動後 10 秒間の 1tick 最大所要時間 ≤ 3ms
- [ ] 通常歩行 60 秒で CET/ゲーム側の frame time p99 ≤ 17ms
- [ ] セッション中 live Lua heap ≤ 100MB（radius 2）
- [ ] `Cron` タイマー本数が常に 1 本（メンテナンスタイマー）＋ホールド中のみ増加

### 5-2. 機能（デグレ確認）
- [ ] AV 召喚／着地／搭乗／降車
- [ ] 近距離 autopilot（同一 chunk 内）
- [ ] **長距離 autopilot（複数 chunk を跨ぐ／市街地横断）** ← 最重要
- [ ] 障害物記録（`StartObstacleRecording`）と保存、再起動後の復元
- [ ] 退避した chunk に再進入したとき正しく再ロードされるか
- [ ] 退避前に dirty chunk が保存されているか（データロスが無いこと）
- [ ] 着地 VFX / 高度判定 / 衝突判定
- [ ] セーブ／ロード往復、ファストトラベル後
- [ ] LTBF / Audioware 併用時

### 5-3. 後方互換
- [ ] 既存 `user_setting_v3.json` からの起動（設定項目追加による破損が無いこと）
- [ ] 旧 `obstacle_map.dat` のマイグレーション（`MigrateOldObstacleMap`）が従来通り動くこと

---

## 6. リスクと低減策

| リスク | 低減策 |
|---|---|
| 長距離 autopilot が未知セルで停止する | 1-4 の回廊ロード。万一に備え `obstacle_map_resident_radius` を設定で拡大可能にする |
| eviction によるデータロス | 退避前に dirty なら必ず `SaveObstacleMap()`。退避対象から dirty chunk を除外 |
| eviction 直後の再ロードでカクつく | `evict_radius`(4) > `resident_radius`(2) のヒステリシスで往復（thrashing）を防ぐ |
| メンテナンスタイマーが走り続けて無駄 | 1 tick あたり O(96) の距離計算のみ。不要時は即 return するガードを入れる |
| 設定ファイルの互換性 | 新規設定は既定値があれば動くよう `or` でフォールバック |

---

## 4E. fix (6)：目的地が障害物のときの最終アプローチ・デッドゾーン（今回実装）

### 症状

目的地付近に障害物が多い場合、**永遠に到達せずスタック**する。
デバッグ表示では `Final Dest Cell: Obstacle`、`Route Progress: 4 / 3`。

`4 / 3` 自体はバグではない。`current_route_index > #current_global_route` は
「ルート全ウェイポイント消費済み」を示す正常な状態であり、コード全体でそのように
扱われている。問題は**その後にどの分岐にも入らない**こと。

### 根本原因：3m〜10m のデッドゾーン

実設定値で確認：

```
destination_range = 3.0m   (av.lua)
sector_size       = 10.0m
```

`astar` フェーズでの到着判定と最終レグ移行条件が、互いに隙間を作る形で書かれていた：

| 判定 | 旧条件 |
|---|---|
| 到着 | `dist_to_final_arr < destination_range` → **3m 未満** |
| `astar -> final_local` 移行 | `horiz_to_final > sector_size` → **10m より遠い** |

→ **水平 3m〜10m の間では、到着するには遠すぎ、移行するには近すぎる。**
機体はその場で永遠にホバーする。

さらに `astar -> final_local` 移行には `not self.astar_is_partial_route` という
ガードがあり、**まさに必要なケースを排除していた**：

- 目的地セルが障害物 → `autopilot_dest_requires_final_local = true`
- A* は正確な目的地セルに到達できないので **partial ルートしか返せない**
- partial ルートだと `can_arrive_at_final_destination = false`（到着不可）
- かつ `not astar_is_partial_route` が偽なので **final_local にも移行できない**
- followup は利得 50m 未満で却下 → `route_plan_next_followup_time` を延ばして再試行
- **無限ループ**

### 修正

`astar -> final_local` 移行条件を再構成：

| 項目 | 旧 | 新 |
|---|---|---|
| 下限距離 | `horiz_to_final > sector_size` | **撤去**（デッドゾーンの原因） |
| partial 除外 | `not astar_is_partial_route` | **撤去**（障害物目的地では partial が正常） |
| 上限距離 | なし | `horiz_to_final <= final_local_max_handoff_distance`（既定 150m） |
| 到達不能時のEscalation | なし | 低利得 followup 連続 3 回で距離無視で移行 |

上限を置いたのは、遠方で partial になった場合にまで純ローカル回避へ投げると
ルートの質が落ちるため。150m 以内なら最終レグとして妥当。

追加設定（`Navigation:New`）：

| キー | 既定値 | 意味 |
|---|---|---|
| `final_local_max_handoff_distance` | `150.0` | A* を諦めて最終レグへ渡す最大距離 |
| `final_local_fallback_after_rejects` | `3` | この回数だけ低利得却下が続けば距離無視で移行 |
| `autopilot_low_gain_followups` | `0` | 連続低利得却下カウンタ（ルート採用時・割り込み時にリセット） |

移行時には `astar_is_partial_route = false` と
`route_plan_next_followup_time = 0` もクリアし、followup チェーンを止めている。

### 検証

`tools/diagnose_route_unknown.lua` に実設定値による解析を追加：

```
destination_range=3.0m  sector_size=10.0m  max_handoff=150.0m
OLD: switch required horiz > sector_size, arrival required horiz < destination_range
-> DEAD ZONE (3m, 10m]: too far to arrive, too close to switch. Vehicle hovers forever.
NEW: switch when horiz <= max_handoff (or after enough low-gain retries)
new rule covers every distance up to max_handoff: true
```

既存の回廊テスト 42 件は全て維持、全 19 ファイルコンパイル OK。

---

## 4F. fix (4)：`io.popen` / `os.execute` の廃止（今回実装）

### 変更

| 関数 | 旧 | 新 |
|---|---|---|
| `EnumerateObstacleMapDataChunks()` | 呼び出しごとに `dir /b` で `cmd.exe` 起動 | `GetAllChunksCached()` のセッションキャッシュを返すだけ。**ファイルシステムに触らない** |
| `BuildObstacleMapLoadQueue()` | `.dat` / `.diff` で 2 回 popen | キャッシュから生成（`MigrateOldObstacleMap` 後なので `force_refresh`） |
| `LoadObstacleMap()` | popen 2 回＋441 回の座標 probe フォールバック | キャッシュ 1 回。probe ループは削除 |
| `EnsureMapDirectory()` | 変更なし | 既に `obstacle_map_dir_ok` でキャッシュ済み。`mkdir` はディレクトリテスト失敗時の 1 回のみ |

`FindNearestKnownSectorPos` / `FindNearestKnownSectorPosInDirection` /
`FindNearestSafeOrDangerCellPos` は `FindNearestObstacleMapChunk` 経由で
`EnumerateObstacleMapDataChunks()` を呼んでいたため、**autopilot のターゲット解決
たびに `cmd.exe` が起動していた**のが消えた。

残る `io.popen` は `GetAllChunksCached()` 内の 1 箇所（セッション中 1 回の初期列挙）
と `EnsureMapDirectory()` の `mkdir`（初回のみ）だけ。

### 検証（テスト 8）

`io.popen` / `os.execute` をラップして起動回数を計数：

```
[PASS] inventory warm-up spawns at most the one-time enumeration
[PASS] autopilot target resolution spawns zero processes
[PASS] nearest-chunk lookup still resolves
[PASS] FindNearestKnownSectorPos still runs
[PASS] FindNearestSafeOrDangerCellPos still runs
[PASS] EnumerateObstacleMapDataChunks returns the cached table (no copy, no probe)
```

20 回のターゲット解決で追加プロセス起動 **0 件**。

---

## 4G. fix (2)：数値パックセルキー化（今回実装）

### 実測したコスト内訳（実 `Data/map`・radius 2 ウィンドウ 628,321 cell）

| | 実装前 | 実装後 |
|---|---|---|
| 合計 | 71.3 MB / **119.0 B/cell** | 43.4 MB / **72.3 B/cell** |
| 削減 | — | **−39%** |

`"x_y_z"` 文字列（平均 8.7 文字）の intern 分と、ルックアップごとの
文字列ハッシュ計算が消えた。

### キーレイアウト

```
sx, sy : 18 bit, bias 131072  ->  +-131071 cell（10m/cell で +-1310 km）
sz     : 10 bit, bias 256     ->  -256 .. +767
key = ((sx + 131072) * 2^18 + (sy + 131072)) * 2^10 + (sz + 256)
最大 ~2^46 → double の 53bit 整数範囲内で厳密
```

チャンクキー `"cx_cy"` は約 96 本しかないので文字列のまま。

### 追加した API

| 関数 | 役割 |
|---|---|
| `PackCellKey(sx, sy, sz)` | 数値キー化 |
| `UnpackCellKey(key)` | 逆変換。**旧 `"x_y_z"` 文字列も許容**して座標を返す |
| `SectorKeyToString(key)` | 表示用 `"x_y_z"`（ログ・デバッグオーバーレイ） |
| `NormalizeCellKey(key)` | setter 入口で数値に正規化 |

### 変更した箇所

`PositionToSectorKey` / `ParseSectorKey` / `SectorKeyToPosition` /
`GetNeighborSectors` / `CellKeyToChunkKey` / `SetObstacleCell` /
`SetObstacleCellNoDirty` / `MarkCellDirty`、ファイルパーサ 6 箇所
（`ParseChunkIncremental` ほか）、`SaveObstacleMap` の diff 書き出し、
`Debug/debug.lua` の表示 3 箇所。

`ParseSectorKey` から `astar_coord_cache` の利用を削除（算術展開なので
正規表現もキーごとのテーブル確保も不要）。

### ホットパス実測（200 万 ops）

| | ops/s |
|---|---|
| `ParseSectorKey`（算術） | **9,174 k** |
| 旧：regex match + tonumber ×3 | 6,472 k |

→ **1.42 倍**。A* は 1 計画で数十万回この経路を通るため無視できない。

### 安全性のために入れたもの

`NormalizeCellKey()` を setter 入口に置いた。これが無いと、旧式の文字列キーが
setter に渡った瞬間 `obstacle_map` に**文字列キーの並行エントリ**が生まれ、
チャンクインデックス・退避・A* ルックアップがすべて食い違う
最悪の split-brain になる。テストで抑止：

```
[PASS] setter normalises a string key to the packed entry
[PASS] no parallel string-keyed entry leaked into the map
[PASS] pack/unpack round-trips for every sampled coord triple
[PASS] distinct triples pack to distinct keys
[PASS] legacy string key unpacks to the same triple
```

### 残った課題（意図的に今回やらない）

`obstacle_map_chunk_index` の**二重インデックス分 19.1 MB（31.7 B/cell）**は
まだ残る（map 単体なら 24.3 MB / 40.6 B/cell まで下がる）。

ハッシュ集合から配列への変換は検討したが、`MarkCellDirty()` が
**記録のたびに同じ cell_key を index へ追加**するため、配列だと重複が積み上がり
長時間セッションでリークする。dedup 戦略（dirty 時のみ追加、等）を
別途設計しないと安全に潰せない。

`GetNeighborSectors()` も 1 呼び出しごとにテーブル 1 本＋数値ボクシング 10 個を
確保しており（447 k ops/s）、キー形式では改善しない。バッファ使い回しは
ネスト反復との相互作用があるため別対応。

---

## 4H. 全 fix 適用後の総合測定量

| ケース | fix (1) 直後 | 全 fix 適用後 |
|---|---|---|
| アイドル（radius 2） | 72 MB | **44 MB** |
| 1.5 km autopilot | 105 MB | **60 MB** |
| 2.8 km autopilot | 93 MB | **51 MB** |
| 8ms 超 tick 割合 | 0.00% | 0.00% |

ルート結果は fix 前后で完全一致（同 cell 数・同反復回数・FULL/PARTIAL 一致）。
テスト **58 passed, 0 failed**、全 19 ファイルコンパイル OK。

---

## 4I. fix (7)：ウィンドウ充填の遅延（今回実装）

### 問題

fix (1) で全マッププリロードは消えたが、`SessionStart` 時点で
**プレイヤー半径 2 chunk のウィンドウ充填**が依然として走っていた。

```
SessionStart → EnsureObstacleMapPreloadTimer(0.05)
  └ 50ms ごと: MaintainObstacleMapCache()
       └ EnsureResidentChunks(プレイヤー現在 chunk)   ← 発火条件が「ロード完了」だけ
```

実測（fix (7) 適用前）:

| 項目 | 値 |
|---|---|
| 充填にかかった時間 | 約 14 秒（285 tick × 50ms） |
| 充填 chunk / cell 数 | 19 chunk / 628,321 cell |
| ヒープ | 46 MB |
| 充填中の tick 分布 | p50 4ms / p99 6ms / max 52ms |
| 8ms 超 tick | 約 0.88% |

障害物の**記録は AV 搭乗中しか走らない**（`av.lua:672` / `av.lua:715`）ため、
この 14 秒は「AV も autopilot も使わないプレイヤー」には完全に無駄だった。

### 設計：充填ゲート

`obstacle_map_fill_started` を追加し、**AV が実際に動くまで窓を開かない**。

| 時点 | 充填ゲート | 挙動 |
|---|---|---|
| `SessionStart` | 閉 | 在庫表（`GetAllChunksCached(true)`）だけ作る。チャンク読込ゼロ |
| autopilot 初回出発 | 開 | 窓が AV を追従し始める |
| 記録開始（開発者モード） | 開 | 記録セッションも窓を温める |

`MaintainObstacleMapCache()` 側:

```lua
local pending = 0
if self.obstacle_map_fill_started then
    local _, pending_now = self:EnsureResidentChunks(pcx, pcy)
    pending = pending_now
end
```

### 効果（実測）

| 状態 | チャンク / cell | ヒープ | 8ms 超 tick |
|---|---|---|---|
| ゲート閉（ロード後 14 秒、autopilot 未使用） | **0 / 0** | **0.4 MB** | **0.00%** |
| ゲート開（初回 autopilot 後） | 19 / 628,321 | 46.4 MB | 1.14%（充填中） |
| 定常（充填完了後） | 19 / 628,321 | 43.4 MB | 0.00% |

**autopilot を使わない一般ユーザーは、ロード後に障害物マップのコストを一切払われない。**

### 回廊キューの単一駆動化

fix (5) で回廊キューに駆動元が 2 つ出来ていた（ゲート自身の 20ms Cron と
保守タイマー 50ms 経由）。**ゲートが保有している間は保守タイマーが触らない**
単一オーナー制に整理した。

```lua
if self.obstacle_map_route_pending and #self.obstacle_map_route_pending > 0 then
    if self.route_corridor_timer == nil then
        -- ゲートが居ないときだけ、残りを保守タイマーが拾う
        self:DrainRouteCorridor(budget_s)
    else
        route_settled = false   -- ゲートが流し中。自分は触らない
    end
end
```

---

## 4J. fix (8)：障害物マップ学習のユーザー設定化（今回実装）

### 背景

マップ更新（32 レイ走査 → diff 書き込み）は本質的に**マップ作成者向け**機能。
同梱マップ（96 chunk / 36MB / 2,625,381 cell）が既に市街地をカバーしており、
一般プレイヤーが書き込む必要はない。

適用前は `DAV.debug_enable_obstacle_scan`（`init.lua`、既定 false）のみで制御され、
**デバッグメニューからしか切り替えられなかった**。

### 追加した設定

| 項目 | 場所 | 既定値 |
|---|---|---|
| `is_enable_obstacle_recording` | `user_setting_table`（`/DAV/advance` にトグル） | **false** |

判定はユーザー設定とデバッグフラグの **OR**。既存の開発者運用は壊さない。

```lua
function Navigation:IsObstacleRecordingEnabled()
    return (DAV.user_setting_table.is_enable_obstacle_recording and true or false)
        or (DAV.debug_enable_obstacle_scan and true or false)
end
```

- `StartObstacleRecording()` が OFF なら即 return
  → 5Hz の 32 レイ走査・ periodic diff 保存（150 tick ごと）が一切走らない
- `av.lua` の搭乗時 auto-start もこの判定に統一
- 設定画面から切り替えると**搭乗中でも即反映**（ON→搭乗中なら開始／OFF→停止）

### 記録ホットパスの数値キー化（fix (2) の残骸）

`RecordObstacleScan()` のレイステップが文字列でセルキーを構築していた。

```lua
-- 旧
local ck = math.floor((pos.x + nd.x * step_d) / cs) .. "_" .. ...
-- 新
local ck = self:PackCellKey(
    math.floor((pos.x + nd.x * step_d) / cs),
    math.floor((pos.y + nd.y * step_d) / cs),
    math.floor((pos.z + nd.z * step_d) / cs))
```

旧実装は `NormalizeCellKey()` が数値に正規化するため**動作は正しかった**が、
「文字列を組み立てて再度パースする」無駄が記録系に残っていた。
該当 3 箇所（レイステップ 2 箇所 ＋ `string.format("%d_%d_%d", ...)` 1 箇所）を解消。

### 追加テスト（`tools/resident_cache_test.lua` 1b）

- 充填ゲートが閉じている間、チャンクデータが 1 つもロードされないこと
- `StartObstacleMapFill()` がゲートを開く／二重呼び出しは no-op
- 学習が既定 OFF であること
- ユーザー設定で ON にできること
- デバッグフラグでも ON になること

**テスト結果: 65 passed, 0 failed**（従来 58 ＋ 新規 7）

---

## 4K. fix (9)：`SessionStart` の `io.popen` がロード直後に 1 秒食っていた（真因）

### fix (7) では改善しなかった

ウィンドウ充填を遅延しても「ロード後すぐのカクつき」は残った。
そこで**実機のログ**を直接検証した。

### 証拠

`DriveAerialVehicle.log` の全セッションで、

```
Session start detected  →  cache started
```

の差が一貫して **約 1 秒**。

| 時刻 | PID | 差 |
|---|---|---|
| 23:41:59 | 5216 | 1s |
| 00:33:55 | 35372 | 1s |
| 00:43:22 | 5736 | 1s |
| 01:04:02 | 3272 | 1s |
| 11:54:44 | 32584 | 1s |
| 11:56:38 | 31476 | 1s |
| 12:03:33 | 32584 | 1s |
| 12:07:22 | 31496 | 1s |
| 12:08:58 | 32116 | 0s |
| 16:56:42 | 33704 | 1s |

fix (7) 適用後の `StartObstacleMapSessionPreload()` は**在庫表作成だけ**しかしていない。
つまりこの 1 秒は **`io.popen` の起動コスト**。

### 見落としていた点

`GetAllChunksCached()` は **`io.popen` を 2 回**呼んでいた（`chunk_*.dat` 用と `chunk_*.diff` 用）。
= `cmd.exe` を 2 回起動。

テスト環境（アイドルディスク）では 31ms だったが、**ロード直後でディスクが忙しい実機では 1 秒**。
fix (4) で autopilot 経路から popen を消したとき、「1 回きりだから許容」と残した箇所が
まさにこれだった。

### 対策（2 段構え）

**① popen を廃止し `io.open` プローブに置換**

```lua
-- 旧: cmd.exe を 2 回起動
local pipe = io.popen('dir /b "' .. dir_win .. '\' .. pattern .. '" 2>nul')

-- 新: プロセス起動なし。±20 chunk（片道 10km）を直接叩く
local range = self.obstacle_map_probe_range or 20
for cx = -range, range do
    for cy = -range, range do
        local dat = io.open(info.path, "rb")
        if dat then dat:close() info.has_dat = true end
        local diff = io.open(info.diff_path, "rb")
        if diff then diff:close() info.has_diff = true end
        ...
    end
end
```

実測：4205 名ぶんの `io.open` プローブで **26ms**。プロセス起動なし。

**② 在庫表自体を `SessionStart` から外す**

`EnsureChunkInventoryFresh()` を新設し、**実際に必要になった最初の時点**
（autopilot 回廊 or 記録セッション）で 1 回だけ作る。

```lua
function Navigation:StartObstacleMapSessionPreload()
    -- 重い処理はもう何もない。以前はここで在庫表を io.popen で作っており、
    -- ロード直後に 1 秒かかっていた。
    self.obstacle_map_cache_started = true
    return self.av_obj.core_obj:EnsureObstacleMapPreloadTimer(...)
end
```

### 実測（fix (9) 適用後）

| 処理 | 適用前（実機） | 適用後 |
|---|---|---|
| `StartObstacleMapSessionPreload()` | **約 1 秒** | **0.0 ms** |
| ロード後 14 秒間の保守 280 tick | — | p50/p90/p99 **0.00ms**、8ms 超 **0.00%** |
| 遅延在庫表作成（初回 autopilot 時） | — | **30 ms** |
| 充填中 | — | p50 4ms / p99 7ms |
| 定常 | — | 8ms 超 **0.00%** |

### 残存する既知の重い処理（未対応）

`Core:Init()` に **100Hz ループ**が残っている。

```lua
Cron.Every(DAV.time_resolution, function()   -- 0.01s
    self.event_obj:CheckAllEvents()
    self:GetActions()
end)
```

これは障害物マップと無関係に常時走る。`GetActions()` は毎 tick
`local move_actions = {}` を確保し、中身が `Nothing` でも
`OperateAerialVehicle(move_actions)` を呼ぶ。
実機でまだカクつく場合、次の調査対象はここ。

### デプロイ状態

- インストール先 `Modules/navigation.lua` を更新（バックアップ: `navigation.lua.bak`）
- `init.lua` はユーザーの A/B テスト状態（onInit コメントアウト）を保持
- 実機で MOD を再度有効化して確認が必要

---

## 4L. fix (10)：回廊ストリームのデューティ比を 75% → 16% に低減（今回実装）

### 症状

fix (9) でロード直後は安定したが、**初回 autopilot 開始直後にフリーズのような挙動**。

### 原因

回廊ローダの予算設定が、ホバー時間を短くする方向に振り切りすぎだった。

```lua
obj.obstacle_route_load_budget_ms = 15.0
obj.obstacle_route_tick = 0.02
```

**15ms / 20ms = デューティ比 75%。**
60fps のフレーム予算は 16.7ms なので、レンダリングスレッドがほぼ枯れる。
待機自体は 0.4 秒程度でも、体感では「カクッ → フリーズ」。

### 実測（`tools/corridor_duty_probe.lua`）

| 設定 | デューティ | 0.6km | 1.5km | 2.8km |
|---|---|---|---|---|
| 旧 15ms/20ms | **75%** | 0.14s | 0.34s | 0.42s |
| **現行 8ms/50ms** | **16%** | 0.70s | 1.60s | 2.00s |
| 4ms/50ms | 8% | 1.35s | 3.20s | 3.95s |

### 変更

```lua
obj.obstacle_route_load_budget_ms = 8.0   -- 15.0 から
obj.obstacle_route_tick = 0.05            -- 0.02 から（保守タイマーと同一周期）
```

tick を 0.05 に統一したことで、目覚め回数も 2.5 分の 1 に減っている。

### タイムアウトとの整合確認

1 chunk あたり実測 約 52ms。

- 最悪ケース（32 chunk 上限 = 約 16km）: 32 × 52ms ≒ 1.7s の仕事
- 8ms/tick で 209 tick × 50ms = **10.4s** → `obstacle_route_wait_timeout = 15s` に収まる

よって partial へのフォールバックは起きない。

### 未対応として残した既知項目

`StartRouteCorridorPreload()` はクリック同期で `EnsureChunkInventoryFresh()` を呼ぶ。
在庫プローブは **約 30ms**（`io.open` 3362 回、プロセス起動なし）で、
**autopilot を押した瞬間に 1〜2 フレーム落ちる**。

`ParseChunkIncremental` はファイル欠損を安全に処理するため、
在庫表なしで回廊を組む（＝座標から `chunk_info` を合成する）ことで消せるが、
意味の変更を伴うため今回は見送った。実機で気になるようなら次に対応する。

### 見送りした代替案：フレーム追従型予算

`onUpdate(delta)` の移動平均から「実際に余っているフレーム時間」を推算し、
毎 tick の予算を `spare × 0.5` で自動調整する方式。

- 余裕があるとき: 予算を大きく取れてホバーが短い
- 重いシーン: 予算が 0 に近づき、こちらのカクつきは加算されない
- 既にカクついている: 完全に引っ込む（最低 0.5ms で進行は維持）

固定値で妥協した分を回収する仕組みなので、8ms/50ms でstill気になるなら次はこの方式へ。

---

## 4M. fix (11)：ディレクトリスイープの廃止（on-demand 存在確認）

### 着眼点

fix (10) でフリーズは消えたが、初回 autopilot の **① 在庫スイープ（`io.open` 3362 回）**が
ユーザーから「一番怪しい」と指摘された。実測して検証した。

### 実測：`io.open` のコスト分解

| 操作 | 1 回あたり |
|---|---|
| MISS（ファイル無し） | **7.5 µs** |
| HIT（open+close のみ） | 13.5 µs |
| HIT（open + 64KB read + close） | 28.5 µs |

| スイープ範囲 | 名前数 / open 数 | 合計 |
|---|---|---|
| ±20（当时的） | 1681 / **3362** | **30.0 ms** |
| ±12 | 625 / 1250 | 11.0 ms |
| ±8 | 289 / 578 | 6.0 ms |

MISS でも 1 回 7.5µs の**実カーネル syscall**。ご指摘のとおり無駄なカーネル仕事だった。
しかもこれは AV 非干渉環境で、Defender のリアルタイムスキャン下ではさらに悪化しうる。

### 核心の発見

**1.5km ルートで実際に使う chunk は 3 個（回廊）＋ 25 個（窓）= 約 28 個。**
3362 個調べて 28 個しか使っていなかった。

ファイル名は座標から完全に決まる（`chunk_<cx>_<cy>.dat`）ので、
**使う分だけ調べれば足りる**。

### 実装

```lua
--- Chunk file names are fully determined by the chunk coordinates, so there is
--- no need to list the directory.
function Navigation:MakeChunkInfo(cx, cy)
	local key = cx .. "_" .. cy
	if g_all_chunks_by_key == nil then g_all_chunks_by_key = {} end
	local info = g_all_chunks_by_key[key]
	if info then return info end          -- 判定済み、再調査しない
	info = { ... }
	local dat = io.open(info.path, "rb")
	if dat then dat:close() info.has_dat = true end
	local diff = io.open(info.diff_path, "rb")
	if diff then diff:close() info.has_diff = true end
	g_all_chunks_by_key[key] = info
	if g_all_chunks_cache then g_all_chunks_cache[#g_all_chunks_cache + 1] = info end
	return info
end
```

| 場所 | 変更 |
|---|---|
| `PrepareRouteChunks` | 冒頭の `GetAllChunksCached()` を削除。ループ内で `MakeChunkInfo(cx, cy)` |
| `EnsureResidentChunks` | 在庫 96 件の走査 → **窓の 25 座標を直接**イテレート |
| `StartRouteCorridorPreload` | `EnsureChunkInventoryFresh()` を削除 |
| `StartObstacleMapFill` | 在庫スイープなし |
| `EnsureChunkInventoryFresh` | **削除**（不要になった） |
| `GetAllChunksCached` | 残す。`MakeChunkInfo` を sweep 範囲分呼ぶ形に統一。**`FindNearestObstacleMapChunk` からのみ**遅延構築される |

`has_dat`/`has_diff` は楽観値ではなく**実際に開いて判定**するため、既存の住居判定セマンティクスは不変。

### 実測（`tools/first_autopilot_breakdown.lua`、`io.open` を計装）

| フェーズ | 時間 | io.open | io.popen |
|---|---|---|---|
| **CLICK** `PrepareRouteChunks` | **0.000 ms** | **6** | 0 |
| HOVER 回廊ストリーム | 235 ms / 26 tick = 1.30s | 3 | 0 |
| WINDOW 半径2 充填 | 1261 ms / 342 tick = 17.1s | 66 | 0 |
| STEADY 保守 | 0.01 ms/tick | 0 | 0 |

参考：フルスイープ 28.0 ms / 3362 open

**クリック同期コスト 28.0 ms → 0.000 ms、`io.open` 3362 → 6 回。**
6 回 = 回廊 3 chunk × 2（.dat / .diff）の存在確認のみ。

### 残る仕事の内訳

初回 autopilot 合計 1496ms の内訳は **corridor 235ms ＋ window 1261ms**。
どちらも予算内で分割実行され、定常状態は 0.01ms/tick・ファイルアクセス無し。

ウィンドウ充填（全体の 84%）は 3ms/50ms = デューティ 6% でカクつきは発生していないが、
**ルートが実際に必要としたデータの約 5 倍**である点は未解消。
学習 OFF の一般ユーザーには過剰なので、必要なら「学習 OFF なら充填しない」案が残っている。
