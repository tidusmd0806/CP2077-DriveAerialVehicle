"""
visualize_obstacle_map.py
=========================
DriveAerialVehicle mod - PyVista obstacle map visualizer.

Loads:
  - Data/map_bin/chunk_*.bin   (packed DAVOB4, preferred)
  - Data/map/chunk_*.dat       (legacy text v3, fallback)
  - Data/last_route.json       (optional)

Renders a native VTK window (no browser) with obstacle/danger/clear points
and the latest A* route. Includes an in-window Reload button and R hotkey.

The packed path is what the game actually reads, so this shows the same thing
the autopilot sees - including chunks minted at runtime by a learned-cell fold,
which are recorded in Data/map_bin/manifest.txt.
"""

import argparse
import json
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent


def _has_map(d: Path) -> bool:
    """Does this directory hold an obstacle map in either format?"""
    return ((d / "map_bin").is_dir() or (d / "map").is_dir()
            or any(d.glob("chunk_*.bin")) or any(d.glob("chunk_*.dat")))


def _candidate_data_dirs():
    """Every plausible home for the mod's Data directory, best guess first.

    This script gets run from two very different places: the repo's tools/ dir,
    and the installed mod root where Data/ sits right beside it. Hard-coding
    either one breaks the other -- the first version did exactly that and looked
    for `mods/source/resources/...`, which exists nowhere. So probe for the
    layout instead of assuming it.
    """
    yield SCRIPT_DIR / "Data"                       # installed mod root
    # repo checkout: tools/ -> <repo>/source/resources/.../DriveAerialVehicle/Data
    yield (SCRIPT_DIR.parent / "source" / "resources" / "bin" / "x64" / "plugins"
           / "cyber_engine_tweaks" / "mods" / "DriveAerialVehicle" / "Data")
    p = SCRIPT_DIR
    for _ in range(5):                              # walk up looking for Data/
        p = p.parent
        yield p / "Data"
    yield SCRIPT_DIR                                # chunks directly beside the script


def _find_data_dir() -> Path:
    for cand in _candidate_data_dirs():
        try:
            if _has_map(cand):
                return cand
        except OSError:
            continue
    return SCRIPT_DIR / "Data"


DATA_DIR = _find_data_dir()
DEFAULT_BIN_DIR = DATA_DIR / "map_bin"
DEFAULT_TEXT_DIR = DATA_DIR / "map"
DEFAULT_MAP_DIR = DEFAULT_BIN_DIR if DEFAULT_BIN_DIR.is_dir() else DEFAULT_TEXT_DIR
DEFAULT_ROUTE_PATH = DATA_DIR / "last_route.json"

# ---------------------------------------------------------------------------
# Packed DAVOB4 layout (little endian)
#   off  size  field
#    0     6   magic "DAVOB4"
#    6     1   z_levels
#    7     1   zmin_bias      (z_min + 128)
#    8     2   cell_size_cm   (uint16 LE, 1000 == 10.0 m)
#   10     4   known_count
#   14     2   reserved
#   16     ..  body: z_levels * 50 * 50 bytes
#
#   body index = (z - z_min) * 2500 + (cy - chunk_cy*50) * 50 + (cx - chunk_cx*50)
#
# Cell byte: 0 = UNKNOWN, 1 = CLEAR, 2 = DANGER, 3 = BLOCKED.
#
# This is NOT the text v3 numbering (0=clear, 1=danger, >=2=blocked). v4 adds
# an explicit UNKNOWN so a dense image can mark never-observed cells; the text
# format simply omitted those. Anything reading v4 must skip 0 rather than treat
# it as clear, or the whole unexplored volume renders as flyable space.
# ---------------------------------------------------------------------------
MAGIC = b"DAVOB4"
CHUNK_CELLS = 50
SLICE = CHUNK_CELLS * CHUNK_CELLS
HDR = 16

