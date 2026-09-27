#!/usr/bin/env python3
"""
Full-residency (DAVOB4 base image) integration test.

Stages three map directories under an ASCII workdir - text-only, bin-only and
empty - so the test can compare the new path against the legacy loader and prove
the fallback still works.

    python tests/run_grid_integration_test.py

Requirements: pip install lupa
"""
import os
import shutil
import subprocess
import sys

WORKDIR = r"C:\davgrid"
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOD = os.path.join(REPO, "source", "resources", "bin", "x64", "plugins",
                  "cyber_engine_tweaks", "mods", "DriveAerialVehicle")

RUNNER_SRC = r'''
import sys
import time
import lupa.lua51 as lua  # CET runs LuaJIT (Lua 5.1 semantics); 5.4 would accept code the game rejects

L = lua.LuaRuntime()
L.globals()["print"] = lambda *a: (sys.stdout.write(" ".join(str(x) for x in a) + "\n"),
                                  sys.stdout.flush())
L.globals()["hrtime"] = time.perf_counter
src = open(R_TEST, encoding="utf-8").read()
fn = L.eval("function(...) " + src + " end")
fn(R_MOD, R_TEXTMAP, R_BINMAP, R_EMPTYMAP)
'''


def main():
    try:
        import lupa.lua51  # noqa: F401
    except ImportError:
        sys.exit("lupa is required:  pip install lupa")

    script = sys.argv[1] if len(sys.argv) > 1 else "grid_integration_test.lua"
    wd = WORKDIR if script == "grid_integration_test.lua" else WORKDIR + "_b"

    mod_dst = os.path.join(wd, "mod")
    text_dst = os.path.join(wd, "textmap")
    bin_dst = os.path.join(wd, "binmap")
    empty_dst = os.path.join(wd, "emptymap")

    for d in (mod_dst, text_dst, bin_dst, empty_dst):
        shutil.rmtree(d, ignore_errors=True)
    shutil.copytree(MOD, mod_dst)
    shutil.copytree(os.path.join(MOD, "Data", "map"), text_dst)
    os.makedirs(empty_dst, exist_ok=True)

    # Pack the shipped text chunks into v4 binaries in the ASCII workdir.
    rc = subprocess.call([sys.executable, os.path.join(REPO, "tools", "mapbin_pack.py"),
                         "--src", text_dst, "--dst", bin_dst,
                         "--zmin", "-4", "--zmax", "127"])
    if rc != 0:
        return rc

    # The staged mod copy must not auto-discover packed data from its own tree.
    shutil.rmtree(os.path.join(mod_dst, "Data", "map_bin"), ignore_errors=True)

    runner = os.path.join(wd, "_runner.py")
    with open(runner, "w", encoding="utf-8") as fh:
        fh.write("R_TEST = r%r\n" % os.path.join(REPO, "tests", script))
        fh.write("R_MOD = r%r\n" % mod_dst)
        fh.write("R_TEXTMAP = r%r\n" % text_dst)
        fh.write("R_BINMAP = r%r\n" % bin_dst)
        fh.write("R_EMPTYMAP = r%r\n" % empty_dst)
        fh.write(RUNNER_SRC)

    return subprocess.call([sys.executable, runner])


if __name__ == "__main__":
    sys.exit(main())
