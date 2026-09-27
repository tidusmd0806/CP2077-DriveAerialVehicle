# tests/

DriveAerialVehicle のテスト・ベンチマーク・診断用スクリプト一式。
（以前は `tools/` に混在していたものをここに分離した）

`tools/` には**ビルド／検証の実用ツール**だけが残っている:

| ファイル | 用途 |
|---|---|
| `tools/mapbin_pack.py` | `.dat` + `.diff` → packed `DAVOB4` `.bin` + `manifest.txt` |
| `tools/visualize_obstacle_map.py` | PyVista で障害物マップを 3D 表示 |
| `tools/check_lua_syntax.py` | 配置前の LuaJIT(5.1) 構文ゲート |

## 実行方法

すべてリポジトリルートから実行する。`lupa` が必要:

```
pip install lupa
```

Windows の Lua `io.open` は ANSI コードページを使うため、リポジトリパスに
非 ASCII 文字（`Y_クリエイト`）が含まれる関係で、各ランナーは作業一式を
`C:\dav*` のような ASCII ワークディレクトリにステージしてから実行する。

### 回帰テスト

```
python tests/run_grid_integration_test.py            # 統合テスト（DAVOB4 base image）
python tests/run_grid_integration_test.py probe_smoke.lua
python tests/run_resident_cache_test.py              # 既存回帰
```

`run_grid_integration_test.py` はテキスト専用 / bin 専用 / 空 の 3 種類の
マップディレクトリをステージし、新しい packed 経路と旧ローダを比較できる。

### ベンチマーク

```
python tests/run_grid_residency_bench.py                       # 既定: grid_residency_bench.lua
python tests/run_grid_residency_bench.py grid_slice_bench.lua  # ほかの bench を指定可
python tests/run_full_residency_bench.py
```

`grid_residency_bench.lua` 系は `grid_proto.lua` / `grid_slice_proto.lua` を
`dofile` する（第 4 引数 `TOOLSDIR` 経由）。

### 診断プロブ

実行時挙動を Lua 側で計装して切り分けるもの。その都度中身を読む前提:

```
corridor_duty_probe.lua          廊下プリロードの実稼働率
diagnose_route_unknown.lua       目的地が unknown と判定される経路
first_autopilot_breakdown.lua    初回 autopilot の内訳
full_load_probe.lua              全マップロードの内訳
gc_spike_probe.lua               GC によるスパイク
key_cost_probe.lua               セルキー演算のコスト
startup_probe.lua                起動シーケンスの内訳
```

## 構文ゲート

テスト Lua も実機と同じ LuaJIT で走る。なので `tools/check_lua_syntax.py` は
`tests/` も対象にしている。`//` や `table.unpack` など 5.4 記法を混ぜても
ゲーム内で初めて落ちる、という事故を防ぐため。

```
python tools/check_lua_syntax.py
```
