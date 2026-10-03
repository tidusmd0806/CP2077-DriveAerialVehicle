# DriveAerialVehicle パフォーマンス改善計画

作成日: 2026-09-25
対象バージョン: 3.2.2 (game 2.13 / CET 1.36 / Codeware 1.17)
※ 本ファイルの fix 1〜30 は「1回あたりのコスト削減」。
   残る「そもそも発火させない」軸の計画は `PERF_PLAN_event_driven.md` 参照（B群・§1.5・C群・A群・D群すべて実装済み）。
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

テスト（`tests/run_resident_cache_test.py`）で実際に検出・修正したもの：

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

`tests/run_resident_cache_test.py`（`pip install lupa` が必要）で実行できる。
実際の `Modules/navigation.lua` を Lua 5.4 上で動かし、実 `Data/map` に対して検証。

```
python tests/run_resident_cache_test.py     # 42 passed, 0 failed
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

`tests/diagnose_route_unknown.lua` に実設定値による解析を追加：

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

適用前は `DAV.is_debug_enable_obstacle_scan`（`init.lua`、既定 false）のみで制御され、
**デバッグメニューからしか切り替えられなかった**。

### 追加した設定

| 項目 | 場所 | 既定値 |
|---|---|---|
| `is_enable_obstacle_recording` | `user_setting_table`（`/DAV/advance` にトグル） | **false** |

判定はユーザー設定とデバッグフラグの **OR**。既存の開発者運用は壊さない。

```lua
function Navigation:IsObstacleRecordingEnabled()
    return (DAV.user_setting_table.is_enable_obstacle_recording and true or false)
        or (DAV.is_debug_enable_obstacle_scan and true or false)
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

### 追加テスト（`tests/resident_cache_test.lua` 1b）

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

### 実測（`tests/corridor_duty_probe.lua`）

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

### 実測（`tests/first_autopilot_breakdown.lua`、`io.open` を計装）

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

---

## 4N. fix (12)：final_local の障害物密集地スタック（今回実装）

### 症状

`final_local` で目的地に近づくとき、周辺に障害物が多いと**近づいては離れを繰り返してスタック**する。

### 原因

`ComputeLocalAvoidanceDirection` は反発場（repulsion field）导航：

```lua
local goal_weight = 1.5
local nav_x = dest_dir.x * goal_weight + rep_x
```

**目的地引力 1.5 と障害物反発が釣り合う**と、AV は近づいては押し戻されるループに入る。

さらに悪いことに、stuck-escape の上昇退避は**目的地付近では意図的に無効**：

```lua
if (not near_final_local_goal) and self.local_avoidance_stuck_timer >= ... then
```

これは「到着直前に緊急上昇しないため」の正当な処置だが、結果として**このループを抜ける手段が何もなくなる**。

### 対策：無進捗ウォッチドッグ

「一定時間近づかないなら、いま居る場所から着陸する」。

```lua
function Navigation:UpdateFinalLocalProgressWatchdog(horiz_dist, current_time)
	local best = self.final_local_best_dist
	local epsilon = self.final_local_progress_epsilon or 1.0
	if best == nil or horiz_dist <= best - epsilon then
		self.final_local_best_dist = horiz_dist
		self.final_local_no_progress_since = current_time
		return false, best
	end
	local stalled_for = current_time - (self.final_local_no_progress_since or current_time)
	if stalled_for >= (self.final_local_no_progress_timeout or 10.0) then
		return true, best
	end
	return false, best
end
```

| 設定 | 値 | 意味 |
|---|---|---|
| `final_local_no_progress_timeout` | 10.0 s | これ以上近づかなければ着陸 |
| `final_local_progress_epsilon` | 1.0 m | 「進んだ」とみなす最小距離 |

`epsilon` が無いと、数 cm のドリフトで毎回リセットされ**永遠に発火しない**。
逆に大きすぎると実際の進捗を見逃す。1.0m が妥当。

### リセット箇所

`autopilot_phase = "final_local"` になる 3 箇所すべてと `InterruptAutoPilot()` で
`ResetFinalLocalProgressWatchdog()` を呼び、**ハンドオフ時点から時計を始める**。

- 既知セル皆無のフルローカル回避開始
- 目的地周辺に既知セルが無い場合のフォールバック
- `astar -> final_local` ハンドオフ
- `InterruptAutoPilot()`

### テスト（`tests/resident_cache_test.lua` セクション 9）

| ケース | 期待 |
|---|---|
| 安定して近づき続ける（40 秒） | 発火しない |
| epsilon 内での振動 | タイムアウト後に発火 |
| 実際の進捗（10m 前進）後 | 時計がリセットされ 12s では発火しない → 14s で発火 |
| リセット後 | 新品の距離がベースラインになる |

---

## 4O. fix (13)：autopilot 中のメータが km/h と距離で高速点滅（今回実装）

### 症状

自動操縦中はメータが「距離」表示になるのが期待値だが、**km/h と距離が高速に切り替わる**。

### 原因 1：単位変換の誤用

`CheckHUD()` は残距離（メートル）を `SetSpeedMeterValue()` に渡していたが、
この関数は**常に m/s → km/h の変換を行う**：

```lua
speed_value = speed_value * 3.6   -- m/s to km/h
```

残距離 100m が **360** と表示されていた。

### 原因 2：上書きガードが C# 呼び出しに依存

```lua
Override("hudCarController", "OnSpeedValueChanged", function(_, speedValue, wrappedMethod)
    if not DAV.core_obj.event_obj:IsInVehicle() or not self.is_manually_setting_speed then
        result = wrappedMethod(speedValue)   -- ゲーム本体が km/h を描画
    end
```

`IsInVehicle()` は `AV:IsPlayerIn()` → `entity:IsPlayerMounted()`（C# round trip）を含む。
**一瞬 false を返すとゲーム本体の描画が通ってしまい**、我々の距離表示と交互になって点滅する。

### 対策

**① 変換なしの専用セッタを追加**

```lua
--- While autopilot is up this shows remaining distance, which is already in the
--- unit we want to print. Running it through SetSpeedMeterValue would multiply
--- the metres by 3.6 as if it were m/s.
function HUD:SetDistanceMeterValue(distance_value)
    ...
    inkTextRef.SetText(self.hud_car_controller.SpeedValue, math.floor(distance_value))
end
```

**② ガードを C# 呼び出しなしの状況判定に変更**

```lua
--- Situation check with no C# round trip. The meter overrides fire on every speed
--- and rpm change event, so they must not depend on IsPlayerMounted().
function Event:IsInAVSituation()
    return self.current_situation == Def.Situation.InVehicle
end
```

`OnSpeedValueChanged` / `OnRpmValueChanged` 両方に適用。
`is_manually_setting_speed` は搭乗時 true・降車時 false で正確に追従しているため、
`IsPlayerMounted()` を条件から外してもセーフティは保たれる（かつ C# 往復も消える）。

### テスト結果

**76 passed, 0 failed**（新規 11 件追加）／ 19/19 コンパイル OK

---

## 4P. fix (14)：autopilot 中の速度メータは通常どおり速度を表示（今回実装）

### 方針転換

`ToggleOriginalMPHDisplay` で単位ラベルを距離表記に差し替える試みは、**ゲーム側が
ラベルを継続的に書き換えているため根本的に勝ち目がなかった**。

戦うのをやめ、次の割り切りにした：

| メータ | 自動操縦中 | 手動時 |
|---|---|---|
| **速度** | **実際の速度**（手動と同じ） | 実際の速度 |
| **RPM** | **進捗ゲージ**（出発 1 → 到着 11） | 実際の RPM |

進捗情報は速度ではなく RPM が担う。既存の RPM 進捗ロジックはそのまま。

### 変更

`Event:CheckHUD()` を「速度は共通・RPM だけ分岐」に整理した。

```lua
-- The game repaints the speedometer unit label on its own, continuously, so
-- swapping it to a distance unit during autopilot just fights the HUD and
-- flickers. Show the real speed in both modes and let the RPM dial carry the
-- autopilot progress instead.
self.hud_obj:ToggleOriginalMPHDisplay(false)
local current_speed = self.av_obj:GetCurrentSpeed()

if self:IsAutoMode() then
    self.hud_obj:EnableManualMeter(true, true)
    self.hud_obj:SetSpeedMeterValue(current_speed)
    ...
    -- RPM is the autopilot progress gauge: 1 at departure, 11 on arrival.
    self.hud_obj:SetRPMMeterValue(math.floor(10 * (1 - current_length / initial_length) + 1))
else
    self.hud_obj:EnableManualMeter(true, self.av_obj.is_enable_manual_rpm_meter)
    self.hud_obj:SetSpeedMeterValue(current_speed)
    self.hud_obj:SetRPMMeterValue(math.abs(rpm_count))
end
```

