#!/usr/bin/env python3
"""
Resident obstacle-map cache regression test (fix (1)).

Runs the real Modules/navigation.lua under Lua 5.4 (the same major version CET
uses) against a copy of the shipped Data/map, with the CET API stubbed out.

Requirements:
    pip install lupa

Usage:
    python tests/run_resident_cache_test.py

NOTE: this repo lives under a path containing non-ASCII characters, and Lua's
io.open on Windows uses the ANSI codepage, so the test stages the mod and the
map under C:\\davtest first. Adjust WORKDIR if needed.
"""
import os
import shutil
import subprocess
import sys

WORKDIR = r"C:\davtest"
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOD = os.path.join(REPO, "source", "resources", "bin", "x64", "plugins",
                  "cyber_engine_tweaks", "mods", "DriveAerialVehicle")

RUNNER_SRC = """\
import sys
import lupa.lua51 as lua  # CET runs LuaJIT (Lua 5.1 semantics); 5.4 would accept code the game rejects

L = lua.LuaRuntime()
g = L.globals()


def pp(*a):
    sys.stdout.write(" ".join(str(x) for x in a) + chr(10))
    sys.stdout.flush()


g["print"] = pp

src = open(R_TEST, encoding="utf-8").read()
fn = L.eval("function(...) " + src + " end")
fn(R_MOD, R_MAP, R_BINMAP)
"""


def main():
    try:
        import lupa.lua51  # noqa: F401
    except ImportError:
        sys.exit("lupa is required:  pip install lupa")

    os.makedirs(WORKDIR, exist_ok=True)
    mod_dst = os.path.join(WORKDIR, "mod")
    map_dst = os.path.join(WORKDIR, "testmap")
    bin_dst = os.path.join(WORKDIR, "testbin")
    shutil.rmtree(mod_dst, ignore_errors=True)
    shutil.copytree(MOD, mod_dst)
    shutil.rmtree(map_dst, ignore_errors=True)
    shutil.copytree(os.path.join(MOD, "Data", "map"), map_dst)
    shutil.copy(os.path.join(REPO, "tests", "resident_cache_test.lua"), WORKDIR)

    # The runtime is packed-only now, so the fixture needs packed chunks. Pack the
    # copied text chunks the same way the shipped map was built.
    shutil.rmtree(bin_dst, ignore_errors=True)
    rc = subprocess.call([sys.executable, os.path.join(REPO, "tools", "mapbin_pack.py"),
                         "--src", map_dst, "--dst", bin_dst,
                         "--zmin", "-4", "--zmax", "127"])
    if rc != 0:
        return rc

    # The staged mod copy must not auto-discover packed data from its own tree;
    # the test points at bin_dst explicitly.
    shutil.rmtree(os.path.join(mod_dst, "Data", "map_bin"), ignore_errors=True)

    runner = os.path.join(WORKDIR, "_runner.py")
    with open(runner, "w", encoding="utf-8") as fh:
        fh.write("R_TEST = r%r\n" % os.path.join(WORKDIR, "resident_cache_test.lua"))
        fh.write("R_MOD = r%r\n" % mod_dst)
        fh.write("R_MAP = r%r\n" % map_dst)
        fh.write("R_BINMAP = r%r\n" % bin_dst)
        fh.write(RUNNER_SRC)

    return subprocess.call([sys.executable, runner])


if __name__ == "__main__":
    sys.exit(main())
