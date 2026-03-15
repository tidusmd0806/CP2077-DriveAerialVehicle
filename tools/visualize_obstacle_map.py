"""
visualize_obstacle_map.py
=========================
DriveAerialVehicle mod - PyVista obstacle map visualizer.

Loads:
  - Data/map/chunk_*.dat
  - Data/last_route.json (optional)

Renders a native VTK window (no browser) with obstacle/danger/clear points
and the latest A* route. Includes an in-window Reload button and R hotkey.
"""

import argparse
import json
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_MAP_DIR = SCRIPT_DIR / "Data" / "map"
DEFAULT_ROUTE_PATH = SCRIPT_DIR / "Data" / "last_route.json"


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


def collect_visual_data(data_path: Path, route_path: Path, no_obstacles: bool, no_clear: bool, verbose: bool = False):
    obs_xs, obs_ys, obs_zs = [], [], []
    dng_xs, dng_ys, dng_zs = [], [], []
    cxs, cys, czs = [], [], []

    if no_obstacles and no_clear:
        if verbose:
            print("Obstacle display skipped (--no-obstacles --no-clear)")
    else:
        chunk_files = list(data_path.glob("chunk_*.dat")) if data_path.is_dir() else []
        if not chunk_files:
            if verbose:
                print(f"[INFO] No chunk files found in: {data_path}")
        else:
            cell_size, cells = load_obstacle_map_chunked(data_path)
            obs_xs, obs_ys, obs_zs, dng_xs, dng_ys, dng_zs, cxs, cys, czs = parse_cells(cells, cell_size)
            if no_obstacles:
                obs_xs, obs_ys, obs_zs = [], [], []
                dng_xs, dng_ys, dng_zs = [], [], []
            if no_clear:
                cxs, cys, czs = [], [], []
            if verbose:
                print(f"Loading chunked obstacle map: {data_path}")
                print(f"  Chunk files found  : {len(chunk_files)}")
                print(f"  Total cells loaded : {len(cells)}")
                print(f"  Obstacle cells     : {len(obs_xs)}")
                print(f"  Danger cells       : {len(dng_xs)}")
                print(f"  Confirmed-clear cells              : {len(cxs)}")

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
        if not xs:
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
    parser.add_argument("--data", type=Path, default=None, help="Path to Data/map/ (default: ./Data/map)")
    parser.add_argument("--route", type=Path, default=DEFAULT_ROUTE_PATH, help="Path to last_route.json")
    parser.add_argument("--min", type=int, default=1, metavar="N", help="Minimum value to show obstacle cell (default: 1)")
    parser.add_argument("--max", type=int, default=None, metavar="N", help=argparse.SUPPRESS)
    parser.add_argument("--out", type=Path, default=None, metavar="FILE", help="Save to image file")
    parser.add_argument("--no-obstacles", action="store_true", help="Hide obstacle cells (show route only)")
    parser.add_argument("--no-clear", action="store_true", help="Hide confirmed-clear cells")
    args = parser.parse_args()

    data_path = (args.data.resolve() if args.data is not None else DEFAULT_MAP_DIR.resolve())
    route_path = args.route.resolve()

    data = collect_visual_data(data_path, route_path, args.no_obstacles, args.no_clear, verbose=True)
    if (not data["obs_xs"] and not data["dng_xs"] and not data["cxs"] and (data["route"] is None or not data["route"]["xs"])):
        print("[WARNING] Nothing to plot. Collect some data first.")
        sys.exit(0)

    print("Rendering with pyvista ...")
    show_clear = not args.no_clear
    reload_loader = None if args.out else (lambda: collect_visual_data(data_path, route_path, args.no_obstacles, args.no_clear, verbose=False))
    render_pyvista(data, args.out, show_clear, reload_loader)


if __name__ == "__main__":
    main()