`ToggleOriginalMPHDisplay(false)` を分岐の外に出したので、自動操縦中も単位は通常の
mph / km/h のまま。**ゲームが書く値と我々が表示する値が一致する**ので矛盾は起きない。

### 併せて削除

`HUD:SetDistanceMeterValue()`（前回追加した変換なしセッタ）は呼び出し元がなくなり
死んだため削除。`--- Set RPM Meter Value` の docstring が誤位置になっていたのも復した。

### 前回までの HUD 修正で有効だったもの

以下は方針転換後もそのまま有効なので残した：

- **`GetMPHTextWidget()` によるウィジェットキャッシュ** — `dynamic` コンテナの深いパスは
  断片的に失敗していた。キャッシュで C# 呼び出しを削減し、失敗を自己修復化
- **エッジトリガー化** — 書き終えたら二度と書かない。100Hz の無駄な書き込みが消えた
- **失敗ログを Debug → Warning に格上げ** — `MasterLogLevel = Info` のため
  Debug レベルでは**どんな失敗も隐形**だった（今回の調査を長期化させた主因）
- **HUD 再初期化時のキャッシュ無効化** — `OnInitialize` / `OnMountingEvent`
- **降車後のラベル復元** — `CheckHUD` は降車後に走らないため exit 経路で明示

### テスト

**76 passed, 0 failed** ／ 19/19 コンパイル OK

---

## 4Q. fix (15)：障害物マップの全 RAM 常駐（base image 化）（今回実装）

### 問題

fix (9)〜(14) でストリーミング関連のコストは潰したが、**長距離 / 複雑な
autopilot での一時的なフリーズ**と**目的地が到達不能になる問題**は残っていた。
原因はストリーミングではなく **表現形式**そのものにあった。

v3 テキストマップを全ロードすると:

| 項目 | 値 |
|---|---|
| 生データ | 34.98 MB（テキスト） |
| セル数 | 2,625,381 |
| ロード時間 | 5.8〜6.2 秒 |
| ロード後ライブヒープ | **181.9 MB** |
| 1 セルあたり | **約 69 B** |
| GC ライブオブジェクト数 | **約 800 万** |

セル 1 つが「キー文字列 + タブレコード + 値」で数個の GC オブジェクトになる。
バイト数ではなく **GC オブジェクト数**がフリーズの本体だった。

### 対策：1 セル 1 バイトの不変イメージ

`Modules/obstacle_grid.lua` を新規追加し、チャンクを Lua の**不変文字列**
1 本として保持する。

```
off  size  field
0      6   magic  "DAVOB4"
6      1   z_levels
7      1   zmin_bias        (z_min + 128)
8      2   cell_size_cm     (u16 LE)
10     4   known_count      (u32 LE)
14     2   reserved
16     …   body = z_levels * 50 * 50 バイト
```

```
index = 16 + (z - zmin) * 2500 + (sy - chunk_sy * 50) * 50 + (sx - chunk_sx * 50)
```

状態は `0=unknown / 1=clear / 2=danger / 3=blocked`。
v3 からの写像は `0→clear, 1→danger, >=2→blocked`。

- 全チャンク常駐で **96 画像 + 96 レコード + 索引 1 個 ≒ 200 GC オブジェクト**
  （800 万 → 200）
- ロードはチャンクあたり `read("*a")` 1 回。セル単位の Lua パースはゼロ
- z は固定窓 `[-4, 127]`（132 層）で統一し、チャンク毎の再写像を排除
- チャンクキーは整数 `((cx+512)*1024)+(cy+512)`。文字列連結なし

### 読み書きの分離

- **base image（不変）**：出荷済みマップ。`obstacle_grid`
- **learned overlay（可変）**：走行中に学習したセルだけを持つ `obstacle_map`

読み取りは `Navigation:CellStateAtKey(key)` に集約し、
**learned → base image** の順で解決して従来の値域
（`true` / `"danger"` / `false` / `nil`）に変換する。

書き込みは `CellStateAtKey` の**実効状態**と比較するため、
「障害物を clear に降格しない」規則は base image に対しても成立する。

`learned_count` が 0 のときは overlay lookup を丸ごと飛ばす。
A* の最熱経路で必ず外れるハッシュ検索が消えるため、これ単体で数 % 効く。

### 既知セルの走査は索引を持たせない

「チャンク内の既知セル全部」が要る経路（最近傍探索など）のために
索引を持つと、260 万要素の Lua 配列で **42 MB** になった。
そこで索引を廃し、画像を直接 `"find(\"[^%z]\")"` で歩く。
未知セルの連続は C レベルのスキャン 1 回で飛ぶため、コストは許容範囲。

> **はまった点**：走査開始を `1` にするとヘッダの非ゼロバイトを
> 「セル」として拾う。ヘッダの `0x03`（cell_size 上位）が
> **負の index の blocked セル**として復号され、存在しないはずの
> 障害物が最近傍探索に混入した。開始位置は必ず `BODY_BASE`。

### 学習セルのフラッシュ

`obstacle_map_learned_flush_cells`（既定 200,000）を超えると、
脏チャンク 1 個の学習セルを base image に畳み込み、`.bin` に永続化して
overlay から除去する。fold 時に `known_count` と状態集計のキャッシュを更新。

### ストリーミングは無効化

全常駐時は `IsFullResidencyActive()` が true になり、以下はすべて no-op：

- `EnsureResidentChunks`
- `PrepareRouteChunks`（回廊プリロード）
- `EvictDistantChunks`
- `MaintainObstacleMapCache`（フラッシュのみ実行して idle を返す）

**未知セル由来の経路失敗が構造的に消える**のが主目的。

### 実測（`tests/run_full_residency_bench.py`）

各表現を**別プロセスで**測定。同一プロセスだと 2 番目の run の GC 状態が
1 番目の free した 180 MB に汚染され、測りたい効果が埋没する。

| | legacy（v3 テーブル） | packed（base image） |
|---|---|---|
| ロード | 5783 / 6152 ms | **345 / 373 ms**（約 15 倍速） |
| マップライブヒープ | 181.9 MB | **31.4 MB**（5.8 倍小） |
| 読み処理量 | 376 / 436 ns/op | **260 / 280 ns/op**（約 1.5 倍速） |
| GC ライブ | 206.2 MB | 55.8 MB |

GC テール（ワースト設定 `pause=110 stepmul=150 alloc=256KB/tick`）:

| | p99 | p99.9 | max | ≥8ms |
|---|---|---|---|---|
| legacy | 9.07 / 9.34 ms | 15.96 / 15.00 ms | 26.24 / 26.70 ms | **1.29% / 1.25%** |
| packed | **2.17 / 2.00 ms** | **5.76 / 4.62 ms** | **15.59 / 7.91 ms** | **0.05% / 0.00%** |

**8ms 超の発生率が約 25 分の 1**。フリーズの体感要因が消えた。

A* の長距離（4.6 km）は両モードほぼ同等（2.3〜2.7 秒、分散大）。
これは A* 自身の open/closed セットが生成する大量の一時テーブルが支配で、
今回の対象外。ルートは全経路で**旧実装とノード列が完全一致**。

### 学んだこと（次回の指針）

- **Lua のメモリ問題はバイト数ではなく GC オブジェクト数で測る。**
  181 MB / 800 万オブジェクト → 31 MB / 200 オブジェクトでテールが消えた
- **不変データは `string` に限る。** 読み取りは `string.byte` で、
  GC の対象にならない
- **互換値域を保つファサードはタダではない。** `get_packed` 経由の
  二段ディスパッチは A* で数 % 効いたので、最熱関数にはインライン展開した
- **`z < 0` の早期 return はマップを実際に確認してから書く。**
  本マップは z = -3 を含み、20 万サンプル中 432 セルが黙って消えた
- **ベンチはプロセスを分けないと意味がない。** 同一プロセスの 2 番目は
  前の GC 断片化を測っている

### テスト

- 新規統合テスト `tests/grid_integration_test.lua`（**52 passed, 0 failed**）
  - base image ロード / 全常駐 / 96 チャンク
  - 旧テキストローダとの 20 万セル一致
  - learned の優先、降格拒否（base image に対しても）
  - eviction / 回廊の不活性
  - A* ルートの完全一致（2.8 / 6.4 / 4.6 km）
  - 最近傍探索が**ファイル open ゼロ**で RAM から解決
  - フラッシュ → 書き出し → 再ロードで学習内容が生存
  - セッション破棄でイメージ解放
- 既存回帰 `tests/run_resident_cache_test.py`（**76 passed, 0 failed**）
- 全 20 Lua ファイルコンパイル OK

