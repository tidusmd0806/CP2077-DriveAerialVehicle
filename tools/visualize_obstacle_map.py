"""
visualize_obstacle_map.py
=========================
DriveAerialVehicle mod - PyVista obstacle map visualizer.

Loads:
  - Data/map_bin/chunk_*.bin   (packed DAVOB4, preferred)
  - Data/map/chunk_*.dat       (legacy text v3, fallback)
  - Data/last_route.json       (optional)

Renders a native VTK window (no browser) with the obstacle map and the latest
A* route. Includes an in-window Reload button and R hotkey.

By default the blocked cells are drawn as the *surface* of the voxel set rather
than as points, so buildings and terrain read as the solid shapes they actually
are -- which is the whole point when you are trying to judge whether a route is
flyable. The no-fly volume gets a translucent shell wrapped around those
solids, and --zmin/--zmax slice a height band out so you can look at one floor
of the city on its own.

    --mode surface   solid voxel skin (default)
    --mode points    the old point cloud
    --mode both      surfaces with points on top
    --danger-style off / shell / edges
    --zmin 100 --zmax 300      look at one altitude band
    --flat-color     plain red instead of the height ramp

The packed path is what the game actually reads, so this shows the same thing
the autopilot sees - including chunks minted at runtime by a learned-cell fold,
which are recorded in Data/map_bin/manifest.txt.
"""

import argparse
import json
import math
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


# ---------------------------------------------------------------------------
# Voxel -> surface extraction
#
# The map is a 10 m voxel grid and the blocked cells are buildings and terrain.
# Drawn as points they read as a red fog; drawn as the *skin* of the voxel set
# they read as the structures themselves. Only faces between a filled voxel and
# an empty neighbour are emitted, so the inside of a solid block costs nothing:
# 410k blocked cells become ~920k quads rather than 2.5M cubes.
#
# Each quad gets its own four points and a winding chosen so the face normal
# points *away* from the filled cell. That matters -- with a single fixed winding
# roughly half the geometry is inverted and shades black under a light source,
# which looks like holes in the buildings rather than buildings.
#
# Note the axis-1 wrinkle: moveaxis(1, 0) is an odd permutation, so the
# right-handed cross product flips sign relative to axes 0 and 2. Hence the
# per-axis table instead of one rule for all three.
# ---------------------------------------------------------------------------
_QUAD = ((0.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 1.0, 1.0), (0.0, 0.0, 1.0))
# Does the listed winding put the normal on the +axis side?
_LISTED_IS_POSITIVE = {0: True, 1: False, 2: True}


def build_voxel_surface(mask, origin, cell_size, against=None):
    """Boundary quads of a boolean voxel mask.

    mask    -- bool ndarray (nx, ny, nz), True = solid cell
    origin  -- (ox, oy, oz) cell index of mask[0, 0, 0]
    cell_size -- metres per cell
    against -- optional mask of the same shape whose cells suppress any face that
               touches them. Used for the danger shell: a danger face that sits
               right against a building is coplanar with that building's own
               face, and drawing both gives z-fighting. It also halves the quad
               count, 1.69M down to 0.80M on the shipped map.

    Returns (points, faces, z_scalar) ready for pv.PolyData, or (None, None, None)
    when nothing is emitted. z_scalar carries each point's world height so callers
    can colour by elevation.
    """
    import numpy as np

    ox, oy, oz = origin
    quad = np.asarray(_QUAD, dtype=np.float64)
    pts_chunks = []
    n_total = 0

    for ax in (0, 1, 2):
        m = np.moveaxis(mask, ax, 0)
        lo, hi = m[:-1], m[1:]
        others = [a for a in (0, 1, 2) if a != ax]
        if against is None:
            ag_lo = ag_hi = None
        else:
            g = np.moveaxis(against, ax, 0)
            ag_lo, ag_hi = g[:-1], g[1:]
        for filled, want_positive in ((lo, True), (hi, False)):
            sel = filled & (lo != hi)
            if ag_lo is not None:
                # drop the face if either side of it belongs to `against`
                sel = sel & ~ag_lo & ~ag_hi
            s, u, v = np.nonzero(sel)
            if s.size == 0:
                continue
            use = quad if (_LISTED_IS_POSITIVE[ax] == want_positive) else quad[::-1]
            n = s.size
            p = np.empty((n, 4, 3), dtype=np.float64)
            # the quad lies in the plane just past the split, offset 0 along ax
            p[..., ax] = (s + 1)[:, None]
            p[..., others[0]] = u[:, None] + use[None, :, 1]
            p[..., others[1]] = v[:, None] + use[None, :, 2]
            p[..., 0] = (p[..., 0] + ox) * cell_size
            p[..., 1] = (p[..., 1] + oy) * cell_size
            p[..., 2] = (p[..., 2] + oz) * cell_size
            pts_chunks.append(p.reshape(n * 4, 3).astype(np.float32))
            n_total += n

    if n_total == 0:
        return None, None, None

    points = np.concatenate(pts_chunks, axis=0)
    idx = np.arange(n_total * 4, dtype=np.int64).reshape(n_total, 4)
    faces = np.column_stack([np.full(n_total, 4, dtype=np.int64), idx]).ravel()
    return points, faces, points[:, 2].copy()


