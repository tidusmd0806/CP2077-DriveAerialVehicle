"""
visualize_obstacle_map.py
=========================
DriveAerialVehicle mod - 3D Obstacle Map + A* Route Visualizer

Reads chunked obstacle map files from Data/map/,
Data/last_route.json, and optionally Data/sector_danger_map.json,
then renders an interactive 3D view so
developers can see:
  - Recorded obstacle positions (coloured by hit count)
  - The last A* route (yellow line with start/goal markers)
  - Blocked sectors from the sector danger map (cyan diamonds)

Usage
-----
  python visualize_obstacle_map.py [options]

Options
-------
  --data   PATH   Path to Data/map/ directory containing chunk_*.dat files
                  (default: ./Data/map)
  --route  PATH   Path to last_route.json
                  (default: ./Data/last_route.json)
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
  Data/map/chunk_{X}_{Y}.dat  (v3 format):
    Line 1 : "DAV_OBMAP v3 cell_size=<float>"
    Lines 2+: "<cx> <cy> <cz> <value>"  (value: 1=obstacle, 0=clear)
    Each file covers a 500m×500m XY region (50 cells per side).

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
DEFAULT_MAP_DIR              = SCRIPT_DIR / "Data" / "map"
DEFAULT_ROUTE_PATH           = SCRIPT_DIR / "Data" / "last_route.json"
DEFAULT_SECTOR_PATH          = SCRIPT_DIR / "Data" / "sector_danger_map.json"
DEFAULT_EXCEPTION_AREA_PATH  = SCRIPT_DIR / "Data" / "autopilot_exception_area.json"


def _parse_dat_content(content: str, cells: dict):
    """Parse DAV_OBMAP v3 content into cells dict. Returns cell_size.
    Values: 2=obstacle, 1=danger, 0=clear. Higher priority wins on merge."""
    import re
    m = re.search(r"cell_size=([\d.]+)", content.split("\n", 1)[0])
    cell_size = float(m.group(1)) if m else 10.0
    for line in content.splitlines()[1:]:
        parts = line.split()
        if len(parts) == 4:
            try:
                cx, cy, cz, val = int(parts[0]), int(parts[1]), int(parts[2]), int(parts[3])
                key = f"{cx}_{cy}_{cz}"
                # Merge: higher priority wins (2=obstacle > 1=danger > 0=clear)
                if key not in cells or cells[key] < val:
                    cells[key] = val
            except ValueError:
                pass
    return cell_size


def load_obstacle_map_chunked(map_dir: Path):
    """Load all chunk_*.dat files from the map directory.

    Returns (cell_size, cells_dict) where cells_dict = {"cx_cy_cz": count}.
    """
    cells: dict = {}
    cell_size = 10.0
    chunk_files = sorted(map_dir.glob("chunk_*.dat"))
    for chunk_path in chunk_files:
        content = chunk_path.read_text(encoding="utf-8")
        if content.startswith("DAV_OBMAP"):
            cell_size = _parse_dat_content(content, cells)
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


def load_exception_areas(path: Path):
    """Load autopilot_exception_area.json.
    Returns list of dicts with keys: tag, min_x/max_x, min_y/max_y, min_z/max_z.
    Returns [] if file is missing.
    """
    if not path.exists():
        return []
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


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

def parse_cells(cells: dict, cell_size: float):
    """
    Convert the ternary cell dict to coordinate arrays.

    Returns
    -------
    (obs_xs, obs_ys, obs_zs)    – obstacle cells  (value == 2)  → red
    (dng_xs, dng_ys, dng_zs)    – danger cells    (value == 1)  → orange
    (cxs,    cys,    czs)       – clear cells     (value == 0)  → green

    World position of each cell centre = (ci + 0.5) * cell_size.
    """
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
            obs_xs.append(wx); obs_ys.append(wy); obs_zs.append(wz)
        elif val == 1:
            dng_xs.append(wx); dng_ys.append(wy); dng_zs.append(wz)
        else:
            cxs.append(wx);   cys.append(wy);   czs.append(wz)
    return obs_xs, obs_ys, obs_zs, dng_xs, dng_ys, dng_zs, cxs, cys, czs


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

# Distinct colours cycled for exception areas
_EA_COLORS = [
    "#ff8c00", "#ff4dcb", "#00ccff", "#88ff44",
    "#ff6655", "#ffcc00", "#cc44ff", "#00ff88",
    "#ff3355", "#5599ff", "#ffaa44", "#44ffcc",
]


def render_matplotlib(obs_xs, obs_ys, obs_zs, dng_xs, dng_ys, dng_zs, cxs, cys, czs, bxs, bys, bzs, route, out_path, show_clear=True, exception_areas=None):
    import matplotlib.pyplot as plt
    import numpy as np

    BG = "#0d0d1a"
    PANEL_BG = "#12122a"
    fig = plt.figure(figsize=(18, 9))
    fig.patch.set_facecolor(BG)

    # Left: 3-D perspective  |  Right: 2-D top-down (XY)
    ax3d = fig.add_subplot(1, 2, 1, projection="3d")
    ax2d = fig.add_subplot(1, 2, 2)
    for ax in (ax3d,):
        ax.set_facecolor(PANEL_BG)
    ax2d.set_facecolor(PANEL_BG)

    # ---- shared draw helper ----
    def _draw_obstacles(ax, is_3d):
        # confirmed-clear (light green)
        if show_clear and cxs:
            kw = dict(c="#88ddaa", marker=".", s=4, alpha=0.20,
                      label=f"Clear ({len(cxs)})")
            if is_3d:
                ax.scatter(cxs, cys, czs, **kw)
            else:
                ax.scatter(cxs, cys, **kw)

        # danger cells (light orange)
        if dng_xs:
            kw = dict(c="#ffbb77", marker=".", s=4, alpha=0.35,
                      label=f"Danger ({len(dng_xs)})")
            if is_3d:
                ax.scatter(dng_xs, dng_ys, dng_zs, **kw)
            else:
                ax.scatter(dng_xs, dng_ys, **kw)

        # obstacle cells (red, square)
        if obs_xs:
            kw = dict(c="#dd2233", marker="s", s=4, alpha=0.70,
                      label=f"Obstacle ({len(obs_xs)})")
            if is_3d:
                ax.scatter(obs_xs, obs_ys, obs_zs, **kw)
            else:
                ax.scatter(obs_xs, obs_ys, **kw)

    _draw_obstacles(ax3d, is_3d=True)
    _draw_obstacles(ax2d, is_3d=False)

    # blocked sectors
    if bxs:
        kw_blk = dict(c="cyan", marker="^", s=35, alpha=0.35,
                      label=f"Blocked sectors ({len(bxs)})")
        ax3d.scatter(bxs, bys, bzs, **kw_blk)
        ax2d.scatter(bxs, bys, **kw_blk)

    # ---- exception areas ----
    if exception_areas:
        import matplotlib.patches as mpatches
        _BOX_EDGES = [
            (0,1),(1,2),(2,3),(3,0),   # bottom face
            (4,5),(5,6),(6,7),(7,4),   # top face
            (0,4),(1,5),(2,6),(3,7),   # verticals
        ]
        for idx, ea in enumerate(exception_areas):
            col = _EA_COLORS[idx % len(_EA_COLORS)]
            x1, x2 = ea["min_x"], ea["max_x"]
            y1, y2 = ea["min_y"], ea["max_y"]
            z1, z2 = ea["min_z"], ea["max_z"]
            tag = ea.get("tag", f"area_{idx}")
            # 2-D rectangle (XY top-down)
            rect = mpatches.Rectangle(
                (x1, y1), x2 - x1, y2 - y1,
                linewidth=1.2, edgecolor=col,
                facecolor=col, alpha=0.10,
                label=f"EA: {tag}",
            )
            ax2d.add_patch(rect)
            ax2d.text((x1+x2)/2, (y1+y2)/2,
                      tag.replace("_", "\n"),
                      color=col, fontsize=5.5, ha="center", va="center", alpha=0.90,
                      bbox=dict(facecolor="#0d0d1a", alpha=0.55,
                                edgecolor="none", pad=1.5))
            # 3-D wireframe box
            vx = [x1,x2,x2,x1, x1,x2,x2,x1]
            vy = [y1,y1,y2,y2, y1,y1,y2,y2]
            vz = [z1,z1,z1,z1, z2,z2,z2,z2]
            for a, b in _BOX_EDGES:
                ax3d.plot3D([vx[a],vx[b]], [vy[a],vy[b]], [vz[a],vz[b]],
                            color=col, linewidth=0.9, alpha=0.55)
            ax3d.text((x1+x2)/2, (y1+y2)/2, z2,
                      tag, color=col, fontsize=5, alpha=0.75)

    # A* route
    if route and route["xs"]:
        rx, ry, rz = route["xs"], route["ys"], route["zs"]
        lbl = f"A* route ({len(rx)} wpts)"

        ax3d.plot(rx, ry, rz, color="#ffe55c", lw=2, alpha=0.9, label=lbl)
        ax3d.scatter(rx, ry, rz, color="#ffe55c", s=14, alpha=0.7)
        ax2d.plot(rx, ry, color="#ffe55c", lw=2, alpha=0.9, label=lbl)
        ax2d.scatter(rx, ry, color="#ffe55c", s=14, alpha=0.7)

        sp = route["start_pos"]
        ep = route["end_pos"]
        for ax in (ax3d, ax2d):
            is3 = hasattr(ax, "scatter") and hasattr(ax, "set_zlabel")
            def _pos3(p): return ([p[0]], [p[1]], [p[2]]) if is3 else ([p[0]], [p[1]])
            pass

        # Start
        ax3d.scatter([sp[0]], [sp[1]], [sp[2]], color="#44ff88", s=140,
                     marker="^", zorder=6, label="Start")
        ax3d.text(sp[0], sp[1], sp[2], "  START", color="#44ff88", fontsize=8)
        ax2d.scatter([sp[0]], [sp[1]], color="#44ff88", s=140, marker="^",
                     zorder=6, label="Start")
        ax2d.annotate("START", (sp[0], sp[1]), color="#44ff88", fontsize=8,
                      xytext=(5, 5), textcoords="offset points")
        # Goal
        ax3d.scatter([ep[0]], [ep[1]], [ep[2]], color="#ff5555", s=160,
                     marker="*", zorder=6, label="Goal")
        ax3d.text(ep[0], ep[1], ep[2], "  GOAL", color="#ff5555", fontsize=8)
        ax2d.scatter([ep[0]], [ep[1]], color="#ff5555", s=160, marker="*",
                     zorder=6, label="Goal")
        ax2d.annotate("GOAL", (ep[0], ep[1]), color="#ff5555", fontsize=8,
                      xytext=(5, 5), textcoords="offset points")

        # Waypoint index labels every 5th
        for i, (lx, ly, lz, lb) in enumerate(zip(rx, ry, rz, route["labels"])):
            if i % 5 == 0:
                ax3d.text(lx, ly, lz, f" {i}", color="#ffe88a", fontsize=5.5, alpha=0.8)
                ax2d.annotate(str(i), (lx, ly), color="#ffe88a", fontsize=5.5,
                              alpha=0.8, xytext=(2, 2), textcoords="offset points")

    # ---- 3D styling ----
    for pane in (ax3d.xaxis.pane, ax3d.yaxis.pane, ax3d.zaxis.pane):
        pane.fill = False
        pane.set_edgecolor("#444466")
    ax3d.set_xlabel("X (m)", color="#aaaacc", fontsize=9)
    ax3d.set_ylabel("Y (m)", color="#aaaacc", fontsize=9)
    ax3d.set_zlabel("Z (m)", color="#aaaacc", fontsize=9)
    ax3d.tick_params(colors="#888899", labelsize=7)
    ax3d.set_title("3D View (perspective)", color="#ccccee", pad=10, fontsize=11)
    # Isometric-ish initial angle
    ax3d.view_init(elev=30, azim=-60)

    # ---- 2D styling ----
    ax2d.set_aspect("equal", adjustable="datalim")
    ax2d.set_xlabel("X (m)", color="#aaaacc", fontsize=9)
    ax2d.set_ylabel("Y (m)", color="#aaaacc", fontsize=9)
    ax2d.tick_params(colors="#888899", labelsize=7)
    ax2d.set_title("Top-down View (XY)", color="#ccccee", pad=10, fontsize=11)
    ax2d.grid(True, color="#2a2a4a", linewidth=0.5)
    for spine in ax2d.spines.values():
        spine.set_edgecolor("#444466")

    # ---- colourbar: removed (binary map has no continuous scale) ----

    # ---- legend ----
    leg_kw = dict(facecolor="#1e1e38", labelcolor="#ddddee",
                  framealpha=0.85, fontsize=8)
    ax3d.legend(loc="upper left", **leg_kw)
    ax2d.legend(loc="upper left", **leg_kw)

    # ---- stats box ----
    if obs_xs or dng_xs or cxs:
        stats = (
            f"Obstacle cells : {len(obs_xs)}\n"
            f"Danger cells   : {len(dng_xs)}\n"
            f"Clear cells    : {len(cxs)}"
        )
    elif route and route["xs"]:
        stats = f"Route waypoints: {len(route['xs'])}"
    else:
        stats = "No obstacle data"
    ax2d.text(0.01, 0.01, stats, transform=ax2d.transAxes,
              color="#bbbbcc", fontsize=8, va="bottom", family="monospace",
              bbox=dict(facecolor="#1a1a30", alpha=0.8, edgecolor="#444466",
                        boxstyle="round,pad=0.4"))

    fig.suptitle("DriveAerialVehicle – Obstacle Map",
                 color="#eeeeff", fontsize=13, y=1.01)
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

def render_plotly(obs_xs, obs_ys, obs_zs, dng_xs, dng_ys, dng_zs, cxs, cys, czs, bxs, bys, bzs, route, out_path, show_clear=True, exception_areas=None):
    try:
        import plotly.graph_objects as go
        import numpy as np
    except ImportError:
        print("plotly not installed.  Run: pip install plotly", file=sys.stderr)
        sys.exit(1)

    BG      = "#0d0d1a"
    GRID_C  = "#2a2a4a"
    AXIS_BG = "#111126"

    traces = []

    # ---- confirmed-clear cells (light green) ----
    if show_clear and cxs:
        traces.append(go.Scatter3d(
            x=cxs, y=cys, z=czs,
            mode="markers",
            name=f"Clear ({len(cxs)})",
            marker=dict(size=1.5, color="#88ddaa", opacity=0.20, symbol="circle"),
            hovertemplate="X: %{x:.0f}<br>Y: %{y:.0f}<br>Z: %{z:.0f}<extra>clear</extra>"
        ))

    # ---- danger cells (light orange) ----
    if dng_xs:
        traces.append(go.Scatter3d(
            x=dng_xs, y=dng_ys, z=dng_zs,
            mode="markers",
            name=f"Danger ({len(dng_xs)})",
            marker=dict(size=1.5, color="#ffbb77", opacity=0.35, symbol="circle"),
            hovertemplate="X: %{x:.0f}<br>Y: %{y:.0f}<br>Z: %{z:.0f}<extra>danger</extra>"
        ))

    # ---- obstacle cells (red, square) ----
    if obs_xs:
        traces.append(go.Scatter3d(
            x=obs_xs, y=obs_ys, z=obs_zs,
            mode="markers",
            name=f"Obstacle ({len(obs_xs)})",
            marker=dict(size=2.5, color="#dd2233", opacity=0.70, symbol="square"),
            hovertemplate=(
                "X: %{x:.0f} m<br>"
                "Y: %{y:.0f} m<br>"
                "Z: %{z:.0f} m<extra>obstacle</extra>"
            ),
        ))

    # ---- blocked sectors ----
    if bxs:
        traces.append(go.Scatter3d(
            x=bxs, y=bys, z=bzs,
            mode="markers",
            name=f"Blocked sectors ({len(bxs)})",
            marker=dict(size=4, color="cyan", opacity=0.30, symbol="diamond")
        ))

    # ---- exception areas (semi-transparent AABB boxes) ----
    if exception_areas:
        # Mesh3d vertex / face index layout for a box
        # Vertices: 0=(x1,y1,z1) 1=(x2,y1,z1) 2=(x2,y2,z1) 3=(x1,y2,z1)
        #           4=(x1,y1,z2) 5=(x2,y1,z2) 6=(x2,y2,z2) 7=(x1,y2,z2)
        BOX_I = [0, 0,  4, 4,  0, 0,  2, 2,  0, 0,  1, 1]
        BOX_J = [1, 2,  5, 6,  1, 5,  3, 7,  3, 7,  2, 6]
        BOX_K = [2, 3,  6, 7,  5, 4,  7, 6,  7, 4,  6, 5]
        for idx, ea in enumerate(exception_areas):
            col = _EA_COLORS[idx % len(_EA_COLORS)]
            x1, x2 = ea["min_x"], ea["max_x"]
            y1, y2 = ea["min_y"], ea["max_y"]
            z1, z2 = ea["min_z"], ea["max_z"]
            tag = ea.get("tag", f"area_{idx}")
            vx = [x1,x2,x2,x1, x1,x2,x2,x1]
            vy = [y1,y1,y2,y2, y1,y1,y2,y2]
            vz = [z1,z1,z1,z1, z2,z2,z2,z2]
            traces.append(go.Mesh3d(
                x=vx, y=vy, z=vz,
                i=BOX_I, j=BOX_J, k=BOX_K,
                opacity=0.12,
                color=col,
                name=f"EA: {tag}",
                showlegend=True,
                flatshading=True,
                hovertemplate=(
                    f"<b>Exception Area</b>: {tag}<br>"
                    f"X: [{x1}, {x2}]<br>"
                    f"Y: [{y1}, {y2}]<br>"
                    f"Z: [{z1}, {z2}]<extra></extra>"
                ),
            ))

    # ---- A* route ----
    if route and route["xs"]:
        rx, ry, rz = route["xs"], route["ys"], route["zs"]
        traces.append(go.Scatter3d(
            x=rx, y=ry, z=rz,
            mode="lines+markers",
            name=f"A* route ({len(rx)} wpts)",
            line=dict(color="#ffe55c", width=5),
            marker=dict(size=3, color="#ffe55c", opacity=0.85),
            hovertemplate=(
                "Sector: %{text}<br>"
                "X: %{x:.0f} m<br>Y: %{y:.0f} m<br>Z: %{z:.0f} m"
                "<extra>A* waypoint</extra>"
            ),
            text=route["labels"],
        ))
        sp = route["start_pos"]
        ep = route["end_pos"]
        traces.append(go.Scatter3d(
            x=[sp[0]], y=[sp[1]], z=[sp[2]],
            mode="markers+text",
            name="Start",
            marker=dict(size=13, color="#44ff88", symbol="diamond"),
            text=["START"], textfont=dict(color="#44ff88", size=12),
            textposition="top center",
            hovertemplate=f"START<br>X:{sp[0]:.1f} Y:{sp[1]:.1f} Z:{sp[2]:.1f}<extra></extra>"
        ))
        traces.append(go.Scatter3d(
            x=[ep[0]], y=[ep[1]], z=[ep[2]],
            mode="markers+text",
            name="Goal",
            marker=dict(size=14, color="#ff5555", symbol="x"),
            text=["GOAL"], textfont=dict(color="#ff5555", size=12),
            textposition="top center",
            hovertemplate=f"GOAL<br>X:{ep[0]:.1f} Y:{ep[1]:.1f} Z:{ep[2]:.1f}<extra></extra>"
        ))

    # ---- layout ----
    axis_style = dict(
        backgroundcolor=AXIS_BG,
        gridcolor=GRID_C,
        showbackground=True,
        zerolinecolor="#444466",
        tickfont=dict(color="#aaaacc", size=10),
    )

    # Compute Z range for slider (if we have any data)
    all_zs = list(obs_zs) + list(dng_zs) + list(czs)
    if route and route["zs"]: all_zs += route["zs"]
    z_min = min(all_zs) if all_zs else 0
    z_max = max(all_zs) if all_zs else 100

    layout = go.Layout(
        title=dict(
            text="DriveAerialVehicle – 3D Obstacle Map",
            font=dict(color="#eeeeff", size=16),
            x=0.5,
        ),
        scene=dict(
            xaxis=dict(title="X (m)", **axis_style),
            yaxis=dict(title="Y (m)", **axis_style),
            zaxis=dict(title="Z (m)", **axis_style),
            aspectmode="data",
            camera=dict(
                eye=dict(x=1.4, y=-1.6, z=1.0),
                up=dict(x=0, y=0, z=1),
            ),
            bgcolor=AXIS_BG,
        ),
        paper_bgcolor=BG,
        plot_bgcolor=BG,
        font=dict(color="#ddddee"),
        legend=dict(
            bgcolor="#1a1a38",
            bordercolor="#444466",
            borderwidth=1,
            font=dict(size=11)
        ),
        margin=dict(l=0, r=60, t=50, b=0),
    )

    fig = go.Figure(data=traces, layout=layout)

    # ---- Z height filter slider ----
    if all_zs and (z_max - z_min) > 1:
        import numpy as np
        n_steps = min(20, int(z_max - z_min) + 1)
        z_levels = np.linspace(z_min, z_max, n_steps)
        steps = []
        for zl in z_levels:
            # Update visibility: show cells with z >= zl
            # We can't filter individual points in Scatter3d steps easily,
            # so we annotate the step label only (full filtering needs dash/widget)
            steps.append(dict(
                method="relayout",
                args=[{"scene.zaxis.range": [zl, z_max]}],
                label=f"{zl:.0f} m",
            ))
        fig.update_layout(
            sliders=[dict(
                active=0,
                steps=steps,
                currentvalue=dict(
                    prefix="Z ≥ ",
                    font=dict(color="#ccccee"),
                ),
                len=0.55,
                x=0.22,
                y=0.0,
                bgcolor="#1a1a38",
                bordercolor="#444466",
                font=dict(color="#aaaacc"),
                tickcolor="#666688",
            )]
        )

    if out_path:
        try:
            fig.write_image(str(out_path), width=1600, height=900)
            print(f"Saved to {out_path}")
        except Exception as e:
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
        "--data", type=Path, default=None,
        help="Path to Data/map/ directory containing chunk_*.dat files (default: ./Data/map)"
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
        "--min", type=int, default=1, metavar="N",
        help="Minimum value to show an obstacle cell  (default: 1)"
    )
    parser.add_argument(
        "--max", type=int, default=None, metavar="N",
        help=argparse.SUPPRESS  # no longer used in binary mode
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
    parser.add_argument(
        "--exception", type=Path, default=DEFAULT_EXCEPTION_AREA_PATH,
        metavar="FILE",
        help="Path to autopilot_exception_area.json  (default: ./Data/autopilot_exception_area.json)"
    )
    parser.add_argument(
        "--no-exception", action="store_true",
        help="Hide exception area boxes"
    )
    args = parser.parse_args()

    # --- Load obstacle map ---
    obs_xs, obs_ys, obs_zs = [], [], []
    dng_xs, dng_ys, dng_zs = [], [], []  # danger cells (adjacent to obstacle)
    cxs, cys, czs = [], [], []  # confirmed-clear cells

    # Determine data source: explicit --data, or default Data/map/ directory
    data_path = (args.data.resolve() if args.data is not None
                 else DEFAULT_MAP_DIR.resolve())

    if args.no_obstacles and args.no_clear:
        print("Obstacle display skipped (--no-obstacles --no-clear)")
    else:
        chunk_files = list(data_path.glob("chunk_*.dat")) if data_path.is_dir() else []
        if not chunk_files:
            print(f"[INFO] No chunk files found in: {data_path}")
            print("  Enable recording from the debug menu, drive around, then save.")
        else:
            print(f"Loading chunked obstacle map: {data_path}")
            print(f"  Chunk files found  : {len(chunk_files)}")
            cell_size, cells = load_obstacle_map_chunked(data_path)
            print(f"  Total cells loaded : {len(cells)}")
            obs_xs, obs_ys, obs_zs, dng_xs, dng_ys, dng_zs, cxs, cys, czs = parse_cells(cells, cell_size)
            if args.no_obstacles:
                obs_xs, obs_ys, obs_zs = [], [], []
                dng_xs, dng_ys, dng_zs = [], [], []
            if args.no_clear:
                cxs, cys, czs = [], [], []
            print(f"  Obstacle cells     : {len(obs_xs)}")
            print(f"  Danger cells       : {len(dng_xs)}")
            print(f"  Confirmed-clear cells              : {len(cxs)}")

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

    # --- Load exception areas ---
    exception_areas = []
    if not args.no_exception:
        ea_path = args.exception.resolve()
        if ea_path.exists():
            print(f"Loading exception areas: {ea_path}")
            exception_areas = load_exception_areas(ea_path)
            print(f"  Exception areas      : {len(exception_areas)}")
        else:
            print(f"[INFO] autopilot_exception_area.json not found ({ea_path}). Skipping.")

    # --- Load sector map ---
    sector_path = args.sector.resolve()
    bxs, bys, bzs = [], [], []
    if sector_path.exists():
        print(f"Loading sector map   : {sector_path}")
        sector_size, sectors = load_sector_map(sector_path)
        bxs, bys, bzs = parse_blocked_sectors(sectors, sector_size)
        if bxs:
            print(f"  Blocked sectors    : {len(bxs)}")

    if not obs_xs and not dng_xs and not cxs and not bxs and (route is None or not route["xs"]):
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
        render_plotly(obs_xs, obs_ys, obs_zs, dng_xs, dng_ys, dng_zs, cxs, cys, czs, bxs, bys, bzs, route, args.out, show_clear, exception_areas)
    else:
        render_matplotlib(obs_xs, obs_ys, obs_zs, dng_xs, dng_ys, dng_zs, cxs, cys, czs, bxs, bys, bzs, route, args.out, show_clear, exception_areas)


if __name__ == "__main__":
    main()
