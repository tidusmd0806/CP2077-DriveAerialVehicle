"""
visualize_obstacle_map.py
=========================
DriveAerialVehicle mod - 3D Obstacle Map + A* Route Visualizer

Reads Data/obstacle_map.dat (or legacy .json), Data/last_route.json, and optionally
Data/sector_danger_map.json, then renders an interactive 3D view so
developers can see:
  - Recorded obstacle positions (coloured by hit count)
  - The last A* route (yellow line with start/goal markers)
  - Blocked sectors from the sector danger map (cyan diamonds)

Usage
-----
  python visualize_obstacle_map.py [options]

Options
-------
  --data   PATH   Path to obstacle_map.dat  (or legacy .json)
                  (default: ../Data/obstacle_map.dat)
  --route  PATH   Path to last_route.json
                  (default: ../Data/last_route.json)
  --sector PATH   Path to sector_danger_map.json  (optional overlay)
  --min    N      Minimum hit count to show an obstacle cell  (default: 2)
  --max    N      Cap colour scale at this hit count (default: auto)
  --engine NAME   Rendering backend: "matplotlib" or "plotly"  (default: auto)
  --out    FILE   Save to file instead of interactive window
                  (matplotlib: .png/.pdf; plotly: .html)
  --no-obstacles  Hide obstacle cells (show route + sectors only)

Requirements
------------
  pip install matplotlib             # for matplotlib backend
  pip install plotly kaleido         # for plotly backend (kaleido for --out)

File format expected
--------------------
  obstacle_map.dat:
    Line 1 : "DAV_OBMAP v2 cell_size=<float>"
    Lines 2+: "<cx> <cy> <cz> <count>"  (integer cell coords, may be negative)
    hit cells (count>=1) and clear cells (count=0) both saved, no caps.

  last_route.json (written by mod on each autopilot start):
    { "version": 1, "sector_size": 25,
      "start_pos": {"x":...,"y":...,"z":...},
      "end_pos":   {"x":...,"y":...,"z":...},
      "waypoints": [ {"key":"sx_sy_sz", "wx":...,"wy":...,"wz":...}, ... ] }

  sector_danger_map.json (optional overlay):
    { "version": 4, "sector_size": 25,
      "sectors": { "sx_sy_sz": { "connections": { ... } }, ... } }
"""

import argparse
import json
import os
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# I/O helpers
# ---------------------------------------------------------------------------

SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_OBSTACLE_PATH = SCRIPT_DIR / ".." / "Data" / "obstacle_map.dat"
DEFAULT_ROUTE_PATH    = SCRIPT_DIR / ".." / "Data" / "last_route.json"
DEFAULT_SECTOR_PATH   = SCRIPT_DIR / ".." / "Data" / "sector_danger_map.json"


def load_obstacle_map(path: Path):
    """Return (cell_size, cells_dict) where cells_dict = {"cx_cy_cz": count}.

    Reads compact .dat format (DAV_OBMAP v2 header).
    """
    import re
    content = path.read_text(encoding="utf-8")
    m = re.search(r"cell_size=([\d.]+)", content.split("\n", 1)[0])
    cell_size = float(m.group(1)) if m else 10.0
    cells: dict = {}
    for line in content.splitlines()[1:]:
        parts = line.split()
        if len(parts) == 4:
            try:
                cx, cy, cz, cnt = int(parts[0]), int(parts[1]), int(parts[2]), int(parts[3])
                cells[f"{cx}_{cy}_{cz}"] = cnt
            except ValueError:
                pass
    return cell_size, cells


def load_sector_map(path: Path):
    """Return (sector_size, sectors_dict).  Returns (25, {}) if file missing."""
    if not path.exists():
        return 25.0, {}
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    sector_size = float(data.get("sector_size", 25.0))
    sectors     = data.get("sectors", {})
    return sector_size, sectors