def _cell_index(xs, ys, zs, cell_size, zlo=None, zhi=None):
    import numpy as np
    gx = np.floor(np.asarray(xs) / cell_size).astype(np.int64)
    gy = np.floor(np.asarray(ys) / cell_size).astype(np.int64)
    gz = np.floor(np.asarray(zs) / cell_size).astype(np.int64)
    if zlo is not None:
        keep = gz >= math.floor(zlo / cell_size)
        gx, gy, gz = gx[keep], gy[keep], gz[keep]
    if zhi is not None:
        keep = gz <= math.floor(zhi / cell_size)
        gx, gy, gz = gx[keep], gy[keep], gz[keep]
    return gx, gy, gz


def union_cell_bounds(sets, cell_size, zlo=None, zhi=None):
    """Common (ox, oy, oz, nx, ny, nz) covering every point set given.

    Both the blocked and danger masks have to sit on the same grid for one to be
    able to punch faces out of the other, so the extents are agreed up front
    rather than each mask picking its own.
    """
    lo = [None, None, None]
    hi = [None, None, None]
    for s in sets:
        if s is None or len(s[0]) == 0:
            continue
        gx, gy, gz = _cell_index(s[0], s[1], s[2], cell_size, zlo, zhi)
        if gx.size == 0:
            continue
        for i, g in enumerate((gx, gy, gz)):
            mn, mx = int(g.min()), int(g.max())
            lo[i] = mn if lo[i] is None else min(lo[i], mn)
            hi[i] = mx if hi[i] is None else max(hi[i], mx)
    if lo[0] is None:
        return None
    return (lo[0], lo[1], lo[2],
            hi[0] - lo[0] + 1, hi[1] - lo[1] + 1, hi[2] - lo[2] + 1)


def state_mask(xs, ys, zs, cell_size, exclude=None, zlo=None, zhi=None, bounds=None):
    """World-coordinate cell centres -> a dense boolean mask plus its origin.

    `exclude` is another set of centres to punch out of the mask. `zlo` / `zhi`
    are world-metre bounds for slicing a floor in isolation. `bounds` pins the
    grid to a shared extent (see union_cell_bounds); cells outside it are dropped.
    """
    import numpy as np

    if len(xs) == 0:
        return None, None
    gx, gy, gz = _cell_index(xs, ys, zs, cell_size, zlo, zhi)
    if gx.size == 0:
        return None, None

    if bounds is not None:
        ox, oy, oz, nx, ny, nz = bounds
        keep = ((gx >= ox) & (gx < ox + nx)
               & (gy >= oy) & (gy < oy + ny)
               & (gz >= oz) & (gz < oz + nz))
        gx, gy, gz = gx[keep], gy[keep], gz[keep]
        if gx.size == 0:
            return None, None
    else:
        ox = int(gx.min())
        oy = int(gy.min())
        oz = int(gz.min())
        nx = int(gx.max()) - ox + 1
        ny = int(gy.max()) - oy + 1
        nz = int(gz.max()) - oz + 1
    mask = np.zeros((nx, ny, nz), dtype=bool)
    mask[gx - ox, gy - oy, gz - oz] = True

    if exclude is not None and len(exclude[0]):
        ex, ey, ez = _cell_index(exclude[0], exclude[1], exclude[2], cell_size)
        mx = ((ex >= ox) & (ex < ox + nx) & (ey >= oy) & (ey < oy + ny)
              & (ez >= oz) & (ez < oz + nz))
        mask[ex[mx] - ox, ey[mx] - oy, ez[mx] - oz] = False
    return mask, (ox, oy, oz)


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
    cell_size = 10.0

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
        "cell_size": cell_size,
        "route": route,
    }


# Rendering palette. Blocked keeps the red collision semantic but is drawn as a
# shaded solid. The height ramp stays inside the red family on purpose: an
# earlier version opened on slate blue for low cells, which made every
# street-level obstacle read as terrain-coloured background instead of
# something you would hit.
BLOCKED_COLOR = "#c9313c"
DANGER_COLOR = "#ff9f43"
CLEAR_COLOR = "#7ee8a2"
HEIGHT_CMAP = ["#5c1018", "#8e1c22", "#c4392b", "#e8763a", "#f7d488"]


