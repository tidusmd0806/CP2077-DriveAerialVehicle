#!/usr/bin/env python3
"""
Control-loop gate regression tests (docs/PERF_PLAN_event_driven.md, A群).

Proves the control-loop body sleeps in Idle/Normal, paces CheckAllEvents to
~20 Hz in Waiting while keeping GetActions at full rate, never skips the
active situations, re-opens on a situation change, keeps the measured-dt
sampler ticking through a sleep, and leaves the Cron timer alone.

Requirements:
    pip install lupa

Usage:
    python tests/run_loop_gate_test.py [test_name.lua ...]

The mod is staged under an ASCII workdir because the repo path contains
non-ASCII characters and Lua's io.open on Windows uses the ANSI codepage.
"""
import os
import shutil
import subprocess
import sys

WORKDIR = r"C:\davtest_loopgate"
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOD = os.path.join(REPO, "source", "resources", "bin", "x64", "plugins",
                  "cyber_engine_tweaks", "mods", "DriveAerialVehicle")

LOOP_GATE_TESTS = ["loop_gate_test.lua"]

RUNNER_SRC = """\
import sys
import lupa.lua51 as lua  # CET runs LuaJIT (Lua 5.1 semantics)

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

    for name in (sys.argv[1:] or LOOP_GATE_TESTS):
        print("--- %s ---" % name)
        rc = run_one(name, mod_dst)
        if rc != 0:
            return rc
    return 0


if __name__ == "__main__":
    sys.exit(main())