V_UNKNOWN, V_CLEAR, V_DANGER, V_BLOCKED = 0, 1, 2, 3
STATE_NAMES = {V_CLEAR: "clear", V_DANGER: "danger", V_BLOCKED: "blocked"}


def get_segment_color(segment_index: int) -> str:
    palette = [
        "#ffe55c",
        "#ffb347",
        "#88ddaa",
        "#6ec6ff",
        "#ff9aa2",
        "#c7a6ff",
        "#ffd166",
        "#9ad0f5",
    ]
    return palette[(max(segment_index, 1) - 1) % len(palette)]


def _parse_dat_content(content: str, cells: dict):
    import re
    m = re.search(r"cell_size=([\d.]+)", content.split("\n", 1)[0])
    cell_size = float(m.group(1)) if m else 10.0
    for line in content.splitlines()[1:]:
        parts = line.split()
        if len(parts) != 4:
            continue
        try:
            cx, cy, cz, val = int(parts[0]), int(parts[1]), int(parts[2]), int(parts[3])
        except ValueError:
            continue
        key = f"{cx}_{cy}_{cz}"
        if key not in cells or cells[key] < val:
            cells[key] = val
    return cell_size


def load_obstacle_map_chunked(map_dir: Path):
    cells = {}
    cell_size = 10.0
    for chunk_path in sorted(map_dir.glob("chunk_*.dat")):
        content = chunk_path.read_text(encoding="utf-8")
        if content.startswith("DAV_OBMAP"):
            cell_size = _parse_dat_content(content, cells)
    return cell_size, cells


# ---------------------------------------------------------------------------
# Packed (DAVOB4) loading
#
# One byte per cell, dense, with a per-chunk z window in the header. Reading it
# is a memcpy plus a vectorised nonzero scan, so there is no per-line parsing and
# no Python-level loop over 2.6M cells.
# ---------------------------------------------------------------------------

def load_bin_manifest(bin_dir: Path):
    """manifest.txt -> [(cx, cy), ...], or None when absent.

    The game enumerates chunks from this file rather than probing every
    coordinate, so using it here keeps the visualiser looking at exactly what
    the game sees - including chunks minted at runtime by a learned-cell fold.
    """
    path = bin_dir / "manifest.txt"
    if not path.is_file():
        return None
    out = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        parts = line.split()
        if len(parts) != 2:
            continue
        try:
            out.append((int(parts[0]), int(parts[1])))
        except ValueError:
            continue
    return out or None


def enumerate_bin_chunks(bin_dir: Path):
    """Chunk coords to read: from the manifest when present, else a glob."""
    manifest = load_bin_manifest(bin_dir)
    if manifest is not None:
        return manifest, "manifest.txt"
    out = []
    for p in sorted(bin_dir.glob("chunk_*.bin")):
        parts = p.stem.split("_")
        if len(parts) != 3:
            continue
        try:
            out.append((int(parts[1]), int(parts[2])))
        except ValueError:
            continue
    return out, "directory glob"