def render_pyvista(data: dict, out_path: Path | None, show_clear: bool,
                  reload_loader=None, mode: str = "surface",
                  height_color: bool = True, zlo=None, zhi=None,
                  show_edges: bool = False, offscreen=None,
                  danger_opacity: float = 0.12,
                  danger_color: str = DANGER_COLOR,
                  danger_style: str = "shell",
                  ground: bool = True,
                  focus_route: bool = False):
    try:
        import numpy as np
        import pyvista as pv
    except ImportError:
        print("pyvista not installed. Run: pip install pyvista", file=sys.stderr)
        sys.exit(1)

    plotter = pv.Plotter(window_size=(1600, 900), title="DriveAerialVehicle - Obstacle Map (PyVista)",
                        off_screen=bool(offscreen))
    plotter.set_background("#0d0d1a")
    plotter.add_axes(line_width=1, color="white")
    # VTK's default light rides with the camera, which is enough for flat-shaded
    # voxels, but a second fixed key light keeps faces lit that the camera grazes
    # edge-on -- without it those read as black gaps in the buildings.
    try:
        import vtkmodules.vtkRenderingCore as _vrc
        key = _vrc.vtkLight()
        key.SetLightTypeToSceneLight()
        key.SetPosition(0.35, 0.45, 0.85)
        key.SetIntensity(0.55)
        key.SetColor(1.0, 0.97, 0.92)
        plotter.renderer.add_light(key)
    except Exception:
        pass
    route_actor_names = []
    surface_actor_names = []

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

        cell_size = cur.get("cell_size", 10.0) or 10.0
        want_surface = mode in ("surface", "both")
        want_points = mode in ("points", "both")
        surf_quads = {"blocked": 0, "danger": 0}

        # ---- surfaces: the actual shapes of the collision volume ----------
        for nm in surface_actor_names:
            remove_actor(nm)
        surface_actor_names.clear()

        if want_surface:
            # One shared grid for both masks so the blocked set can punch faces
            # out of the danger shell.
            bnd = union_cell_bounds(
                [(obs_xs, obs_ys, obs_zs), (dng_xs, dng_ys, dng_zs)],
                cell_size, zlo, zhi)
            bm, bor = state_mask(obs_xs, obs_ys, obs_zs, cell_size,
                                zlo=zlo, zhi=zhi, bounds=bnd)
            if bm is not None:
                p, f, zsc = build_voxel_surface(bm, bor, cell_size)
                if p is not None:
                    mesh = pv.PolyData(p, f)
                    kw = dict(lighting=True, name="surf_blocked",
                            line_width=0.6, show_edges=show_edges)
                    if height_color:
                        kw.update(scalars=zsc, cmap=HEIGHT_CMAP,
                                 edge_color="#20090e",
                                 scalar_bar_args=dict(
                                     title="height (m)", vertical=True,
                                     height=0.5, width=0.035,
                                     position_x=0.905, position_y=0.25,
                                     title_font_size=11, label_font_size=10,
                                     color="#ccccee",
                                     background_color="#14142a"))
                    else:
                        kw.update(color=BLOCKED_COLOR)
                    plotter.add_mesh(mesh, **kw)
                    surface_actor_names.append("surf_blocked")
                    surf_quads["blocked"] = len(f) // 5

            # Danger wraps around the buildings rather than cutting through them,
            # so the no-fly volume reads as one continuous shell. Backface
            # culling halves the overdraw, which matters at ~800k quads.
            dm, dor = state_mask(dng_xs, dng_ys, dng_zs, cell_size,
                                zlo=zlo, zhi=zhi, bounds=bnd)
            if dm is not None and danger_style != "off":
                p, f, _ = build_voxel_surface(dm, dor, cell_size,
                                             against=(bm if bm is not None else None))
                if p is not None:
                    mesh = pv.PolyData(p, f)
                    if danger_style == "edges":
                        # Wireframe of the same shell: shows the envelope's
                        # structure without tinting the whole scene.
                        plotter.add_mesh(mesh, style="wireframe", color=danger_color,
                                       line_width=0.4, opacity=danger_opacity * 2.2,
                                       name="surf_danger")
                    else:
                        plotter.add_mesh(mesh, color=danger_color,
                                       opacity=danger_opacity,
                                       lighting=False, backface_culling=True,
                                       name="surf_danger")
                    surface_actor_names.append("surf_danger")
                    surf_quads["danger"] = len(f) // 5

            # z=0 reference lattice, so a height slice still tells you which way
            # is up and how far above the street you are looking.
            if ground:
                try:
                    arrays = [a for a in (obs_xs, obs_ys, dng_xs, dng_ys, cxs, cys) if len(a)]
                    if arrays:
                        x0 = min(float(np.min(a)) for a in arrays[0::2])
                        x1 = max(float(np.max(a)) for a in arrays[0::2])
                        y0 = min(float(np.min(a)) for a in arrays[1::2])
                        y1 = max(float(np.max(a)) for a in arrays[1::2])
                        step = max(cell_size * 10.0, 100.0)
                        nx = max(int((x1 - x0) // step) + 1, 2)
                        ny = max(int((y1 - y0) // step) + 1, 2)
                        lat = pv.ImageData(dimensions=(nx, ny, 1),
                                         origin=(x0, y0, 0.0),
                                         spacing=(step, step, 1.0))
                        plotter.add_mesh(lat, style="wireframe", color="#263252",
                                       line_width=0.5, name="ground_grid")
                        surface_actor_names.append("ground_grid")
                except Exception:
                    pass

        # ---- points: the legacy view, still useful for spotting density ----
        if want_points:
            if show_clear:
                set_points("pts_clear", cxs, cys, czs, CLEAR_COLOR, 2, 0.18)
            else:
                remove_actor("pts_clear")
            set_points("pts_danger", dng_xs, dng_ys, dng_zs, DANGER_COLOR, 2, 0.30)
            set_points("pts_obstacle", obs_xs, obs_ys, obs_zs, BLOCKED_COLOR, 3, 0.70)
        else:
            remove_actor("pts_clear")
            remove_actor("pts_danger")
            remove_actor("pts_obstacle")

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

        stats = f"Obstacle: {len(obs_xs)}  Danger: {len(dng_xs)}  Clear: {len(cxs)}"
        if want_surface:
            stats += (f"\n[surface] blocked {surf_quads['blocked']:,} quads"
                      f" / danger {surf_quads['danger']:,} quads")
        if zlo is not None or zhi is not None:
            stats += f"\nheight slice: {zlo if zlo is not None else '-inf'} .. " \
                    f"{zhi if zhi is not None else '+inf'} m"
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

    # Fit the whole map first. focus_route then overrides with a tighter framing.
    # Note pyvista's show() has no reset_camera kwarg -- it is the act of
    # assigning camera_position that marks the camera as modified and stops VTK
    # from auto-fitting on the first render.
    plotter.reset_camera()
    if focus_route and data.get("route") and data["route"]["xs"]:
        try:
            r = data["route"]
            rp = np.column_stack([r["xs"], r["ys"], r["zs"]]).astype(float)
            c = rp.mean(axis=0)
            span = float((rp.max(axis=0) - rp.min(axis=0)).max())
            d = max(span * 2.0, 500.0)
            plotter.camera_position = [
                (c[0] - d * 0.45, c[1] - d * 0.75, c[2] + d * 1.05),
                (float(c[0]), float(c[1]), float(c[2])),
                (0.0, 0.0, 1.0),
            ]
        except Exception:
            pass

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
            if not offscreen:
                plotter.show(auto_close=False)
            else:
                plotter.render()
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
    parser.add_argument("--mode", choices=("surface", "points", "both"), default="surface",
                      help="surface = solid voxel skin, reads as real buildings and "
                           "terrain (default). points = the old point cloud. "
                           "both = surfaces with the points on top.")
    parser.add_argument("--flat-color", action="store_true",
                      help="Plain red for blocked instead of the height colour ramp")
    parser.add_argument("--edges", action="store_true",
                      help="Stroke the quad edges over the surface")
    parser.add_argument("--zmin", type=float, default=None, metavar="M",
                      help="Draw only cells at or above this world height (metres)")
    parser.add_argument("--zmax", type=float, default=None, metavar="M",
                      help="Draw only cells at or below this world height (metres)")
    parser.add_argument("--no-ground", action="store_true",
                      help="Skip the z=0 reference grid")
    parser.add_argument("--danger-style", choices=("shell", "edges", "off"),
                      default="shell",
                      help="How the no-fly volume reads: translucent shell "
                           "(default), wireframe, or hidden")
    parser.add_argument("--danger-opacity", type=float, default=0.10, metavar="A",
                      help="Opacity of the danger shell (default 0.10)")
    parser.add_argument("--danger-color", default=DANGER_COLOR,
                      help="Colour of the danger shell (default %s)" % DANGER_COLOR)
    parser.add_argument("--offscreen", action="store_true",
                      help="Render without opening a window (needed over SSH / "
                           "for scripted screenshots)")
    parser.add_argument("--focus-route", action="store_true",
                      help="Frame the camera on the route instead of the whole "
                           "6 km map -- the route is a speck otherwise")
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
    render_pyvista(data, args.out, show_clear, reload_loader,
                  mode=args.mode,
                  height_color=not args.flat_color,
                  zlo=args.zmin, zhi=args.zmax,
                  show_edges=args.edges,
                  offscreen=args.offscreen or bool(args.out),
                  danger_opacity=args.danger_opacity,
                  danger_color=args.danger_color,
                  danger_style=args.danger_style,
                  ground=not args.no_ground,
                  focus_route=args.focus_route)


if __name__ == "__main__":
    main()