---

## 4R. 本番投入で mod が初期化不能になった（Lua バージョン取り違え）

### 症状

```
Error: Cannot load module 'Modules/navigation.lua':
  navigation.lua:2641: unexpected symbol near '/'
Modules/av.lua:18: attempt to index upvalue 'Navigation' (a nil value)
```

mod の初期化が完了しなくなった。

### 真因：**CET は LuaJIT（Lua 5.1 セマンティクス）だった**

調査全程でランタイムを **Lua 5.4 だと思い込んでいた**。実際は LuaJIT で、
5.2 以降の構文は**構文エラー**になる。

私が新規追加したコードの 5.4 依存：

| 構文 | 5.4 | LuaJIT / 5.1 | 影響 |
|---|---|---|---|
| `a // b`（整数除算） | ○ | **×** 構文エラー | mod 初期化不能 |
| `table.unpack` | ○ | **×** nil | fold 全滅 |
| `unpack`（素） | ×（削除済） | ○ | — |

`//` は 7 箇所あった：

- `navigation.lua` `CellStateAtKey` ×3
- `obstacle_grid.lua` `get` / `get_packed` / `walk_chunk` ×4

### なぜテストを全部通過したのか（**調査側の欠陥**）

2 重の見逃しがあった。

1. **ランナーが `lupa.lua54` を使っていた**
   → 5.4 でパースしているので `//` が通ってしまう。
   ゲームで落ちるコードがテストでは緑になる。

2. **構文チェックが例外を握りつぶしていた**
   ```python
   lua.eval("function(s) return load(s) end")(src)   # 戻り値を捨てていた
   ```
   Lua の `load` は失敗時に例外を投げず `nil, msg` を**返す**。
   戻り値を捨てているので**永遠に「0 failures」**になる。
   「全 20 ファイルコンパイル OK」は最初から意味をなしていなかった。

### 対策

**構文ゲートを新設：`tools/check_lua_syntax.py`**

- `lupa.lua51` で**実際にコンパイル**し、`compile()` の例外を検知する
- 5.1 で落ちるが LuaJIT が許す `goto` / `::label::` は
  置換してから再パースし、**誤検出せず拡張として表示**
- コメントと文字列リテラルを空白化してからパターン照合
  （`"<< Recording active >>` のような文字列内の `<<` で誤爆した）
- 5.2+ 構文をパターンで弾く：
  `//`、`table.unpack`、`table.pack`、`table.move`、`math.maxinteger`、
  `math.tointeger`、`math.type`、`utf8.`、`<const>`、`<close>`、
  `\x41`、`\z`、16 進浮動小数、ビット演算子

**全テストランナーを `lupa.lua51` に移行**

```python
import lupa.lua51 as lua  # CET runs LuaJIT (Lua 5.1 semantics);
                         # 5.4 would accept code the game rejects
```

テスト側の `preload` も `load(str)` → `(loadstring or load)(str)` に修正
（5.1 の `load` は関数しか取らない）。

### 修正内容

- `//` → `math.floor(a / b)` に全置換
- `string.char(table.unpack(buf, 1, SLICE))` →
  **事前構築した 256 文字テーブル + `table.concat`** に変更

  ```lua
  local CHAR = {}
  for i = 0, 255 do CHAR[i] = string.char(i) end
  ...
  buf[i] = CHAR[v or old]
  local new_slice = table.concat(buf, "", 1, SLICE)
  ```

  `table.unpack` の不在だけでなく、**1 回に 2500 引数を渡す**呼び出し自体が
  LuaJIT では脆い。concat の方が速い。

### 5.1 での再測定の注意

`lupa.lua51` は **C 実装の Lua 5.1** であり LuaJIT ではない。
GC も JIT も別物なので、上の 4Q の絶対値はそのまま当てはまらない。

| | legacy | packed |
|---|---|---|
| ロード | 9289 ms | **415 ms**（約 22 倍） |
| マップライブヒープ | 302.9 MB | **31.9 MB**（9.5 倍小） |
| 読み処理量 | 572 ns/op | **498 ns/op** |

`math.floor` に落としても packed が読み処理量で勝っている。
GC テールは 5.1 の増分 GC が緩く両モード 0.00% で**判別不能**
（5.4 の GC より鋭敏さに差があるため、テールの絶対値はゲーム内で確認する）。

### 学んだこと

- **まずターゲットランタイムを確定させろ。** 「CET = Lua 5.4」という
  思い込みが調査全体を汚染した。`//` を書き始めた時点で気づくべきだった
- **テストが緑であることと、コードが正しいことは別。**
  テストが間違った VM で走っているなら緑は何も保証しない
- **`load` は失敗を返すのであって throw しない。**
  構文チェッカーは戻り値を見ないと**常に成功と報告する**
- **LuaJIT 相手には `table.concat` + 文字テーブルが安全。**
  大量引数の `string.char(unpack(...))` は避ける
- **`goto`/`continue` は LuaJIT 拡張。** 素の 5.1 パーサは弾くので、
  ゲート作る時は除外扱いが必要

---

## 4S. base image が実フローで一度もロードされていなかった

### 症状

`//` を直して再ロードしたところ、autopilot が正しく動かない。
ログに `AutoPilot [start_local]: start in UNKNOWN cell` が並び、
`AutoPilot: streaming 2 corridor chunks before departure` と
`Obstacle map window fill enabled` が出ている
＝ **full residency が有効になっていない**。
しかも `Obstacle map loaded: N base cells ...` のログが一切ない。

### 真因：**`LoadObstacleMap()` は死んだコードだった**

```
$ grep -rn ":LoadObstacleMap()" --include=*.lua .
Modules/navigation.lua:3209:function Navigation:LoadObstacleMap()
```

**呼び出し元がゼロ。** 定義しかない。

私は base image ロードを全部この関数の中に書いた。だから：

- テストは `nav:LoadObstacleMap()` を直接呼ぶので**緑**
- ゲームは別の経路なので base image は**永遠にロードされない**
- `is_base_image_loaded` は false のまま → full residency 不入 →
  従来どおりテキストチャンクのストリーミングが走る
- 窓フィルは初回 autopilot 以降しか始まらないので、
  出発時点の周辺セルが UNKNOWN → ルート選択失敗

### 実際の起動フロー

| 関数 | 役割 |
|---|---|
| `StartObstacleMapSessionPreload` | 起動直後。重い処理はゼロ。タイマー起動のみ |
| `MaintainObstacleMapCache` | **唯一の定期ドライバ**（`Core:EnsureObstacleMapPreloadTimer`） |
| `StartObstacleMapFill` | 初回 autopilot で窓フォロー開始 |
| `ProcessObstacleMapLoadBatch` | 旧 staged preload（キュー駆動） |
| `LoadObstacleMap` | **未使用** |

### 対策：`MaintainObstacleMapCache` を base image のドライバにする

`Navigation:LoadBaseImageStep(budget_ms)` を追加し、
**予算内で少しずつ**チャンクを読み込む。

```lua
if not self.is_base_image_loaded then
    self:LoadBaseImageStep(self.obstacle_base_image_budget_ms or 12.0)
    if self.base_image_pending ~= false then
        return false          -- まだロード中、他のことはしない
    end
elseif self:IsFullResidencyActive() then
    self:FlushLearnedCellsToImage()
    return true
end
```

**ロード完了まで窓フィルを止める**のが要点。先にテキストチャンクを
`obstacle_map` に流入させると、何百万セルが learned overlay に入り、
このモジュールが存在的に消したはずの形に戻ってしまう。

`base_image_pending == false`（＝パックデータ無し）なら
フォールスルーして従来どおりストリーミング。
**ここを `return false` にしたままにすると、パックデータのない環境で
窓フィルが永久に止まった**（既存テスト 8 件が落ちて判明）。

### sweep も予算内に分散

`GetAllChunksCached(true)` は 41×41 = 1681 チャンク × 3 `io.open`
＝ **約 5000 回のファイル open を 1 フレームに落とす**。
これは今回除去してきたヒッチと同種なので、自前のスイープカーソルで
1 回に数行ずつ進めるようにした。

### 出発ゲート

`PrepareRouteChunks` は、まだロード中なら
`FinishBaseImageLoad(1500)` で同期的に終わらせてから出発する。
通常はメンテナンスタイマー（既定 50ms 間隔・12ms 予算）が
**約 1.5 秒で 96 チャンクを読み終える**ので、
プレイヤーが autopilot を押す頃には終わっている。

### 教訓

- **新機能を既存関数に足す前に、その関数が実際に呼ばれているか確認しろ。**
  `grep "関数名()"` 一発で分かる話だった