def load_route(path: Path):
    """
    Load last_route.json.
    Returns a dict with keys:
      sector_size, start_pos, end_pos,
      xs, ys, zs  (world-space waypoint centres),
      labels       (list of sector key strings)
    Returns None if file does not exist.
    """
    if not path.exists():
        return None
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    if data.get("version") != 1:
        print(f"[WARNING] Unexpected last_route.json version: {data.get('version')}",
              file=sys.stderr)
    ss = float(data.get("sector_size", 25.0))
    waypoints = data.get("waypoints", [])
    xs, ys, zs, labels = [], [], [], []
    for wp in waypoints:
        xs.append(float(wp.get("wx", 0)))
        ys.append(float(wp.get("wy", 0)))
        zs.append(float(wp.get("wz", 0)))
        labels.append(wp.get("key", ""))
    sp = data.get("start_pos", {})
    ep = data.get("end_pos",   {})
    return dict(
        sector_size = ss,
        start_pos   = (float(sp.get("x", 0)), float(sp.get("y", 0)), float(sp.get("z", 0))),
        end_pos     = (float(ep.get("x", 0)), float(ep.get("y", 0)), float(ep.get("z", 0))),
        xs=xs, ys=ys, zs=zs,
        labels=labels,
    )


# ---------------------------------------------------------------------------
# Data preparation
# ---------------------------------------------------------------------------

def parse_cells(cells: dict, cell_size: float, min_hits: int):
    """
    Convert the cell dict to two sets of arrays.

    Returns
    -------
    (xs, ys, zs, counts)  – obstacle cells (count >= min_hits)
    (cxs, cys, czs)       – confirmed-clear cells (count == 0)

    World position of each cell centre = (ci + 0.5) * cell_size.
    """
    xs, ys, zs, counts = [], [], [], []
    cxs, cys, czs = [], [], []  # confirmed-clear cells
    for key, count in cells.items():
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
        if count == 0:
            cxs.append(wx)
            cys.append(wy)
            czs.append(wz)
        elif count >= min_hits:
            xs.append(wx)
            ys.append(wy)
            zs.append(wz)
            counts.append(count)
    return xs, ys, zs, counts, cxs, cys, czs


def parse_blocked_sectors(sectors: dict, sector_size: float):
    """
    Return blocked sector centre positions (wx, wy, wz) where
    at least one direction is explicitly blocked (connections[key] == False).
    """
    bxs, bys, bzs = [], [], []
    for key, sector in sectors.items():
        if not isinstance(sector, dict):
            continue
        conns = sector.get("connections", {})
        if any(v is False for v in conns.values()):
            parts = key.split("_")
            if len(parts) == 3:
                try:
                    sx, sy, sz = int(parts[0]), int(parts[1]), int(parts[2])
                    bxs.append((sx + 0.5) * sector_size)
                    bys.append((sy + 0.5) * sector_size)
                    bzs.append((sz + 0.5) * sector_size)
                except ValueError:
                    pass
    return bxs, bys, bzs


# ---------------------------------------------------------------------------
# Matplotlib backend
# ---------------------------------------------------------------------------

