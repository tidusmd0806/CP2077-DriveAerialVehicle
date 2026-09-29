#!/usr/bin/env python3
"""
Situation cost regression test.

Drives the real core / event / av / engine / hud modules under stubbed CET +
REDscript APIs and counts every Lua -> C# transition per situation, before and
after the situation-cost fixes.

Requirements:
    pip install lupa

Usage:
    python tests/run_situation_cost_test.py
"""
import os
import shutil
import subprocess
import sys

WORKDIR = r"C:\davtest_situation"
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOD = os.path.join(REPO, "source", "resources", "bin", "x64", "plugins",
                  "cyber_engine_tweaks", "mods", "DriveAerialVehicle")

TESTS = ["situation_cost_test.lua"]

RUNNER_SRC = """\
import os
import sys
import lupa.lua51 as lua  # CET runs LuaJIT (Lua 5.1 semantics)

# Utils:ReadJson uses paths relative to the mod root, and the repo path is
# non-ASCII, so run from the staged ASCII copy.
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
        sys.exit("lupa is required:  pip install lupa")

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
