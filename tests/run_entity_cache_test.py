#!/usr/bin/env python3
"""
Frame-level cache regression tests (docs/PERF_ANALYSIS_init441.md fix (1) + (2)).

Runs the real Modules/av.lua and Modules/navigation.lua under LuaJIT-equivalent
semantics with the CET API stubbed and counters on Game.FindEntityByID and
SyncRaycastByQueryFilter, to prove:

  * the entity handle resolves at most once per rendered frame
  * the ground probe (height) resolves at most once per rendered frame

Requirements:
    pip install lupa

Usage:
    python tests/run_entity_cache_test.py [test_name.lua ...]

With no argument it runs every test in CACHE_TESTS. The mod is staged under an
ASCII workdir because the repo path contains non-ASCII characters and Lua's
io.open on Windows uses the ANSI codepage.
"""
import os
import shutil
import subprocess
import sys

WORKDIR = r"C:\davtest_entity"
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOD = os.path.join(REPO, "source", "resources", "bin", "x64", "plugins",
                  "cyber_engine_tweaks", "mods", "DriveAerialVehicle")

CACHE_TESTS = ["entity_cache_test.lua", "height_cache_test.lua"]

RUNNER_SRC = """\
import sys
import lupa.lua51 as lua  # CET runs LuaJIT (Lua 5.1 semantics); 5.4 accepts code the game rejects

L = lua.LuaRuntime()
g = L.globals()

def pp(*a):
    sys.stdout.write(" ".join(str(x) for x in a) + chr(10))
    sys.stdout.flush()

g["print"] = pp

src = open(R_TEST, encoding="utf-8").read()
fn = L.eval("function(...) " + src + " end")
fn(R_MOD)
"""


def run_one(test_name, mod_dst):
    runner = os.path.join(WORKDIR, "_runner_%s.py" % test_name.replace(".", "_"))
    with open(runner, "w", encoding="utf-8") as fh:
        fh.write("R_TEST = r%r\n" % os.path.join(REPO, "tests", test_name))
        fh.write("R_MOD = r%r\n" % mod_dst)
        fh.write(RUNNER_SRC)
    return subprocess.call([sys.executable, runner])


def main():
    try:
        import lupa.lua51  # noqa: F401
    except ImportError:
        sys.exit("lupa is required:  pip install lupa")

    os.makedirs(WORKDIR, exist_ok=True)
    mod_dst = os.path.join(WORKDIR, "mod")
    shutil.rmtree(mod_dst, ignore_errors=True)
    shutil.copytree(MOD, mod_dst)

    for name in (sys.argv[1:] or CACHE_TESTS):
        print("--- %s ---" % name)
        rc = run_one(name, mod_dst)
        if rc != 0:
            return rc
    return 0


if __name__ == "__main__":
    sys.exit(main())
