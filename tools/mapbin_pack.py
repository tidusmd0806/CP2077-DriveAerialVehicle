#!/usr/bin/env python3
"""
Pack the text chunk files (DAV_OBMAP v3) into flat binary byte-grids (v4).

Why: the resident cost of the obstacle map is dominated by the *number of live Lua
objects* (2.6M cells -> ~8M strings/table slots -> ~300MB and multi-ms GC pauses),
not by the bytes.  A dense 1-byte-per-cell grid stored as ONE immutable Lua string
per chunk collapses the whole map to 96 GC objects and ~30MB, and Lua can load it
with a single read("*a") - no per-cell parsing at all.

Layout (little endian), per chunk file `chunk_<cx>_<cy>.bin`:

    off  size  field
    0    6    magic  b"DAVOB4"
    6    1    z_levels          (1..255)
    7    1    zmin_bias         (uint8, z_min + 128)  -> z_min in [-128, 127]
    8    2    cell_size_cm       (uint16 LE, 1000 == 10.0 m)
    10   4    known_count       (uint32 LE, cells that are not UNKNOWN)
    14   2    reserved
    16   ...  body: z_levels * 50 * 50 bytes

The header is deliberately laid out so Lua reads it with a handful of
`string.byte` calls and no sign decoding:
    z_levels = raw:byte(7);  z_min = raw:byte(8) - 128

    body index = (z - z_min) * 2500 + ly * 50 + lx
    lx = cx - chunk_cx * 50      (0..49)
    ly = cy - chunk_cy * 50      (0..49)

Cell byte values (4 states, matches the Lua-side enum):

    0 = UNKNOWN   (never observed)
    1 = CLEAR     (observed free)
    2 = DANGER    (soft obstacle)
    3 = BLOCKED   (hard obstacle)

Text v3 values map as: 0 -> CLEAR, 1 -> DANGER, >=2 -> BLOCKED.

Usage:
    python tools/mapbin_pack.py                 # -> Data/map_bin (tight per-chunk z)
    python tools/mapbin_pack.py --zmin -4 --zmax 127   # fixed global z window
"""
import argparse
import os
import struct
import sys

CHUNK_CELLS = 50
SLICE = CHUNK_CELLS * CHUNK_CELLS  # 2500
MAGIC = b"DAVOB4"

V_UNKNOWN, V_CLEAR, V_DANGER, V_BLOCKED = 0, 1, 2, 3
TEXT_TO_GRID = {0: V_CLEAR, 1: V_DANGER}


def parse_text_chunk(path):
    """Return (cell_size, [(cx, cy, cz, grid_value), ...])."""
    with open(path, "rb") as fh:
        raw = fh.read()
    if not raw.startswith(b"DAV_OBMAP v3"):
        return None, []
    head = raw[:64].decode("ascii", "replace")
    cell_size = 10.0
    if "cell_size=" in head:
        try:
            cell_size = float(head.split("cell_size=")[1].split()[0])
        except ValueError:
            pass
    cells = []
    for line in raw.split(b"\n")[1:]:
        parts = line.split()
        if len(parts) < 4:
            continue
        try:
            cx, cy, cz, v = (int(parts[0]), int(parts[1]), int(parts[2]), int(parts[3]))
        except ValueError:
            continue
        cells.append((cx, cy, cz, TEXT_TO_GRID.get(v, V_BLOCKED)))
    return cell_size, cells


def pack_chunk(cx, cy, cells, zmin=None, zmax=None):
    """Build the binary body for one chunk. Returns (bytes, z_min, z_levels)."""
    if not cells:
        return None
    if zmin is None:
        zmin = min(c[2] for c in cells)
        zmax = max(c[2] for c in cells)
    levels = zmax - zmin + 1
    if levels < 1 or levels > 255:
        raise SystemExit(f"chunk {cx}_{cy}: z_levels {levels} out of range 1..255")
    body = bytearray(levels * SLICE)  # 0 == UNKNOWN
    bx, by = cx * CHUNK_CELLS, cy * CHUNK_CELLS
    for cx_, cy_, cz, val in cells:
        lx, ly = cx_ - bx, cy_ - by
        if not (0 <= lx < CHUNK_CELLS and 0 <= ly < CHUNK_CELLS):
            raise SystemExit(f"chunk {cx}_{cy}: cell {cx_},{cy_} outside chunk footprint")
        body[(cz - zmin) * SLICE + ly * CHUNK_CELLS + lx] = val
    if zmin < -128 or zmin > 127:
        raise SystemExit(f"chunk {cx}_{cy}: z_min {zmin} outside [-128,127]")
    known = sum(1 for b in body if b != 0)
    hdr = (MAGIC + bytes([levels, zmin + 128])
           + struct.pack("<HI", 1000, known) + b"\0" * 2)
    return hdr + bytes(body), zmin, levels


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=None, help="source Data/map dir (text v3)")
    ap.add_argument("--dst", default=None, help="destination dir (binary v4)")
    ap.add_argument("--zmin", type=int, default=None, help="fixed global z_min")
    ap.add_argument("--zmax", type=int, default=None, help="fixed global z_max")
    args = ap.parse_args()

    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    mod = os.path.join(repo, "source", "resources", "bin", "x64", "plugins",
                      "cyber_engine_tweaks", "mods", "DriveAerialVehicle")
    src = args.src or os.path.join(mod, "Data", "map")
    dst = args.dst or os.path.join(mod, "Data", "map_bin")
    os.makedirs(dst, exist_ok=True)

    total_in = total_out = total_cells = n = 0
    manifest = []
    for name in sorted(os.listdir(src)):
        if not (name.startswith("chunk_") and name.endswith(".dat")):
            continue
        key = name[len("chunk_"):-len(".dat")]
        try:
            sx, sy = key.split("_")
            cx, cy = int(sx), int(sy)
        except ValueError:
            continue
        cell_size, cells = parse_text_chunk(os.path.join(src, name))
        if cell_size is None:
            print(f"skip {name}: not v3", file=sys.stderr)
            continue
        out, zmin, levels = pack_chunk(cx, cy, cells, args.zmin, args.zmax)
        out_path = os.path.join(dst, f"chunk_{cx}_{cy}.bin")
        with open(out_path, "wb") as fh:
            fh.write(out)
        manifest.append((cx, cy))
        total_in += os.path.getsize(os.path.join(src, name))
        total_out += len(out)
        total_cells += len(cells)
        n += 1

    print(f"packed {n} chunks, {total_cells} cells")

    # Chunk manifest: the game otherwise discovers chunks by probing every
    # coordinate in the probe range, and a FAILED io.open costs ~0.7 ms under
    # Cyber Engine Tweaks.  41x41 coords = 1681 probes = ~1.2 s, which is 82% of
    # the whole base-image load on a fast machine and scales straight with disk
    # latency -- several seconds on an HDD.  One small text file turns that into a
    # single open.
    man_path = os.path.join(dst, "manifest.txt")
    with open(man_path, "w") as fh:
        fh.write("DAVOB4-MANIFEST %d\n" % len(manifest))
        for cx, cy in manifest:
            fh.write("%d %d\n" % (cx, cy))
    print(f"  manifest      : {man_path}")
    print(f"  text v3 total : {total_in / 1048576:8.2f} MB")
    print(f"  binary v4     : {total_out / 1048576:8.2f} MB "
          f"({total_out / max(total_cells, 1):.2f} B/cell on disk)")
    print(f"  -> {dst}")


if __name__ == "__main__":
    main()
