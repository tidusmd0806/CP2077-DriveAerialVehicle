# デプロイ手順（配置漏れが「効かない」になる）

このリポジトリにはデプロイスクリプトが**無い**。`source/resources/` 配下を手でゲームフォルダへ
コピーしているため、**追加されたファイルは黙って配置漏れになる**。実際にこれで autopilot が
全滅した（`Data/map_bin` がゲーム側に無く、障害物マップ不在 → 全目的地が `unknown` →
ルート 0 区間）。

## 同期先

| 種別 | リポジトリ | ゲーム側 |
|---|---|---|
| MOD 本体 | `source/resources/bin/x64/plugins/cyber_engine_tweaks/mods/DriveAerialVehicle/` | `<game>/bin/x64/plugins/cyber_engine_tweaks/mods/DriveAerialVehicle/` |
| DLL | `red4ext/plugins/DriveAerialVehicle/DriveAerialVehicle.dll` | `<game>/red4ext/plugins/DriveAerialVehicle/` |

`<game>` = `C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077`

## 必ず揃っていないといけないもの

| パス（MOD フォルダ基準） | 何 | 無いとどうなる |
|---|---|---|
| `init.lua`, `Modules/`, `Etc/`, `External/`, `Debug/` | Lua 本体 | 起動しない |
| **`Data/map_bin/chunk_*.bin` + `manifest.txt`** | **障害物マップ（96 chunk / 約 8MB）** | **autopilot がルートを作れない**（`last_route.json` の `segments` が空、目的地が全部 `unknown`） |
| `Data/map/*.dat`（+ `.diff`） | 旧形式のベース／差分。`map_bin` の元データ | 再パック時に必要 |
| `Data/*.json` | 入力・モデル定義 | 操作できない |
| `Data/user_setting_v3.json` | ユーザー設定 | **ゲーム側を上書きしないこと**（ライブ設定なので） |

`Data/` の相対パスは **CET の Lua カレントディレクトリ＝MOD フォルダ**基準で解決される
（`last_route.json` が MOD フォルダに書かれることで確認できる）。ゲーム直下に `Data/` は要らない。

## 同期コマンド（PowerShell）

```powershell
$src = "C:\Users\sdxeq\Documents\div\cp-av\source\resources"
$dst = "C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077"
# 全体（user_setting_v3.json は守る）
robocopy "$src\bin" "$dst\bin" /E /XF user_setting_v3.json
robocopy "$src\red4ext" "$dst\red4ext" /E
```

`robocopy /E` を使う限りは `map_bin` のような追加も追随する。ファイル単位で `cp` する運用は
新規ファイルが必ず漏れるので避ける。

## 配置漏れをログで見抜く

| ログ行 | 意味 |
|---|---|
| `[DAV][map] NO PACKED OBSTACLE MAP: ...` | `Data/map_bin` が無い／空。autopilot は死んでいる |
| `NATIVE FLIGHT DISABLED -> Lua fallback: <理由>` | native 飛行が落ちて Lua 経路に退避した（パフォーマンスは落ちるが飛べる） |
| `[DAV][probe] ... native=true fm=true mode=2 loop=false` | 正常。DLL が保持、Lua は状態変化時だけ push |

`Log:Record` は `PrintDebugMode`（ImGui の "Print Debug Mode"）がオフだと `scripting.log` に
**出ない**。セッション全体を壊す失敗（障害物マップ不在、native 失効）は `print` でも出すようにして
ある設定に依存させない、という方針。