- **テストが直接呼ぶ経路と、ゲームが通る経路は別物。**
  「テスト緑＝ゲームで動く」ではない。今回 2 回目同じ轍
- 対策として統合テストに **section 13** を追加：
  `LoadObstacleMap` を**一度も呼ばない** nav を
  `MaintainObstacleMapCache` のティックだけで full residency に到達させ、
  96 チャンク・全セルが載ることを検証。
  併せて「パックデータ無しで永久に待たない」ことも検証

### テスト

- 統合 `tests/grid_integration_test.lua` — **66 passed, 0 failed**
- 既存回帰 `tests/run_resident_cache_test.py` — **76 passed, 0 failed**
- 構文ゲート `tools/check_lua_syntax.py` — **20 files, 0 problems**

---

## 4T. A* → final_local の引き渡しが一度も発火していなかった

### 症状

記録外エリアの目的地に向かっても A* がマップ端で止まり、
その先へ進まない／衝突を繰り返す。

### 調査

まず目的地をセルキーから復号した:

```
dest_cell 35248930744585 -> cell (240,-70,9)  world (2400,-700,90)  chunk (4,-2)
マップの chunk x = [-6 .. 2]        ← chunk (4,-2) は存在しない
```

で、**目的地は記録範囲から 1.2km 外**。…だがそれは問題では**なかった**。

**設計上、記録外は「A* の探索境界」にすぎない。**
A* は既知空間のルートを走り、その先は `start_local` と同じ
ローカル回避ロジックで目的地へ向かう。
`start_local` が未知スタートから既知セルまで 391m をローカル回避で走るのと同じこと。

### 真因：`final_local_max_handoff_distance = 150` が引き渡しを止めていた

```lua
if self.autopilot_phase == "astar"
    and self.autopilot_dest_requires_final_local
    and self.route_plan_job == nil
    and self.current_route_index > #self.current_global_route
    and (horiz_to_final <= max_handoff or give_up_on_astar) then   -- max_handoff = 150
```

`horiz_to_final` は**実際の目的地までの水平距離**。今回のケース **1210m**。

- `1210 > 150` → 窓に入らない
- `give_up_on_astar` は「A* が低ゲインで 3 回却下された」時のみ
- ところが今回は A* が**毎回成功**している（解決済みプロキシ＝マップ端
  cell (119,-72,5) まで 7 cell を計画）ので却下も発生しない

→ **エスケープハッチが両方とも閉じて、引き渡しが永久に来ない。**

ログ全体で `astar->final_local` の出現回数は **0 回**。

### さらに悪い二次効果

ルートを使い切ても phase が `astar` のままなので、

```lua
if self.autopilot_phase == "astar" and #self.current_global_route > 0 then
    -- Pure A* waypoint following   ← 障害物回避なしの直進
```

の分岐に入り、`nav_target = final_destination`（＝1.2km 先の実際の目的地）に
**障害物回避ゼロで直進**する。
ログの `Collision Detected` はこれ。

### 修正

**A* がこれ以上計画できない状態**を明示して引き渡し条件に追加した。

```lua
local astar_out_of_road = self.autopilot_dest_is_unknown == true
if self.autopilot_phase == "astar"
    and self.autopilot_dest_requires_final_local
    and self.route_plan_job == nil
    and self.current_route_index > #self.current_global_route
    and (horiz_to_final <= max_handoff or give_up_on_astar or astar_out_of_road) then
```

目的地セル自体が未知なら、ルートを使い切った時点で A* は**文字手上がり**
である。フォローアップを追加しても到達しうるはずがない。
だから距離に関係なく引き渡して、残りは `start_local` と同じローカル回避に任せる。

- 目的地が既知／traversable → 条件に入らない（従来どおり）
- 目的地が未知だが 150m 以内 → 従来どおりの窓で引き渡し
- 目的地が未知で遠い → **新規条件で引き渡し**

ログに `dest-unknown=` を追加して追跡可能にした。

### 教訓

- **「マップ外＝到達不能」ではなかった。** 記録外は A* の境界であって、
  その先はローカル回避が走る。設計を読み違えた
- **上限（cap）を足す時は、その cap に引っかかった時の脱出経路が
  実際に発火するか確認する。** 「低ゲイン 3 回で諦める」は
  A* が成功し続けると一度も来ない
- **ルートを使い切った phase で「障害物なし直進」分岐に入るのは危険。**
  spent route は速やかにローカル回避へ渡すべき

---

## 4U. .dat / .diff から .bin への一元化

### 質問

packed (`DAVOB4`) へ移行したのだから `.dat` / `.diff` は不要では？

### 調査結果：読み込み側は不要、書き込み側にギャップがあった

| ファイル | 役割 | residency 下で**読む** | **書く** |
|---|---|---|---|
| `.bin` | packed base image | **YES（これだけ）** | YES（学習 fold） |
| `.dat` | legacy v3 テキスト base | **NO**（dead `LoadObstacleMap` の fallback 内のみ） | `IntegrateObstacleMapDiff` のみ |
| `.diff` | 追記専用の学習差分 | **NO** | **YES（`SaveObstacleMap` が今も追記）** |

`.dat` の読み出し経路は `LoadObstacleMap`（呼び出し元ゼロの dead code）に
しか存在しない。よって**読み込み側で `.dat` は完全に不要**。

**ただし `.diff` は「書かれるのに読まれない」状態になっていた。**

### 実際のデータ損失ギャップ

```
記録 → obstacle_map (overlay) + dirty_cells
        ├─ SaveObstacleMap()        → .diff に追記   ← 書く
        └─ FlushLearnedCellsToImage → .bin に fold   ← 条件付き
```

`FlushLearnedCellsToImage` は `.bin` を持つ chunk だけ選別していた：

```lua
if n > 0 and self.obstacle_grid:has_chunk(cx, cy) and ...
```

そして `fold_cells` は：

```lua
if c == nil or cells == nil or #cells == 0 then return false end
```

**＝新規 chunk を作れない。**

結果、**packed 範囲外に記録した障害物は `.diff` にしか存在せず、
`.diff` は residency 経路で読まれないので再起動時に失われていた。**

なお既存の `.diff` 2 個（`chunk_-4_-1`, `chunk_-4_-6`）はどちらも packed
範囲内だったので、現時点での実害はなかった。

### 修正

**1. `ObstacleGrid:new_chunk(ccx, ccy, zlo, zhi)`** — 空 chunk を新設

z 窓は呼び出し側のセルに合わせて**タイトに**作る。デフォルト全 132 レベル
（330KB）ではなく、疎なチャンクは KB 単位で済む。

**2. `ObstacleGrid:ensure_z_range(c, zlo, zhi)`** — z 窓の成長

後から高い高度のセルが来たら、前面/背面にゼロスライスを挿して拡大する。
窓外のセルは UNKNOWN と読めるため、拡大しないと黙ってデータを落とす。

**3. `fold_cells` が欠損チャンクを新設／既存は成長させる**

**4. `Navigation:FoldDirtyChunkToImage(chunk_key)`** — 永続化の単一路径

fold + `save_chunk` + overlay クリア + マニフェスト更新を 1 箇所にまとめた。

**5. `FlushLearnedCellsToImage` から `has_chunk()` フィルタを削除**

**6. `SaveObstacleMap` は residency 下で `.bin` に fold し、`.diff` を書かない**

```lua
if self:IsFullResidencyActive() then
    for ck in pairs(self.obstacle_map_dirty_cells) do
        local n = self:FoldDirtyChunkToImage(ck)
        ...
    end
    return
end
```

**7. マニフェストへの新チャンク登録**

`ReadBinManifest` が `bin_manifest_set` を保持し、新チャンクが出たら
`RewriteBinManifest` で書き戻す。ヘッダの count も真値に保つ。

### はまった点

`RewriteBinManifest` が**内部キー形式 `40_40` のまま書き出し**、
`ReadBinManifest` が期待する空白区切り `40 40` をパースできないという
バグを作った。ヘッダ count は 97 になるのに中身が読めず、

```
[FAIL] manifest lists the new chunk
[FAIL] reloaded nav sees 97 chunks  got 96
```

と分かりにくい形で出た（sweep フォールバックが 96 を見つけてしまったため）。
`k:gsub("_", " ")` で修正。

### 残すもの

- **`.dat` は repo に保持**。`tools/mapbin_pack.py` の入力であり、
  これが無いとマップの再生成・拡張ができない
- 配布物（ゲームフォルダ）からは外せる
- `.diff` への書き込みは residency 下では止まるため、肥大化しない

### テスト

`tests/grid_integration_test.lua` section 15（20 項目追加）:

- grid レベル: 新設 / タイトな窓 / known 計上 / 窓成長 / 既存セル保持
- nav レベル: packed 範囲外への記録 → `.bin` 書き出し → overlay ドレイン
  → マニフェスト更新 → **別 nav で再ロードして同じ値が読める**