def load_bin_map(bin_dir: Path):
    """Read packed chunks into world-coordinate point clouds per cell state.

    Returns (cell_size, states, stats) where `states` maps
    V_CLEAR / V_DANGER / V_BLOCKED to (xs, ys, zs) numpy arrays in world
    coordinates, and UNKNOWN cells are dropped entirely.
    """
    import numpy as np

    chunks, how = enumerate_bin_chunks(bin_dir)
    cell_size = 10.0
    acc = {V_CLEAR: [], V_DANGER: [], V_BLOCKED: []}
    n_read = 0
    skipped = []

    for cx, cy in chunks:
        path = bin_dir / f"chunk_{cx}_{cy}.bin"
        if not path.is_file():
            skipped.append(f"{cx},{cy} (missing)")
            continue
        raw = path.read_bytes()
        if not raw.startswith(MAGIC):
            skipped.append(f"{cx},{cy} (bad magic)")
            continue
        zlevels = raw[6]
        zmin = raw[7] - 128
        cm = raw[8] | (raw[9] << 8)
        if cm:
            cell_size = cm / 100.0
        need = zlevels * SLICE
        if len(raw) < HDR + need:
            skipped.append(f"{cx},{cy} (truncated)")
            continue
        body = np.frombuffer(raw, dtype=np.uint8, count=need, offset=HDR)
        body = body.reshape(zlevels, CHUNK_CELLS, CHUNK_CELLS)

        lz, ly, lx = np.nonzero(body)
        if lz.size:
            gx = cx * CHUNK_CELLS + lx
            gy = cy * CHUNK_CELLS + ly
            gz = zmin + lz
            st = body[lz, ly, lx]
            for state in (V_CLEAR, V_DANGER, V_BLOCKED):
                m = st == state
                if m.any():
                    acc[state].append((gx[m], gy[m], gz[m]))
        n_read += 1

    states = {}
    for state, parts in acc.items():
        if not parts:
            states[state] = (np.zeros(0), np.zeros(0), np.zeros(0))
            continue
        xs = np.concatenate([p[0] for p in parts])
        ys = np.concatenate([p[1] for p in parts])
        zs = np.concatenate([p[2] for p in parts])
        states[state] = ((xs + 0.5) * cell_size,
                        (ys + 0.5) * cell_size,
                        (zs + 0.5) * cell_size)
    stats = {"chunks": n_read, "listed": len(chunks), "skipped": skipped,
             "enumerated_by": how}
    return cell_size, states, stats


def resolve_map_source(path: Path, force: str | None = None):
    """Pick packed or text loading from whatever `path` points at.

    Pointing at Data/map still finds the packed set next door, so existing
    invocations keep working and simply get the faster path. `force` overrides
    the detection outright -- without it `--text` would silently load packed
    anyway whenever a map_bin sibling happens to exist.
    """
    if force == "text":
        return "text", path
    if force == "bin":
        return "bin", path
    if path.is_dir():
        if any(path.glob("chunk_*.bin")):
            return "bin", path
        sibling = path.parent / "map_bin"
        if sibling.is_dir() and any(sibling.glob("chunk_*.bin")):
            return "bin", sibling
        if any(path.glob("chunk_*.dat")):
            return "text", path
    return "text", path


def load_route(path: Path):
    if not path.exists():
        return None
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)

    def parse_pos(entry):
        if not isinstance(entry, dict):
            return None
        return (
            float(entry.get("x", 0)),
            float(entry.get("y", 0)),
            float(entry.get("z", 0)),
        )

    segments = []
    unique_astar_targets = set()
    raw_segments = data.get("segments", [])
    for segment in raw_segments:
        waypoints = segment.get("waypoints", [])
        seg_xs, seg_ys, seg_zs, seg_labels = [], [], [], []
        for wp in waypoints:
            seg_xs.append(float(wp.get("wx", 0)))
            seg_ys.append(float(wp.get("wy", 0)))
            seg_zs.append(float(wp.get("wz", 0)))
            seg_labels.append(wp.get("key", ""))
        if not seg_xs:
            continue
        seg_astar_pos = parse_pos(segment.get("astar_destination_pos"))
        if seg_astar_pos is not None:
            unique_astar_targets.add(seg_astar_pos)
        segments.append(
            {
                "index": int(segment.get("index", len(segments) + 1)),
                "kind": segment.get("kind", "route"),
                "xs": seg_xs,
                "ys": seg_ys,
                "zs": seg_zs,
                "labels": seg_labels,
                "astar_destination_pos": seg_astar_pos,
                "astar_destination_status": segment.get("astar_destination_status", "unknown"),
            }
        )

    waypoints = data.get("waypoints", [])
    xs, ys, zs, labels = [], [], [], []
    for wp in waypoints:
        xs.append(float(wp.get("wx", 0)))
        ys.append(float(wp.get("wy", 0)))
        zs.append(float(wp.get("wz", 0)))
        labels.append(wp.get("key", ""))
    sp = data.get("start_pos", {})
    ep = data.get("end_pos", {})
    final_destination_pos = parse_pos(data.get("final_destination_pos"))
    original_destination_pos = parse_pos(data.get("original_destination_pos"))
    astar_destination_pos = parse_pos(data.get("astar_destination_pos"))
    if astar_destination_pos is not None:
        unique_astar_targets.add(astar_destination_pos)
    return {
        "start_pos": (float(sp.get("x", 0)), float(sp.get("y", 0)), float(sp.get("z", 0))),
        "end_pos": (float(ep.get("x", 0)), float(ep.get("y", 0)), float(ep.get("z", 0))),
        "final_destination_pos": final_destination_pos,
        "original_destination_pos": original_destination_pos,
        "astar_destination_pos": astar_destination_pos,
        "final_destination_status": data.get("final_destination_status", "unknown"),
        "astar_destination_status": data.get("astar_destination_status", "unknown"),
        "requires_final_local": bool(data.get("requires_final_local", False)),
        "unique_astar_target_count": len(unique_astar_targets),
        "xs": xs,
        "ys": ys,
        "zs": zs,
        "labels": labels,
        "segments": segments,
    }


