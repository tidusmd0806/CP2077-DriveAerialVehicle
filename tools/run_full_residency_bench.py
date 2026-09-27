#!/usr/bin/env python3
"""
Full-residency benchmark, run once per representation in a SEPARATE process.

Sharing a process makes the second run's GC state depend on the first run's
~180 MB of freed tables, which swamps the effect being measured.

    python tools/run_full_residency_bench.py

Requirements: pip install lupa
"""
import os
import shutil
import subprocess
import sys

WORKDIR = r"C:\davfull"
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
fn(R_MOD, R_TEXTMAP, R_BINMAP, R_EMPTYMAP, MODE)
'''


def main():
    try:
        import lupa.lua51  # noqa: F401
    except ImportError:
        sys.exit("lupa is required:  pip install lupa")

    mod_dst = os.path.join(WORKDIR, "mod")
    text_dst = os.path.join(WORKDIR, "textmap")
    bin_dst = os.path.join(WORKDIR, "binmap")
    empty_dst = os.path.join(WORKDIR, "emptymap")

    for d in (mod_dst, text_dst, bin_dst, empty_dst):
        shutil.rmtree(d, ignore_errors=True)
    shutil.copytree(MOD, mod_dst)
    shutil.copytree(os.path.join(MOD, "Data", "map"), text_dst)
    os.makedirs(empty_dst, exist_ok=True)

    rc = subprocess.call([sys.executable, os.path.join(REPO, "tools", "mapbin_pack.py"),
                         "--src", text_dst, "--dst", bin_dst,
                         "--zmin", "-4", "--zmax", "127"])
    if rc != 0:
        return rc
    shutil.rmtree(os.path.join(mod_dst, "Data", "map_bin"), ignore_errors=True)

    runner = os.path.join(WORKDIR, "_runner.py")
    with open(runner, "w", encoding="utf-8") as fh:
        fh.write("R_TEST = r%r\n" % os.path.join(REPO, "tools", "full_residency_bench.lua"))
        fh.write("R_MOD = r%r\n" % mod_dst)
        fh.write("R_TEXTMAP = r%r\n" % text_dst)
        fh.write("R_BINMAP = r%r\n" % bin_dst)
        fh.write("R_EMPTYMAP = r%r\n" % empty_dst)
        fh.write("MODE = %r\n")

    for mode in ("legacy", "packed"):
        with open(runner, "w", encoding="utf-8") as fh:
            fh.write("R_TEST = r%r\n" % os.path.join(REPO, "tools", "full_residency_bench.lua"))
            fh.write("R_MOD = r%r\n" % mod_dst)
            fh.write("R_TEXTMAP = r%r\n" % text_dst)
            fh.write("R_BINMAP = r%r\n" % bin_dst)
            fh.write("R_EMPTYMAP = r%r\n" % empty_dst)
            fh.write("MODE = %r\n" % mode)
            fh.write(RUNNER_SRC)
        rc = subprocess.call([sys.executable, runner])
        if rc != 0:
            return rc
    return 0


if __name__ == "__main__":
    sys.exit(main())
