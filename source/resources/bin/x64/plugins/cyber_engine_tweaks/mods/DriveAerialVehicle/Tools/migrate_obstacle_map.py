"""
Migrate legacy obstacle_map.dat (v2) to chunked format in Data/map/ (v3).
Each chunk covers 50x50 cells (500m x 500m) in XY.
File naming: chunk_{chunkX}_{chunkY}.dat
"""
import os
import math
from collections import defaultdict

BASE_DIR = os.path.join(os.path.dirname(__file__), "..")
OLD_PATH = os.path.join(BASE_DIR, "Data", "obstacle_map.dat")
MAP_DIR = os.path.join(BASE_DIR, "Data", "map")
CHUNK_CELLS = 50  # cells per chunk side

def main():
    if not os.path.exists(OLD_PATH):
        print(f"ERROR: {OLD_PATH} not found")
        return

    os.makedirs(MAP_DIR, exist_ok=True)

    # Read old file
    with open(OLD_PATH, "r", encoding="utf-8") as f:
        lines = f.readlines()

    if not lines:
        print("ERROR: Empty file")
        return

    header = lines[0].strip()
    if not header.startswith("DAV_OBMAP v2"):
        print(f"ERROR: Unrecognized header: {header}")
        return

    cell_size = header.split("cell_size=")[1] if "cell_size=" in header else "10"
    print(f"Header: {header}")
    print(f"Cell size: {cell_size}")

    # Parse all cells and group by chunk
    chunks = defaultdict(list)  # chunk_key -> [(cx, cy, cz, count), ...]
    total = 0
    for line in lines[1:]:
        line = line.strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) != 4:
            continue
        cx, cy, cz, count = int(parts[0]), int(parts[1]), int(parts[2]), int(parts[3])
        chunk_x = math.floor(cx / CHUNK_CELLS)
        chunk_y = math.floor(cy / CHUNK_CELLS)
        chunk_key = f"{chunk_x}_{chunk_y}"
        chunks[chunk_key].append((cx, cy, cz, count))
        total += 1

    print(f"Total cells parsed: {total}")
    print(f"Total chunks: {len(chunks)}")

    # Write chunk files
    for chunk_key, cells in chunks.items():
        chunk_path = os.path.join(MAP_DIR, f"chunk_{chunk_key}.dat")
        with open(chunk_path, "w", encoding="utf-8") as f:
            f.write(f"DAV_OBMAP v3 cell_size={cell_size}\n")
            for cx, cy, cz, count in cells:
                f.write(f"{cx} {cy} {cz} {count}\n")
        print(f"  chunk_{chunk_key}.dat: {len(cells)} cells")

    # Rename old file
    migrated_path = OLD_PATH + ".migrated"
    if os.path.exists(migrated_path):
        os.remove(migrated_path)
    os.rename(OLD_PATH, migrated_path)
    print(f"\nOld file renamed to: {migrated_path}")

    # Also handle .bak if exists
    bak_path = OLD_PATH + ".bak"
    if os.path.exists(bak_path):
        bak_migrated = bak_path + ".migrated"
        if os.path.exists(bak_migrated):
            os.remove(bak_migrated)
        os.rename(bak_path, bak_migrated)
        print(f"Backup renamed to: {bak_migrated}")

    print(f"\nMigration complete! {total} cells -> {len(chunks)} chunk files in Data/map/")

if __name__ == "__main__":
    main()