def parse_cells(cells: dict, cell_size: float):
    obs_xs, obs_ys, obs_zs = [], [], []
    dng_xs, dng_ys, dng_zs = [], [], []
    cxs, cys, czs = [], [], []
    for key, val in cells.items():
        parts = key.split("_")
        if len(parts) != 3:
            continue
        try:
            cx, cy, cz = int(parts[0]), int(parts[1]), int(parts[2])
        except ValueError:
            continue
        wx = (cx + 0.5) * cell_size
        wy = (cy + 0.5) * cell_size
        wz = (cz + 0.5) * cell_size
        if val >= 2:
            obs_xs.append(wx)
            obs_ys.append(wy)
            obs_zs.append(wz)
        elif val == 1:
            dng_xs.append(wx)
            dng_ys.append(wy)
            dng_zs.append(wz)
        else:
            cxs.append(wx)
            cys.append(wy)
            czs.append(wz)
    return obs_xs, obs_ys, obs_zs, dng_xs, dng_ys, dng_zs, cxs, cys, czs


def collect_visual_data(data_path: Path, route_path: Path, no_obstacles: bool, no_clear: bool, verbose: bool = False, force_mode: str | None = None):
    obs_xs, obs_ys, obs_zs = [], [], []
    dng_xs, dng_ys, dng_zs = [], [], []
    cxs, cys, czs = [], [], []

    if no_obstacles and no_clear:
        if verbose:
            print("Obstacle display skipped (--no-obstacles --no-clear)")
    else:
        mode, src = resolve_map_source(data_path, force_mode)
        if mode == "bin":
            cell_size, states, stats = load_bin_map(src)
            obs_xs, obs_ys, obs_zs = states[V_BLOCKED]
            dng_xs, dng_ys, dng_zs = states[V_DANGER]
            cxs, cys, czs = states[V_CLEAR]
            if verbose:
                print(f"Loading packed obstacle map (DAVOB4): {src}")
                print(f"  Enumerated by    : {stats['enumerated_by']}")
                print(f"  Chunks read      : {stats['chunks']} / {stats['listed']}")
                if stats["skipped"]:
                    print(f"  Skipped          : {', '.join(stats['skipped'][:8])}"
                          + (" ..." if len(stats['skipped']) > 8 else ""))
                print(f"  Cell size        : {cell_size} m")
                print(f"  Obstacle cells   : {len(obs_xs)}")
                print(f"  Danger cells     : {len(dng_xs)}")
                print(f"  Confirmed-clear  : {len(cxs)}")
                print(f"  (UNKNOWN cells are not stored and are not drawn)")
        else:
            chunk_files = list(src.glob("chunk_*.dat")) if src.is_dir() else []
            if not chunk_files:
                if verbose:
                    print(f"[INFO] No chunk files found in: {src}")
            else:
                cell_size, cells = load_obstacle_map_chunked(src)
                obs_xs, obs_ys, obs_zs, dng_xs, dng_ys, dng_zs, cxs, cys, czs = parse_cells(cells, cell_size)
                if verbose:
                    print(f"Loading text obstacle map (legacy v3): {src}")
                    print(f"  Chunk files found  : {len(chunk_files)}")
                    print(f"  Total cells loaded : {len(cells)}")
                    print(f"  Obstacle cells     : {len(obs_xs)}")
                    print(f"  Danger cells       : {len(dng_xs)}")
                    print(f"  Confirmed-clear cells              : {len(cxs)}")
        if no_obstacles:
            obs_xs, obs_ys, obs_zs = [], [], []
            dng_xs, dng_ys, dng_zs = [], [], []
        if no_clear:
            cxs, cys, czs = [], [], []

    route = load_route(route_path)
    if verbose:
        if route:
            print(f"Loading A* route     : {route_path}")
            print(f"  Waypoints          : {len(route['xs'])}")
            print(f"  Start              : {route['start_pos']}")
            print(f"  Goal               : {route['end_pos']}")
            print(f"  Original Dest      : {route.get('original_destination_pos')}")
            print(f"  Final Dest         : {route.get('final_destination_pos')}")
            print(f"  A* Dest            : {route.get('astar_destination_pos')}")
        else:
            print(f"[INFO] last_route.json not found ({route_path}).")

    return {
        "obs_xs": obs_xs,
        "obs_ys": obs_ys,
        "obs_zs": obs_zs,
        "dng_xs": dng_xs,
        "dng_ys": dng_ys,
        "dng_zs": dng_zs,
        "cxs": cxs,
        "cys": cys,
        "czs": czs,
        "route": route,
    }