- residency 下で `.diff` が書されないこと

```
統合       : 101 passed, 0 failed
既存回帰   : 76 passed, 0 failed
構文ゲート  : 21 files, 0 problems
```

---

## 4V. 実行時を packed のみに統一（テキスト形式の削除）

### 動機
`Data/map_bin` + `manifest.txt` が本番化して以降、`.dat` / `.diff` は実行時に
**一切読まれていない**。残っているのは観測上のノイズと、誤作動の危険だけだった。

特に危険だったのが `IntegrateObstacleMapDiff`。`obstacle_map` から `.dat` を
**書き直し**、その後 `.diff` を `os.remove()` する。full residency 下では
`obstacle_map` は学習オーバーレイ（数千セル）しか持たないので、これを呼ぶと
  - 完全なベース・スナップショットが数セルに縮み
  - まだ統合されていない `.diff` の差分が削除される
実際に `.diff` に 42 セルが `.bin` 未統合で残っており、消えると恒久損失だった。

### 削除したもの（`Modules/navigation.lua` から 398 行）
| 関数 | 理由 |
|---|---|
| `LoadObstacleMap` | 呼び出し元ゼロ（死コード）。テキスト一括ロード |
| `LoadObstacleMapChunkFile` | 同上のチャンク版 |
| `BuildObstacleMapLoadQueue` | ストリーミング用キュー構築 |
| `ProcessObstacleMapLoadBatch` | 1 バッチ=1 ファイルのテキスト解析 |
| `IntegrateObstacleMapDiff` | **破壊的**。上記 |
| `EnsureResidentChunks` | 窓方式のウィンドウ充填 |
| `EvictDistantChunks` | 窓方式の退避 |

`Debug/debug.lua` の `Integrate Diff -> Base` ボタンも削除。

### 簡素化したもの
- `MakeChunkInfo` — `.bin` だけを調べる。`path` / `diff_path` / `has_dat` /
  `has_diff` / `probed` を廃止。1 チャンク 3 回だった `io.open` が 1 回に。
- `GetAllChunksCached` — `has_bin` のチャンクのみ返す。
- `MarkChunkOnDisk(chunk_key)` — 引数簡素化。
- `MaintainObstacleMapCache` — packed のみ：
  未ロードなら `LoadBaseImageStep`、済なら学習フラッシュして `true`。
  窓追従・退避・廊下ドレインは無し。
- `packed_chunks()`（`mapbin_pack.py`）— `.dat` に `.diff` を**マージしてから**
  パックする。順序はセル単位で diff 優先。

### packed が無い場合の挙動
従来は「テキストへフォールバック」。今は **明示エラー**：

```
NO PACKED OBSTACLE MAP: no chunk_*.bin found under Data/map_bin
Run tools/mapbin_pack.py --src Data/map --dst Data/map_bin --zmin -4 --zmax 127
```

フォールバック先が無いことを隠さず、対処方法をそのまま出す。

### 残る `.dat` の位置づけ
`mapbin_pack.py` の**入力専用**。配布物には含めなくてよい。
実行時は読まない。ライブの `Data/map` に残る 2 個の `.diff` も、
内容はすでに `.bin` へ統合済みなので削除して問題ない。

### テストへの影響
`resident_cache_test.lua` は窓方式の回帰テストだったため、廃止セクション
（窓充填・退避・廊下プリロード）を除去し、有効な 4 セクションに再構成：
inベントリ列挙 / セルキー往復 / 頑健性 / プロセス起動ガード / watchdog。
ランナーは packed を用意して `obstacle_map_bin_dir` を明示的に渡す
（既定値 `Data/map_bin` はゲームの CWD 基準なので、ハーネスでは解決できない）。

`grid_integration_test.lua` は 16 番を「破壊的パスが存在しないこと」の
構造ガードに置き換えた。

### 構文ゲートの網羅性を改善
`tools/check_lua_syntax.py` の既定対象が mod ディレクトリだけで、
`tools/*.lua` が検査外だった。テスト Lua も実 LuaJIT なので追加したところ、
即座に `#` コメント（Python 記法）の混入を検出した。
加えて遺棄プロトタイプ 3 ファイルの `//` と `table.unpack` を修正。

**40 ファイル / 0 問題**

### 最終テスト状態
| 実行 | 結果 |
|---|---|
| `python tools/check_lua_syntax.py` | 40 files, 0 problems |
| `python tests/run_grid_integration_test.py` | 101 passed, 0 failed |
| `python tests/run_resident_cache_test.py` | 33 passed, 0 failed |
| `python tests/run_grid_integration_test.py probe_smoke.lua` | 15 passed, 0 failed |

---

## 5. `visualize_obstacle_map.py` — 点群からソリッド面へ

### 問題
衝突セルを点で描いていたため、建物も地形も「赤い霧」にしか見えなかった。
地図作りには「あの塊がビルで、この隙間が通路」と立体で読み取れる必要がある。

### 対応：ボクセル表面の抽出
衝突セル集合の**外皮だけ**を出した。埋まったセルと空のセルの境目の面のみ生成
するので、 solidity なブロックの内部はコストゼロ。

| | 点描画 | 面描画 |
|---|---|---|
| blocked 410,579 cell | 41 万点 | **921,090 quad** |
| danger 933,962 cell | 93 万点 | **801,806 quad**（除外後） |

抽出は numpy で 0.11 秒、全体のレンダリングは 2 秒。

### 実装で注意した点
- **面の向き（winding）を面ごとに決めている。** 一様な winding にすると
  半分くらいの面が内側を向いて、光源下で黒く潰れ、建物に穴が開いている
 ように見えた。
- **`moveaxis(1, 0)` は奇置換**なので、軸 0・2 と外積の符号が反転する。
  3 軸共通の規則にはできず、軸ごとの表になっている。
- **danger シェルは建物に接する面を除外**した。建物の面と同一平面上に
  重なるため z-fighting の原因になる。除外で quad は 1,690,837 → 801,806 と
  半減し、描画も軽くなった。
  （blocked と danger はセルが重複しないので、マスクから抜くのでは不十分で、
   **面レベル**で除く必要がある。）

### 追加したオプション
```
--mode surface|points|both    既定 surface。points は従来の点群
--danger-style shell|edges|off  no-fly 体積の見え方
--danger-opacity A            シェルの不透明度（既定 0.10）
--zmin M --zmax M             高度帯でスライスして一層だけ見る
--flat-color                  高度ランプをやめて単色赤
--edges                       面にワイヤーフレームを重ねる
--no-ground                   z=0 基準グリッドを消す
--focus-route                 カメラをルートに寄せる
--offscreen                   ウィンドウを開かずレンダリング
```

### 効果が高かったもの
- **高度カラーランプ**。低い所を濃い赤、高い所を明るいクリームに。
  最初は低い所をスレート青にしていたが、地上レベルの障害物が
  「背景の地形」に見えて障害物だと分からなくなった。赤系で統一して解決。
- **`--zmin/--zmax` のスライス**。100〜300m で見ると、タワー群・高架道路・
  円形構造物など中層の構造がはっきり読める。
- **`--focus-route`**。地図が約 6km あるため 900m のルートは点に等しい。
  カメラをルートに合わせると、建物の間をどう抜けたかがそのまま見える。

### バックアップ
変更前のスクリプトは `tools/visualize_obstacle_map.py.bak` に残してある。

### 修正: `show(reset_camera=...)` は pyvista 0.49 に存在しない
初版は `plotter.show(reset_camera=reset_cam)` を使っていたが、pyvista 0.49 の
`show()` にその引数はない（`title / window_size / interactive / auto_close /
cpos / ...` のみ）。`--out` 経由でテストしていたため対話分岐が一度も実行されず、
ウィンドウを開いた時に初めて落ちた。

正しくは **`plotter.reset_camera()` を明示的に呼び、focus_route のときだけ
`camera_position` で上書き**する。`camera_position` を代入すること自体が
カメラを「変更済み」として扱い、VTK が最初のレンダリングで自動フィットするのを
抑える。`show()` に引数を渡す必要はない。

```python
plotter.reset_camera()                 # 全体に合わせる
if focus_route and route and route["xs"]:
    plotter.camera_position = [eye, route_centre, (0, 0, 1)]
plotter.show()
```

検証: `reset_camera` 呼び出し 1 回、その後 focus 時の focal point はルート中心
(10, 5, 20) に一致。対話分岐を monkeypatch で実行し、`show()` の kwargs が
空であることを確認。ライブフォルダでも同じく OK。

---

## 6. packed-only 移行で保存が全死していた（`os.execute` は CET に無い）