def render_matplotlib(xs, ys, zs, counts, cxs, cys, czs, bxs, bys, bzs, route, cap_count, out_path, show_clear=True):
    import matplotlib.pyplot as plt
    import matplotlib.cm as cm
    import matplotlib.colors as mcolors
    import numpy as np

    fig = plt.figure(figsize=(14, 10))
    ax  = fig.add_subplot(111, projection="3d")
    ax.set_facecolor("#1a1a2e")
    fig.patch.set_facecolor("#1a1a2e")

    # --- confirmed-clear cells (count == 0) ---
    if show_clear and cxs:
        ax.scatter(cxs, cys, czs, c="#00e5b0", marker=".", s=6, alpha=0.25,
                   label=f"Confirmed clear ({len(cxs)})")

    # --- obstacle cells ---
    if xs:
        cap = cap_count or max(counts)
        norm = mcolors.Normalize(vmin=1, vmax=cap)
        cmap = cm.get_cmap("plasma")
        colours = [cmap(norm(min(c, cap))) for c in counts]
        sizes   = [max(10, min(60, c * 3)) for c in counts]

        sc = ax.scatter(xs, ys, zs, c=counts, cmap="plasma",
                        vmin=1, vmax=cap,
                        s=sizes, alpha=0.75, depthshade=True,
                        label=f"Obstacle cells ({len(xs)})")

        cb = fig.colorbar(sc, ax=ax, pad=0.12, shrink=0.7)
        cb.set_label("Hit count", color="white")
        cb.ax.yaxis.set_tick_params(color="white")
        plt.setp(plt.getp(cb.ax.axes, "yticklabels"), color="white")

    # --- blocked sectors overlay ---
    if bxs:
        ax.scatter(bxs, bys, bzs, c="cyan", marker="^", s=40, alpha=0.4,
                   label=f"Blocked sectors ({len(bxs)})")

    # Styling
    ax.set_xlabel("X (m)", color="white")
    ax.set_ylabel("Y (m)", color="white")
    ax.set_zlabel("Z (m)", color="white")
    ax.set_title("DriveAerialVehicle – 3D Obstacle Map", color="white", pad=15)
    ax.tick_params(colors="white")
    ax.xaxis.pane.set_edgecolor("gray")
    ax.yaxis.pane.set_edgecolor("gray")
    ax.zaxis.pane.set_edgecolor("gray")
    ax.xaxis.pane.fill = False
    ax.yaxis.pane.fill = False
    ax.zaxis.pane.fill = False

    legend = ax.legend(loc="upper left", facecolor="#22223b", labelcolor="white",
                       framealpha=0.8)

    # --- A* route ---
    if route and route["xs"]:
        rx, ry, rz = route["xs"], route["ys"], route["zs"]
        # Route line
        ax.plot(rx, ry, rz, color="yellow", linewidth=2.0, alpha=0.9,
                label=f"A* route ({len(rx)} sectors)")
        # Waypoint dots
        ax.scatter(rx, ry, rz, color="yellow", s=20, alpha=0.7, zorder=5)
        # Start marker
        sp = route["start_pos"]
        ax.scatter([sp[0]], [sp[1]], [sp[2]], color="lime", s=120, marker="^",
                   zorder=6, label="Start (actual)")
        ax.text(sp[0], sp[1], sp[2], "  START", color="lime", fontsize=8)
        # Goal marker
        ep = route["end_pos"]
        ax.scatter([ep[0]], [ep[1]], [ep[2]], color="red", s=120, marker="*",
                   zorder=6, label="Goal (actual)")
        ax.text(ep[0], ep[1], ep[2], "  GOAL", color="red", fontsize=8)
        # Waypoint index labels (every 5th to avoid clutter)
        for i, (lx, ly, lz, lbl) in enumerate(
                zip(rx, ry, rz, route["labels"])):
            if i % 5 == 0:
                ax.text(lx, ly, lz, f" {i}", color="lightyellow",
                        fontsize=6, alpha=0.8)

    legend = ax.legend(loc="upper left", facecolor="#22223b", labelcolor="white",
                       framealpha=0.8)
    if counts:
        stats = (
            f"Cells shown : {len(xs)}\n"
            f"Max hits    : {max(counts)}\n"
            f"Mean hits   : {sum(counts)/len(counts):.1f}\n"
            f"Clear cells : {len(cxs)}"
        )
    elif cxs:
        stats = f"Clear cells : {len(cxs)}\nNo obstacle cells yet"
    elif route and route["xs"]:
        stats = f"Route waypoints: {len(route['xs'])}"
    else:
        stats = "No obstacle data"
    ax.text2D(0.01, 0.01, stats, transform=ax.transAxes,
              color="lightgray", fontsize=9, va="bottom",
              bbox=dict(facecolor="#22223b", alpha=0.7, edgecolor="none"))

    plt.tight_layout()
    if out_path:
        plt.savefig(out_path, dpi=150, bbox_inches="tight",
                    facecolor=fig.get_facecolor())
        print(f"Saved to {out_path}")
    else:
        plt.show()


# ---------------------------------------------------------------------------
# Plotly backend (interactive HTML)
# ---------------------------------------------------------------------------