def render_pyvista(data: dict, out_path: Path | None, show_clear: bool, reload_loader=None):
    try:
        import numpy as np
        import pyvista as pv
    except ImportError:
        print("pyvista not installed. Run: pip install pyvista", file=sys.stderr)
        sys.exit(1)

    plotter = pv.Plotter(window_size=(1600, 900), title="DriveAerialVehicle - Obstacle Map (PyVista)")
    plotter.set_background("#0d0d1a")
    plotter.add_axes(line_width=1, color="white")
    route_actor_names = []

    def remove_actor(name: str):
        try:
            plotter.remove_actor(name, reset_camera=False, render=False)
        except Exception:
            pass

    def clear_route_actors():
        while route_actor_names:
            remove_actor(route_actor_names.pop())

    def register_route_actor(name: str):
        route_actor_names.append(name)

    def set_points(name: str, xs, ys, zs, color, size, opacity):
        remove_actor(name)
        # len() rather than truthiness: the packed loader hands back numpy arrays,
        # and `not <ndarray>` raises instead of meaning "empty".
        if xs is None or len(xs) == 0:
            return
        pts = np.column_stack([xs, ys, zs]).astype(np.float32)
        cloud = pv.PolyData(pts)
        plotter.add_points(cloud, color=color, point_size=size, opacity=opacity, render_points_as_spheres=False, name=name)

    def draw(cur: dict):
        obs_xs = cur["obs_xs"]
        obs_ys = cur["obs_ys"]
        obs_zs = cur["obs_zs"]
        dng_xs = cur["dng_xs"]
        dng_ys = cur["dng_ys"]
        dng_zs = cur["dng_zs"]
        cxs = cur["cxs"]
        cys = cur["cys"]
        czs = cur["czs"]
        route = cur["route"]

        if show_clear:
            set_points("pts_clear", cxs, cys, czs, "#88ddaa", 2, 0.18)
        else:
            remove_actor("pts_clear")
        set_points("pts_danger", dng_xs, dng_ys, dng_zs, "#ffbb77", 2, 0.30)
        set_points("pts_obstacle", obs_xs, obs_ys, obs_zs, "#dd2233", 3, 0.70)

        clear_route_actors()

        if route and route["xs"]:
            if route.get("segments"):
                for segment in route["segments"]:
                    actor_suffix = f"_{segment['index']}"
                    line_name = f"route_line{actor_suffix}"
                    wpt_name = f"route_wpts{actor_suffix}"
                    color = get_segment_color(segment.get("index", 1))
                    rpts = np.column_stack([segment["xs"], segment["ys"], segment["zs"]]).astype(np.float32)
                    if len(rpts) >= 2:
                        route_line = pv.lines_from_points(rpts, close=False)
                        plotter.add_mesh(route_line, color=color, line_width=4, name=line_name)
                        register_route_actor(line_name)
                    pts = np.column_stack([segment["xs"], segment["ys"], segment["zs"]]).astype(np.float32)
                    cloud = pv.PolyData(pts)
                    plotter.add_points(
                        cloud,
                        color=color,
                        point_size=5,
                        opacity=0.95,
                        render_points_as_spheres=False,
                        name=wpt_name,
                    )
                    register_route_actor(wpt_name)
            else:
                rpts = np.column_stack([route["xs"], route["ys"], route["zs"]]).astype(np.float32)
                if len(rpts) >= 2:
                    route_line = pv.lines_from_points(rpts, close=False)
                    plotter.add_mesh(route_line, color="#ffe55c", line_width=3, name="route_line")
                    register_route_actor("route_line")
                pts = np.column_stack([route["xs"], route["ys"], route["zs"]]).astype(np.float32)
                cloud = pv.PolyData(pts)
                plotter.add_points(
                    cloud,
                    color="#ffe55c",
                    point_size=4,
                    opacity=0.85,
                    render_points_as_spheres=False,
                    name="route_wpts",
                )
                register_route_actor("route_wpts")

            sp = route["start_pos"]
            ep = route.get("final_destination_pos") or route["end_pos"]
            set_points("route_start", [sp[0]], [sp[1]], [sp[2]], "#44ff88", 12, 1.0)
            set_points("route_goal", [ep[0]], [ep[1]], [ep[2]], "#ff5555", 12, 1.0)
            original_goal = route.get("original_destination_pos")
            if original_goal:
                set_points("route_original_goal", [original_goal[0]], [original_goal[1]], [original_goal[2]], "#ff88aa", 11, 1.0)
                register_route_actor("route_original_goal")
            else:
                remove_actor("route_original_goal")
            astar_goal = route.get("astar_destination_pos")
            if astar_goal:
                set_points("route_astar_goal", [astar_goal[0]], [astar_goal[1]], [astar_goal[2]], "#55d6ff", 11, 1.0)
                register_route_actor("route_astar_goal")
            else:
                remove_actor("route_astar_goal")
            register_route_actor("route_start")
            register_route_actor("route_goal")

        stats = f"Obstacle: {len(obs_xs)}\nDanger: {len(dng_xs)}\nClear: {len(cxs)}"
        if route and route.get("segments"):
            stats += f"\nRoute Segments: {len(route['segments'])}"
        if route:
            stats += f"\nRequires final_local: {route.get('requires_final_local', False)}"
            stats += f"\nFinal Dest Status: {route.get('final_destination_status', 'unknown')}"
            stats += f"\nA* Dest Status: {route.get('astar_destination_status', 'unknown')}"
            stats += f"\nUnique A* Targets: {route.get('unique_astar_target_count', 0)}"
            stats += f"\nOriginal Dest: {route.get('original_destination_pos')}"
            stats += f"\nFinal Dest: {route.get('final_destination_pos') or route.get('end_pos')}"
            stats += f"\nA* Dest: {route.get('astar_destination_pos')}"
        remove_actor("stats_text")
        plotter.add_text(stats, position="upper_left", font_size=10, color="#ddddee", name="stats_text")

    draw(data)

    if reload_loader and out_path is None:
        busy = {"v": False}

        def on_reload(_state=None):
            if busy["v"]:
                return
            busy["v"] = True
            try:
                new_data = reload_loader()
                draw(new_data)
                plotter.render()
                print("[Reload] obstacle map/route reloaded.")
            finally:
                busy["v"] = False

        plotter.add_checkbox_button_widget(on_reload, value=False, position=(12, 12), size=24)
        plotter.add_text("Reload", position=(42, 14), font_size=10, color="#ddddee")
        plotter.add_key_event("r", on_reload)

    if out_path:
        suffix = out_path.suffix.lower()
        if suffix in {".png", ".jpg", ".jpeg", ".bmp", ".tif", ".tiff"}:
            plotter.show(auto_close=False)
            plotter.screenshot(str(out_path))
            plotter.close()
            print(f"Saved to {out_path}")
        else:
            plotter.close()
            print("Unsupported output extension for PyVista. Use image formats like .png", file=sys.stderr)
            sys.exit(1)
    else:
        plotter.show()