### 症状
記録を有効にしても `.bin` の mtime が動かない。ログには `STARTED` / `STOPPED`
だけ並んで `saved (packed)` が 1 件も出ない。

```
[13:14:36] Obstacle map recording STARTED (merged with saved map)
[13:15:42] navigation.lua:3136: attempt to call field 'execute' (a nil value)
[13:16:12] navigation.lua:3136: attempt to call field 'execute' (a nil value)
[13:16:42] navigation.lua:3136: attempt to call field 'execute' (a nil value)
... 30 秒ごと ...
```

### 原因
`SaveObstacleMap` は residency 分岐に入る**前**に `EnsureMapDirectory()` で
ゲートしていた。そして packed-only 移行で `Data/map` を消したため：

1. `io.open("Data/map/.dirtest", "w")` が失敗（ディレクトリが存在しない）
2. フォールバックの `os.execute('mkdir ...')` へ進む
3. **CET の Lua サンドボックスに `os.execute` は無い** → nil 呼び出しで例外
4. `SaveObstacleMap` は packed 分岐に到達する前で死ぬ → `.bin` は永遠に書かれない

`Data/map` が存在していた間は 2 に到達しないので、この欠陥は表面化しなかった。
移行の「テキスト形式を消した」部分が、保存経路を一緒に壊していた。

### 修正
- `EnsureDirWritable(dir)` を新設。**シェルに一切頼らない**書き込み_probe のみ。
- `EnsureBinDirectory()` を新設。residency 下の保存は**packed ディレクトリだけ**
  を見る。
- `SaveObstacleMap` の residency 分岐を**どのディレクトリ・ゲートよりも前**に
  移動。テキスト dir の状態が packed 保存を止める経路を無くした。
- `EnsureMapDirectory()` は非 residency 経路専用の probe に格下げ。失敗しても
  Warning を出して packed 保存には影響しない。

### 追加で塞いだ穴：記録停止時に flush していなかった
`StopObstacleRecording()` はフラグを落とすだけで保存しなかった。一方 periodic
save は **autopilot 稼働中は意図的にスキップ**される：

```lua
if not self.av_obj.is_auto_pilot then
    self:SaveObstacleMap()
else
    -- "periodic save skipped (autopilot active)"
end
```

マッピング飛行はまさに autopilot 中なので、periodic save はほぼ永遠に来ない。
セッションが学んだセルは RAM に残り、クラッシュすれば消える。
`StopObstacleRecording()` から `SaveObstacleMap()` を呼ぶようにした。

### 回帰テスト（integration 17 節）
サンドボックス条件をそのまま再現する：

- `obstacle_map_dir` を存在しないパスにする
- `os.execute = nil` / `io.popen = nil`（CET と同じ）
- クリアなセルを 1 つ teaching → `SaveObstacleMap()`
- 例外が出ないこと、**リロードしてそのセルが blocked で読めること**
- 第 2 のセルで `StopObstacleRecording()` → dirty が空になり、リロードでも残ること

`os.execute` を nil にして pcall が通ること自体が「保存経路が一度も呼んでいない」
ことの証明になっている。

### 最終テスト状態
| 実行 | 結果 |
|---|---|
| `python tools/check_lua_syntax.py` | 40 files, 0 problems |
| `python tests/run_grid_integration_test.py` | **110 passed, 0 failed** |
| `python tests/run_resident_cache_test.py` | 33 passed, 0 failed |
| `python tests/run_grid_integration_test.py probe_smoke.lua` | 15 passed, 0 failed |

---

## 6. fix (11): `time_resolution` をユーザー設定として公開（今回実装）

### 背景

§4C では `DAV.time_resolution = 0.01` を「変更しない」としていた。
理由は **この値が CPU の予算ではなく飛行制御ループのサンプリング周期 `dt` そのもの**
で、変えると離着陸の停止位置がずれるためだった。

ユーザー側から「環境に合わせて下げたい」という要望があったため、
**全量を dt 基準に揃えた上で**設定公開した。

### 設計

新規 `Etc/timescale.lua` が唯一の権限を持つ。

| 関数 | 用途 |
|---|---|
| `TimeScale:Get()` | 現在の周期（秒） |
| `TimeScale.DEFAULT_HZ` / `DEFAULT_RESOLUTION` | **出荷既定 20 Hz / 0.05 s** |
| `TimeScale:Scale()` | ベース(0.01)に対する倍率 `dt_scale` |
| `TimeScale:Ticks(seconds)` | 秒 → tick 数 |
| `TimeScale:PerTick(v)` | ベース tick あたりの増分 → 現在周期での増分 |
| `TimeScale:Lead(speed, max_lead)` | 1 tick 中に進む距離＝判定の反応盲点。**`max_lead` は実質必須**（下記） |
| `TimeScale:HzToResolution(hz)` | ユーザー入力 Hz → クランプ済み周期 |
| `TimeScale:GetHz()` | 現在値を整数 Hz で返す（スライダー表示用） |
| `TimeScale:Clamp(v)` | 1/120 〜 1/10 s（= 10〜120 Hz）にクランプ。nil/NaN は**出荷既定 20 Hz** にフォールバック |

`TimeScale` は `Utils` / `Def` / `Engine` と同じ `X.__index = X` + `function X:Method()` スタイル。
制御ループは 1 つしか存在しないのでシングルトンとしてクラステーブル自体に対して呼ぶ
（`TimeScale:Set(...)`）。`.` で残っているのは `BASE_RESOLUTION` / `DEFAULT_HZ` /
`MIN_HZ` / `MAX_HZ` / `MODE_*` などの**データ定数**のみ。
（`Cron.Every` の `.` は psiberx 製の外部モジュールなので別枠）
`DAV.time_resolution` / `DAV.dt_scale` は `TimeScale:Set()` が常時同期する。
**実行時に直接代入してはいけない。**

### 何をスケールし、何をしないか

**スケールする（tick あたりの累積量）**

| 箇所 | 量 |
|---|---|
| `engine.lua` | `rpm_count_step` / `rpm_restore_step` |
| `engine.lua` | `heli_lift_acceleration` の加算（`z` 項ではない） |
| `av.lua` | `thruster_angle_step` / `thruster_angle_restore` |
| 全域 | tick カウント・タイムアウト → `TimeScale:Ticks(秒)` |

**スケールしない（すでに秒基準＝レート目標）**

`Engine:Update` は毎フレーム `force = direction_velocity * mass` /
`torque = (cmd - actual) * gain` を渡しており、指令量は秒基準。

- `acceleration` / `vertical_acceleration` / `left_right_acceleration` [m/s²]
- `horizontal_air_resistance_const` / `vertical_air_resistance_const` [1/s]
  - 終端速度 `a/c = 1.5/0.015 = 100 m/s ≈ max_speed 220mph` が単位の根拠
- `*_change_amount` / `*_restore_amount` / `rotate_roll_change_amount`
- `CalculateIdleMode` の `damping` / `height_gain`
- `FluctuationVelocity` の `step_width_per_second`（明示的に /s）

これらを掛えると理由なく `dt_scale` 倍強くなる。

### 離着陸の停止位置：反応盲点の補正

制御ループは高度を 1 tick に 1 回しか読まない。 therefore 判定を見た時点で
機体はすでに `speed * dt` 進んでいる。

```lua
local lead = TimeScale:Lead(descent_speed)
if self:GetHeight() - lead <= self.av_obj.minimum_distance_to_ground then
```

`<` ではなく `<=` にしているのは、周期と物理ステップが整数倍でちょうど揃う
境界で lead が移動量と相殺し、厳密比較だと 1 tick 遅れ発火になるため。

同様に `AutoLeaving`（上昇）でも `lead` を前方に足し、
`IsWall` の探知距離にも `+ lead` を加算した。

### 引き算した安全ネット（LandingTriggerHeight）

当初 `LandingTriggerHeight()` を入れて「減速開始点を、スクリプト高度と
**実減速で止まる必要距離**の大きい側で発火」させたが、**誤りだったので削除した**。

`autopilot_acceleration = max(1.0, speed * 0.063)` は 25 m/s で **1.575 m/s²**
しかなく、停止距離 `v²/2a = 625/3.15 = 198 m` となる。100 m 高度に対して
198 m なので**全高度で即フレア**が発火し、降下は 5 m/s に張り付く。
実減速が小さすぎるため、この「安全ネット」は安全ではなく単なる誤作動だった。

→ 元の `deceleration_height`（`min(h*0.5, 80)`）+ lead に戻した。

### lead は無制限にしてはいけない（真のバグ）

`lead = descent_speed × dt` を `Engine:GetVelocity()` の返り値を信じて
そのまま使っていたのが**「はるか上空で着陸完了する」の直接原因**。