def render_plotly(xs, ys, zs, counts, cxs, cys, czs, bxs, bys, bzs, route, cap_count, out_path, show_clear=True):
    try:
        import plotly.graph_objects as go
    except ImportError:
        print("plotly not installed.  Run: pip install plotly", file=sys.stderr)
        sys.exit(1)

    traces = []

    # --- confirmed-clear cells (count == 0) ---
    if show_clear and cxs:
        traces.append(go.Scatter3d(
            x=cxs, y=cys, z=czs,
            mode="markers",
            name=f"Confirmed clear ({len(cxs)})",
            marker=dict(size=2, color="#00e5b0", opacity=0.25, symbol="circle"),
            hovertemplate=(
                "X: %{x:.0f} m<br>"
                "Y: %{y:.0f} m<br>"
                "Z: %{z:.0f} m<br>"
                "Hits: 0 (confirmed clear)<extra></extra>"
            )
        ))

    if xs:
        cap = cap_count or max(counts)
        traces.append(go.Scatter3d(
            x=xs, y=ys, z=zs,
            mode="markers",
            name=f"Obstacle cells ({len(xs)})",
            marker=dict(
                size=[max(2, min(10, c * 0.6)) for c in counts],
                color=counts,
                colorscale="Plasma",
                cmin=1, cmax=cap,
                opacity=0.8,
                colorbar=dict(title="Hit count")
            ),
            hovertemplate=(
                "X: %{x:.0f} m<br>"
                "Y: %{y:.0f} m<br>"
                "Z: %{z:.0f} m<br>"
                "Hits: %{marker.color}<extra></extra>"
            )
        ))

    if bxs:
        traces.append(go.Scatter3d(
            x=bxs, y=bys, z=bzs,
            mode="markers",
            name=f"Blocked sectors ({len(bxs)})",
            marker=dict(size=4, color="cyan", opacity=0.35, symbol="diamond")
        ))

    # --- A* route ---
    if route and route["xs"]:
        rx, ry, rz = route["xs"], route["ys"], route["zs"]
        # Route line
        traces.append(go.Scatter3d(
            x=rx, y=ry, z=rz,
            mode="lines+markers",
            name=f"A* route ({len(rx)} sectors)",
            line=dict(color="yellow", width=5),
            marker=dict(size=3, color="yellow", opacity=0.8),
            hovertemplate=(
                "Sector: %{text}<br>"
                "X: %{x:.0f} m<br>Y: %{y:.0f} m<br>Z: %{z:.0f} m"
                "<extra>A* waypoint</extra>"
            ),
            text=route["labels"],
        ))
        # Start marker
        sp = route["start_pos"]
        traces.append(go.Scatter3d(
            x=[sp[0]], y=[sp[1]], z=[sp[2]],
            mode="markers+text",
            name="Start (actual)",
            marker=dict(size=12, color="lime", symbol="diamond"),
            text=["START"], textfont=dict(color="lime", size=12),
            textposition="top center",
            hovertemplate=f"START<br>X:{sp[0]:.1f} Y:{sp[1]:.1f} Z:{sp[2]:.1f}<extra></extra>"
        ))
        # Goal marker
        ep = route["end_pos"]
        traces.append(go.Scatter3d(
            x=[ep[0]], y=[ep[1]], z=[ep[2]],
            mode="markers+text",
            name="Goal (actual)",
            marker=dict(size=14, color="red", symbol="x"),
            text=["GOAL"], textfont=dict(color="red", size=12),
            textposition="top center",
            hovertemplate=f"GOAL<br>X:{ep[0]:.1f} Y:{ep[1]:.1f} Z:{ep[2]:.1f}<extra></extra>"
        ))

    layout = go.Layout(
        title=dict(
            text="DriveAerialVehicle – 3D Obstacle Map",
            font=dict(color="white")
        ),
        scene=dict(
            xaxis=dict(title="X (m)", backgroundcolor="#0d0d1a",
                       gridcolor="gray", showbackground=True),
            yaxis=dict(title="Y (m)", backgroundcolor="#0d0d1a",
                       gridcolor="gray", showbackground=True),
            zaxis=dict(title="Z (m)", backgroundcolor="#0d0d1a",
                       gridcolor="gray", showbackground=True),
            aspectmode="data"
        ),
        paper_bgcolor="#1a1a2e",
        plot_bgcolor="#1a1a2e",
        font=dict(color="white"),
        legend=dict(bgcolor="#22223b", bordercolor="gray")
    )

    fig = go.Figure(data=traces, layout=layout)

    if out_path:
        try:
            fig.write_image(str(out_path), width=1400, height=900)
            print(f"Saved to {out_path}")
        except Exception as e:
            # Fall back to HTML
            html_path = Path(str(out_path)).with_suffix(".html")
            fig.write_html(str(html_path))
            print(f"Image export failed ({e}); saved HTML to {html_path}")
    else:
        fig.show()
# ---------------------------------------------------------------------------
# Auto-detect best engine
# ---------------------------------------------------------------------------