def main():
    parser = argparse.ArgumentParser(description="Visualize DriveAerialVehicle 3D obstacle map and A* route (PyVista).")
    parser.add_argument("--data", type=Path, default=None,
                      help="Map directory. Packed Data/map_bin is preferred and is "
                           "auto-detected even when you point at Data/map.")
    parser.add_argument("--bin", type=Path, default=None,
                      help="Force packed DAVOB4 chunks from this directory")
    parser.add_argument("--text", type=Path, default=None,
                      help="Force legacy text v3 chunks from this directory")
    parser.add_argument("--route", type=Path, default=DEFAULT_ROUTE_PATH, help="Path to last_route.json")
    parser.add_argument("--min", type=int, default=1, metavar="N", help="Minimum value to show obstacle cell (default: 1)")
    parser.add_argument("--max", type=int, default=None, metavar="N", help=argparse.SUPPRESS)
    parser.add_argument("--out", type=Path, default=None, metavar="FILE", help="Save to image file")
    parser.add_argument("--no-obstacles", action="store_true", help="Hide obstacle cells (show route only)")
    parser.add_argument("--no-clear", action="store_true", help="Hide confirmed-clear cells")
    args = parser.parse_args()

    if args.bin is not None and args.text is not None:
        parser.error("--bin and --text are mutually exclusive")

    force_mode = None
    if args.bin is not None:
        data_path, force_mode = args.bin.resolve(), "bin"
    elif args.text is not None:
        data_path, force_mode = args.text.resolve(), "text"
    else:
        data_path = (args.data.resolve() if args.data is not None else DEFAULT_MAP_DIR.resolve())
    route_path = args.route.resolve()

    print(f"Data directory : {data_path}")
    print(f"Route file     : {route_path}")

    data = collect_visual_data(data_path, route_path, args.no_obstacles,
                              args.no_clear, verbose=True, force_mode=force_mode)
    if (len(data["obs_xs"]) == 0 and len(data["dng_xs"]) == 0
            and len(data["cxs"]) == 0
            and (data["route"] is None or not data["route"]["xs"])):
        print("[WARNING] Nothing to plot. Collect some data first.")
        print(f"          Looked for chunk_*.bin / chunk_*.dat under: {data_path}")
        print("          Override with --bin DIR or --text DIR.")
        sys.exit(0)

    print("Rendering with pyvista ...")
    show_clear = not args.no_clear
    reload_loader = None if args.out else (
        lambda: collect_visual_data(data_path, route_path, args.no_obstacles,
                                  args.no_clear, verbose=False, force_mode=force_mode))
    render_pyvista(data, args.out, show_clear, reload_loader)


if __name__ == "__main__":
    main()
