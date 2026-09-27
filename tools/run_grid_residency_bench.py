#!/usr/bin/env python3
"""
Full-map residency benchmark: table-per-cell (current) vs flat byte grid (v4).

Stages everything under an ASCII workdir because Lua's io.open on Windows uses the
ANSI codepage and the repo path contains non-ASCII characters.

    python tools/run_grid_residency_bench.py

Requirements: pip install lupa
"""
import os
import shutil
import subprocess
import sys

WORKDIR = r"C:\davbench"
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
# Lua's os.clock() on Windows has ~1 ms resolution, which hides the whole GC tail.
# Give the benchmark a real nanosecond clock.
L.globals()["hrtime"] = time.perf_counter
src = open(R_TEST, encoding="utf-8").read()
fn = L.eval("function(...) " + src + " end")
fn(R_MOD, R_TEXTMAP, R_BINMAP, R_TOOLS)
'''


def stage(workdir):
    os.makedirs(workdir, exist_ok=True)
    mod_dst = os.path.join(workdir, "mod")
    text_dst = os.path.join(workdir, "textmap")
    bin_dst = os.path.join(workdir, "binmap")
    tools_dst = os.path.join(workdir, "tools")

    for d in (mod_dst, text_dst, bin_dst, tools_dst):
        shutil.rmtree(d, ignore_errors=True)
    shutil.copytree(MOD, mod_dst)
    shutil.copytree(os.path.join(MOD, "Data", "map"), text_dst)
    shutil.copytree(os.path.join(REPO, "tools"), tools_dst)

    # Build the binary grids into the ASCII workdir.
    rc = subprocess.call([sys.executable, os.path.join(REPO, "tools", "mapbin_pack.py"),
                         "--src", text_dst, "--dst", bin_dst,
                         "--zmin", "-4", "--zmax", "127"])
    if rc != 0:
        sys.exit(rc)
    return {"base": workdir, "mod": mod_dst, "text": text_dst,
            "bin": bin_dst, "tools": tools_dst}


def run(script, wd):
    runner = os.path.join(wd["base"], "_runner.py")
    with open(runner, "w", encoding="utf-8") as fh:
        fh.write("R_TEST = r%r\n" % os.path.join(wd["tools"], script))
        fh.write("R_MOD = r%r\n" % wd["mod"])
        fh.write("R_TEXTMAP = r%r\n" % wd["text"])
        fh.write("R_BINMAP = r%r\n" % wd["bin"])
        fh.write("R_TOOLS = r%r\n" % wd["tools"])
        fh.write(RUNNER_SRC)
    return subprocess.call([sys.executable, runner])


def main():
    try:
        import lupa.lua51  # noqa: F401
    except ImportError:
        sys.exit("lupa is required:  pip install lupa")

    script = sys.argv[1] if len(sys.argv) > 1 else "grid_residency_bench.lua"
    wd = WORKDIR if script == "grid_residency_bench.lua" else WORKDIR + "_v"
    return run(script, stage(wd))



if __name__ == "__main__":
    sys.exit(main())