def detect_engine():
    try:
        import plotly  # noqa
        return "plotly"
    except ImportError:
        pass
    try:
        import matplotlib  # noqa
        return "matplotlib"
    except ImportError:
        pass
    return None


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Visualize the DriveAerialVehicle 3D obstacle map and A* route."
    )
    parser.add_argument(
        "--data", type=Path, default=DEFAULT_OBSTACLE_PATH,
        help="Path to obstacle_map.dat (or legacy .json)"
    )
    parser.add_argument(
        "--route", type=Path, default=DEFAULT_ROUTE_PATH,
        help="Path to last_route.json (written by mod on each autopilot start)"
    )
    parser.add_argument(
        "--sector", type=Path, default=DEFAULT_SECTOR_PATH,
        help="Path to sector_danger_map.json (optional overlay)"
    )
    parser.add_argument(
        "--min", type=int, default=2, metavar="N",
        help="Minimum hit count to display an obstacle cell (default: 2)"
    )
    parser.add_argument(
        "--max", type=int, default=None, metavar="N",
        help="Cap colour scale at this hit count (default: auto)"
    )
    parser.add_argument(
        "--engine", choices=["matplotlib", "plotly"], default=None,
        help="Rendering backend (default: auto-detect; prefers plotly)"
    )
    parser.add_argument(
        "--out", type=Path, default=None, metavar="FILE",
        help="Save to file instead of interactive window"
    )
    parser.add_argument(
        "--no-obstacles", action="store_true",
        help="Hide obstacle cells (show route + sector data only)"
    )
    parser.add_argument(
        "--no-clear", action="store_true",
        help="Hide confirmed-clear (hit=0) cells"
    )
    args = parser.parse_args()

    # --- Load obstacle map ---
    xs, ys, zs, counts = [], [], [], []
    cxs, cys, czs = [], [], []  # confirmed-clear cells
    data_path = args.data.resolve()
    if args.no_obstacles and args.no_clear:
        print("Obstacle display skipped (--no-obstacles --no-clear)")
    elif not data_path.exists():
        print(f"[INFO] obstacle_map.dat not found: {data_path}")
        print("  Enable recording from the debug menu, drive around, then save.")
    else:
        print(f"Loading obstacle map : {data_path}")
        cell_size, cells = load_obstacle_map(data_path)
        print(f"  Total cells in file : {len(cells)}")
        xs, ys, zs, counts, cxs, cys, czs = parse_cells(cells, cell_size, args.min)
        if args.no_obstacles:
            xs, ys, zs, counts = [], [], [], []
        if args.no_clear:
            cxs, cys, czs = [], [], []
        print(f"  Obstacle cells (min={args.min}) : {len(xs)}")
        print(f"  Confirmed-clear cells (hit=0) : {len(cxs)}")

    # --- Load A* route ---
    route_path = args.route.resolve()
    route = None
    if route_path.exists():
        print(f"Loading A* route     : {route_path}")
        route = load_route(route_path)
        if route:
            print(f"  Waypoints          : {len(route['xs'])}")
            print(f"  Start              : {route['start_pos']}")
            print(f"  Goal               : {route['end_pos']}")
    else:
        print(f"[INFO] last_route.json not found ({route_path}).")
        print("  Start autopilot once to generate it.")

    # --- Load sector map ---
    sector_path = args.sector.resolve()
    bxs, bys, bzs = [], [], []
    if sector_path.exists():
        print(f"Loading sector map   : {sector_path}")
        sector_size, sectors = load_sector_map(sector_path)
        bxs, bys, bzs = parse_blocked_sectors(sectors, sector_size)
        if bxs:
            print(f"  Blocked sectors    : {len(bxs)}")

    if not xs and not cxs and not bxs and (route is None or not route["xs"]):
        print("[WARNING] Nothing to plot.  Collect some data first.")
        sys.exit(0)

    # --- Render ---
    engine = args.engine or detect_engine()
    if engine is None:
        print("[ERROR] No rendering backend found.  Install matplotlib or plotly:",
              file=sys.stderr)
        print("  pip install matplotlib", file=sys.stderr)
        print("  pip install plotly", file=sys.stderr)
        sys.exit(1)

    print(f"Rendering with {engine} …")
    show_clear = not args.no_clear

    if engine == "plotly":
        render_plotly(xs, ys, zs, counts, cxs, cys, czs, bxs, bys, bzs, route, args.max, args.out, show_clear)
    else:
        render_matplotlib(xs, ys, zs, counts, cxs, cys, czs, bxs, bys, bzs, route, args.max, args.out, show_clear)


if __name__ == "__main__":
    main()