物理ハンドルからの速度取得は、スポーン直後・テレポート直後などに
一時的に大きな値を返すことがある。500 m/s を 20 Hz で拾うと

```
lead = 500 × 0.05 = 25 m
高度 20 m で: 20 - 25 = -5 <= 1.2  →  即停止（地上 19 m 上で）
```

**修正**：`TimeScale:Lead(speed, max_lead)` に上限引数を追加し、
**守っている距離自身を上限**として渡す。

| 呼び出し | 上限 |
|---|---|
| `AutoLanding` | `minimum_distance_to_ground`（1.2 m） |
| `SpawnToSky` | `minimum_distance_to_ground`（1.2 m） |
| `AutoLeaving` | `check_cell_distance`（5.0 m） |

「補正量は、補正対象より大きくなってはいけない」という原則。
100 Hz・25 m/s では lead = 0.25 m で上限に当たらないので通常動作は不変。

### 修正した時制バグ（放置すると必ず壊れていた箇所）

| 箇所 | 修正前 | 修正後 |
|---|---|---|
| `av.lua` | `up_timeout = 350`（素 tick。0.01 タイマーなので偶然 3.5s） | `up_timeout = 3.5 -- s` + `TimeScale:Ticks()` |
| `av.lua` | `timer.tick > 350`（unmount） | `unmount_timeout = 3.5 -- s` |
| `core.lua` | `max_move_hold_count = 50000` | `max_move_hold_seconds = 500` |
| `av.lua` | `Cron.Every(0.01, ...)` ハードコード 2 箇所 | `DAV.time_resolution` に統一 |
| `event.lua` | `math.floor(2 / DAV.time_resolution)` | `TimeScale:Ticks(2)` |

tick 数の閾値は**シーケンス開始時にローカルへ退避**している。
実行中にユーザーが設定を変えると締切が動くため。

### 設定

`user_setting_v3.json` に 2 キー追加（NativeSettings の Advance 段）：

- `time_resolution` — **10〜120 Hz の連続値**（NativeSettings は Hz スライダー、
  5 Hz 刻み、**既定 20 Hz**）。保存値は秒（周期）なので JSON 直編集も可。
  `TimeScale:HzToResolution()` / `GetHz()` / `ResolutionToHz()` が変換を担当し、
  範囲外は `TimeScale.Clamp` が 1/120 〜 1/10 に吸収する。
- `time_scale_measured` — オフ時は設定値で補正（＝従来の挙動）。
  オンの時は実際の経過時間で補正。Cron はフレームより速く発火しないため、
  処理が追いつかない環境で挙動が一定になる。反面 100fps 未満では体感も変わる。

**`BASE_RESOLUTION`（チューニング基準）は 0.01 のまま据え置き。**
ここを動かすと全定数が無言で再スケールするため、既定値とは別定数にしてある。

**出荷既定は 20 Hz（`DEFAULT_RESOLUTION = 0.05`）で、`dt_scale == 5.0`。**
つまり既定構成では制御ループはチューニング時より 5 倍粗く、
その差分を lead 補正と `PerTick` で埋めている形になる。
既存ユーザーは `user_setting_v3.json` の `version` 不一致時にこの既定値へ移行する。

### 実効レートの注意

Cron は 1 レンダリングフレームに最大 1 回しか発火しない
（`delay -= delta; if delay <= 0 then fire`）。
したがって実効レートは `min(1/resolution, fps)`。
30fps 環境で 100 Hz を指定しても 33 Hz にしかならないので、
その場合は `time_scale_measured` をオンにするか 33 Hz を選ぶ。

### 回帰テスト

新規 `tests/timescale_landing_test.lua`（`python tests/run_timescale_landing_test.py`）

- **A. 単位換算** — Ticks / Lead / PerTick / Clamp / プリセット往復 / measured モード
- **B. 着陸停止点** — 物理 600Hz に対し **120/100/80/60/50/40/33/25/20/10 Hz**
  × 進入速度 5/12/25 m/s をスイープ。
  補正なしは 25 m/s @20Hz 以下で **停止高度 -0.04m（地面を貫通）**、
  補正ありは全 30 組合せでクリアランス 1.2m を割らない。
  さらに補正後の散布が `speed × (1/10 − 1/120)` の理論値以内に収まることを検証。
- **C. 静的ガード** — `Cron.Every(0.01`、`/ DAV.time_resolution`、
  `timer.tick <N|>N` の素 tick 比較がソースに残っていたら失敗。

### 最終テスト状態（fix 11 後）

| 実行 | 結果 |
|---|---|
| `python tools/check_lua_syntax.py` | 49 files, 0 problems |
| `python tests/run_timescale_landing_test.py` | **188 passed, 0 failed** |
| `python tests/run_meter_cadence_test.py` | 42 passed, 0 failed |
| `python tests/run_situation_cost_test.py` | 54 passed, 0 failed |
| `python tests/run_enter_exit_cost_test.py` | 52 passed, 0 failed |
| `python tests/run_onaction_cost_test.py` | 40 passed, 0 failed |
| `python tests/run_axis_proxy_cost_test.py` | 31 passed, 0 failed |
| `python tests/run_entity_cache_test.py` | 30 + 31 passed, 0 failed |

### 既定 20 Hz 化による影響（要実機確認度が上がる）

既定が `dt_scale == 5.0` になるため、**何も設定していないユーザーも
5 倍粗い制御レートで飛ぶ**。テストで担保しているのは停止位置だけなので、
実機では以下を必ず確認する：

1. 手動飛行の操縦感（0.05 s のゼロ次保持遅入による発振・ overshoot）
2. ホバーの収束（`CalculateIdleMode` の P/D が 5 倍遅い保持で破綻しないか）
3. RPM / スラスター角 / 着陸 SE の追従

気に入らなければスライダーで 50〜100 Hz に戻せばよく、
`BASE_RESOLUTION` を触っていないので**どの Hz でも元のチューニングに
正確に-scaling-される**ことがテスト済み。

### 降下タイムアウトを固定 20 s に（fix 12）

実機ログで `AutoPilot Success for timeout` が確認できたため確定した。

**原因**：予算が `(height / autopilot_speed) * 1.8` で、
**着陸開始時点から巡航速度で降下している前提**だった。

| 量 | 値 |
|---|---|
| 降下開始速度 | `SetDirectionVelocity(0, 0, -0.5)` = 0.5 m/s |
| 加速度 | `autopilot_acceleration = max(1.0, speed*0.063)` = **1.575 m/s²** @25m/s |
| 巡航到達に必要な降下距離 | `(v² − v0²) / 2a` = **198 m** |

典型的な 50 m 着陸では予算（3.6 s）が**巡航到達前に切れ**、
**地上 38 m で「着陸完了」**になっていた。100 Hz でも 20 Hz でも同じ。

**修正**：`Navigation.landing_timeout_seconds = 20`（固定）に変更。

この値は**安全ネットであってタイミング目標ではない**。実際の着陸は
ground / `target_z` / collision の各分岐で終了し、20 s は
「地上が決して検出されない場所（void・水上）で降下し続ける」
ケースだけを拾う。

**20 s がカバーする降下距離**（降下プロファイルを実積分して算出）

| 巡航速度 | カバー高度 |
|---|---|
| 5 m/s | ~43 m |
| 10 m/s | ~105 m |
| 25 m/s | ~160 m |
| 35 m/s | ~390 m |
| 50 m/s | ~590 m |

実際の着陸高度は `autopilot_leaving_height = max(20, speed*2)`
（25 m/s で 50 m）なので全速度域で余裕がある。

**効果（テスト D 節、AutoLanding 判定連鎖 + Engine fluctuation の完全ミラー）**

```
旧予算   20m @100Hz -> stop=17.6m TIMEOUT     20s固定   20m @100Hz -> stop= 1.2m ground
旧予算   50m @100Hz -> stop=38.0m TIMEOUT     20s固定   50m @100Hz -> stop= 1.2m ground
旧予算  100m @ 20Hz -> stop=55.5m TIMEOUT     20s固定  100m @ 20Hz -> stop= 1.2m ground
旧予算  200m @ 20Hz -> stop=47.6m TIMEOUT     20s固定  150m @ 20Hz -> stop= 1.2m ground
```

旧予算は 8/8 全ケースでタイムアウト。20 s 固定は 12/12 全ケースで接地
（100 Hz / 33 Hz / 20 Hz）。

**既知の上限（テストで固定）**：25 m/s 巡航で 200 m 降下は約 23.6 s かかり、
20 s より先に接地しない。本 Mod の対象高度より十分高いが、
将来降下プロファイルを変えたときに気づけるようテストで押さえてある。

