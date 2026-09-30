#!/usr/bin/env python3
"""
Time-scale / landing-stop regression test.

Asserts that exposing DAV.time_resolution as a user setting is safe:

  A. TimeScale unit maths (seconds<->ticks, per-tick increments, lead, clamps)
  B. The AutoLanding stop point stays above the ground clearance at every
     supported resolution, and the uncompensated model demonstrably does not.

Requirements:
    pip install lupa

Usage:
    python tests/run_timescale_landing_test.py
"""
import os
import shutil
import subprocess
import sys

WORKDIR = r"C:\davtest_timescale"
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOD = os.path.join(REPO, "source", "resources", "bin", "x64", "plugins",
                  "cyber_engine_tweaks", "mods", "DriveAerialVehicle")

TESTS = ["timescale_landing_test.lua"]

RUNNER_SRC = """\
import os
import sys
import lupa.lua51 as lua  # CET runs LuaJIT (Lua 5.1 semantics)

# The repo path is non-ASCII, so run from the staged ASCII copy.
os.chdir(R_MOD)

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
        sys.exit("lupa.lua51 is required:  pip install lupa")

    os.makedirs(WORKDIR, exist_ok=True)
    mod_dst = os.path.join(WORKDIR, "mod")
    shutil.rmtree(mod_dst, ignore_errors=True)
    shutil.copytree(MOD, mod_dst)

    for name in (sys.argv[1:] or TESTS):
        print("--- %s ---" % name)
        rc = run_one(name, mod_dst)
        if rc != 0:
            return rc
    return 0


if __name__ == "__main__":
    sys.exit(main())