### 召喚降下のタイムアウト（fix 13）

autopilot 着陸が直った後、**車両召喚時の着陸地点が高い**という報告。
同じクラスのバグだが**定数が別**だった。`AV.down_timeout = 5`。

**降下プロファイル**（`spawn_height=20`, `down_speed=-5.0`）

| 区間 | 速度 | 所要 |
|---|---|---|
| 20 m → 10 m | `down_speed` 5 m/s | 2.0 s |
| 10 m → 4 m | `-2 m/s²` で 1 m/s へ減速 | 2.0 s |
| 4 m → 1.2 m | 1 m/s 維持 | 2.8 s |
| | **合計** | **6.8 s** |

`down_timeout = 5` は**守るべき降下より短かった**ため、全召喚が
ground 分岐ではなくタイムアウト分岐で **地上約 3 m 上**で止まっていた。

**修正**：`down_timeout = 10`（余裕 ~50%）。

```
旧(5s)  @100Hz -> stop=3.00m TIMEOUT      新(10s)  @100Hz -> stop=1.24m ground  6.76s
旧(5s)  @ 33Hz -> stop=3.12m TIMEOUT      新(10s)  @ 33Hz -> stop=1.34m ground  6.79s
旧(5s)  @ 20Hz -> stop=3.20m TIMEOUT      新(10s)  @ 20Hz -> stop=1.45m ground  6.75s
```

`spawn_height` はハードコード（ユーザー設定なし）なのでプロファイルは固定で、
10 s は全ケースで安全。テスト E 節でプロファイルを実測し、
`spawn_height` / `down_speed` / フレア定数を変えて 10 s を超えたら
検知するようにしてある。

### 加速音の停止ディバウンス（fix 14）

`time_resolution` を 100 Hz → 20 Hz に上げたことで、
**前進時の追加エンジン音（`dav_av_accel_start`）が鳴らなくなった**。

> **訂正**：当初 `timeToLive = 1.5` を「音の寿命」と解釈し、
> 「エッジ 1 回では 1.5 s で音が消える」と書いたが**誤り**。
> `timeToLive` は**フェード時間**で、音は鳴り続ける。
> それに伴い keep-alive 方式は取り下げた。

**実際の機構：一時的な空キューが誤 STOP を生む**

`ControlSound` は **drain 済みのアクションキュー**から
加速中フラグをラッチする。このキューは**過渡的な信号**で、
ある tick で移動コマンドが見えるかどうかは、

- ボタン保持プロデューサの Cron タイマ
- 制御ループコンシューマの Cron タイマ
- フレームレート

の**位相関係**で決まる。位相がずれると**キーを押し続けているのに
その tick のキューが空**になり、旧コードはそれを即 `Stop` イベントに
変換していた。→ **加速中に音の ON/OFF が繰り返され、
1.5 s フェードを抜ける前に毎回消える。**

100 Hz ではプロデューサが毎フレーム enqueue していたため
このギャップが発生せず、症状が出なかった。

**修正**：停止条件に**猶予（ディバウンス）**を入れる。

```lua
obj.sound_stop_grace_seconds = 0.3
-- ControlSound 内
local grace_ticks = TimeScale:Ticks(self.sound_stop_grace_seconds)
-- コマンドが見えたら即ラッチ、見えなくなっても grace_ticks 連続して
-- 経るまで Stop を発火しない
```

| | 1 tick のギャップ | grace-1 tick | 実際のリリース |
|---|---|---|---|
| 旧 | **STOP** | STOP | STOP |
| 新 | イベント無し | イベント無し | STOP（1 回） |

猶予は `TimeScale:Ticks()` で**実時間 0.3 s**に固定しているため、
解像度を変えても体感が変わらない（100 Hz=30 tick / 33 Hz=10 tick / 20 Hz=6 tick）。

**追加で修正した餓え**：旧コードは `if/elseif` 一本鎖で、
加速ブランチがスラスターブランチを**餓させていた**
（加速エッジが処理されるたび `return` していた）。
両レイヤーを独立に処理するよう変更した。

**診断ログ**：停止時に猶予 tick 数を記録するようにしたので、
実機ログで誤 STOP の有無を即確定できる。

```
Stop Acceleration Sound after 7 idle ticks
```

**実機での見方**：加速中にこのログが出る → まだ誤 STOP がある
（`sound_stop_grace_seconds` を上げる）。出ないのに音が鳴らない →
`ControlSound` の外（音声リソース／イベント配線）が原因。

### 副次的に発見した誤削除（fix 15）

ui.lua の obstacle recording スイッチから
`Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)` が
**誤って削除されていた**（このセッションの編集で消えた）。
音とは無関係だが、設定が保存されず再起動で元に戻るバグだったので復元した。

### 制御ループの低域通過とリレーの dt 非依存化（fix 16）

20 Hz 化により**安定化リレーと autopilot の旋回で、目標角度へ近づく動きが
若干不安定**になった。原因は 2 種類あった。

#### (1) per-tick 低域通過フィルタの時定数が 5 倍になっていた

`x = x + (target - x) * alpha` を 1 tick に 1 回実行する形は
1 次フィルタで、極は `(1 - alpha)`、**時定数は `-dt / ln(1 - alpha)`**。
つまり **`alpha` は `dt` とセットで意味を持つ**。
`dt` を 5 倍にしても `alpha` を固定のままにすると、
フィルタは実時間ベースで **5 倍鈍くなる**。

| 箇所 | 係数 | 100Hz の時定数 | 20Hz（修正前） |
|---|---|---|---|
| `yaw_smooth_alpha`（旋回目標） | 0.06 | 0.162 s | **0.808 s** |
| `transition_rate`（inertia/blend） | 0.15 | 0.062 s | **0.308 s** |

**旋回目標が 0.8 秒遅れる**＝機体は「1 秒前に要求された方角」を
追いかけ続けることになり、接近時にオーバーシュートを繰り返す。
これがふらつきの正体。

**修正**：極を再マッピングする `TimeScale:SmoothAlpha()` を新設。

```lua
alpha_eff = 1 - (1 - alpha) ** (dt / BASE_RESOLUTION)
```

| alpha | 100Hz | 33Hz | 20Hz | 10Hz | 時定数 |
|---|---|---|---|---|---|
| 0.06 | 0.0600 | 0.1710 | 0.2661 | 0.4614 | **全解像度 0.162 s** |
| 0.15 | 0.1500 | 0.3889 | 0.5563 | 0.8031 | **全解像度 0.062 s** |

`BASE_RESOLUTION` では恒等（調整基準の不変を保証）。

#### (2) 安定化リストアが素のリレーだった

```lua
if roll > deadband then local_roll = -restore_amount   -- 距離と無関係にフルレート
```

リレーは**どれだけ目標に近いかに関係なく、1 tick 分フルレートをコミット**する。
コミットされる超過量は `レート × dt` なので **tick に比例して増える**。
20 Hz では補正が着地するまでに機体は 5 倍進んでおり、
デッドバンド端で Settling せずに揺れる。

**修正**：**バウンダリレイヤー**を追加。デッドバンド端に向かって
コマンドレートを線形に 0 へ減衰させる。

```lua
obj.restore_boundary_deg = 1.0   -- 基準解像度での層の厚み
-- 層の幅は dt_scale 倍 → 粗いループの分だけ余分に広げる
boundary = restore_boundary_deg * dt_scale
rate = full_rate * (excess / boundary)     -- 層内
```

| 解像度 | 層の幅 |
|---|---|
| 100 Hz | 1.0° |
| 33 Hz | 3.0° |
| 20 Hz | 5.0° |

**適用箇所**（3 か所すべて、`Engine:Run` / `Engine:OnlyAngularRun` /
`Engine:CalculateIdleMode` の roll・pitch）。

幅を `dt_scale` 倍にした意図：**100 Hz では調整基準とほぼ同じ挙動**に留まり、
粗くなった分だけ平滑化が効く。`restore_boundary_deg = 0` で
従来（素のリレー）に戻せる。

### 未検証（実機が必要）

Lua 側から `FlyAVSystem` の C# 実装（別リポジトリ `RED4ext_DAV`）は見えず、
`ChangeVelocity` / `AddForce` が impulse 系か真の力積かは断定できない。
終端速度の整合から **レート基準（秒基準）と判断**したが、
20〜25 Hz で実際に離着陸して以下を確認する必要がある：

1. 着陸停止位置が 100 Hz と比べて数 10cm 以内に収まるか
2. RPM の上がり下がりが体感で同じか
3. スラスター角度の追従速度が同じか

ずれる場合は `TimeScale.PerTick` を掛かっている 3 箇所
（rpm / thruster / heli_lift）だけを外して再確認する。
