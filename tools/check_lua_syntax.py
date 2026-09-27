#!/usr/bin/env python3
"""
Syntax-gate every Lua file in the mod against the runtime it actually runs on.

Cyber Engine Tweaks embeds **LuaJIT**, which is Lua 5.1 semantics. Code that
parses under Lua 5.4 can still be a hard syntax error in the game -- `//`
(integer division, 5.4-only) being the example that broke mod init here.

The previous check used `lua.eval("function(s) return load(s) end")(src)`,
which silently passed: `load` returns `nil, msg` instead of raising, and the
return value was discarded. This checker inspects the return value.

    python tools/check_lua_syntax.py [root]

Defaults to the mod directory. Exits non-zero if any file fails to parse.
"""
import os
import re
import sys

import lupa.lua51 as lua51

MOD_DEFAULT = os.path.join(
    "source", "resources", "bin", "x64", "plugins",
    "cyber_engine_tweaks", "mods", "DriveAerialVehicle",
)

# Constructs that parse on 5.4 but not on LuaJIT / Lua 5.1.
NEWER = [
    (r"(?<![=/<>!])//(?!=)",        "integer division `//` (5.4)"),
    (r"\bmath\.(maxinteger|mininteger|tointeger|type|unpack)\b",
                                    "math 5.3+ function"),
    (r"\btable\.unpack\b",           "table.unpack (5.2; 5.1 uses bare unpack)"),
    (r"\btable\.pack\b",            "table.pack (5.2)"),
    (r"\btable\.move\b",            "table.move (5.3)"),
    (r"\btable\.pow\b",             "table.pow (5.3)"),
    (r"\butf8\.",                   "utf8 library (5.3)"),
    (r"<\s*(const|close)\s*>",      "<const>/<close> (5.4)"),
    (r"\\x[0-9a-fA-F]{2}",         r"\x hex escape (5.2)"),
    (r"\\z",                       r"\z escape (5.2)"),
    (r"\b0x[0-9a-fA-F]*\.[0-9a-fA-F]+p", "hex float literal (5.2)"),
]

BITWISE = re.compile(r"(?<![&~|<>=])&(?![&])|(?<![&~|<>=])\|(?![|])"
                    r"|(?<![<>=])~(?![=])|<<|>>")


def blank_noncode(src):
    """Blank out comments and string literals so patterns only see real code."""
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c == "-" and src.startswith("--", i):
            m = re.match(r"\[(=*)\[", src[i + 2:])
            if m:  # long comment
                close = "]" + m.group(1) + "]"
                end = src.find(close, i + 2 + len(m.group(0)))
                end = n if end < 0 else end + len(close)
                out.append(" " * (end - i))
                i = end
            else:
                end = src.find("\n", i)
                end = n if end < 0 else end
                out.append(" " * (end - i))
                i = end
        elif re.match(r"\[(=*)\[", src[i:]):
            m = re.match(r"\[(=*)\[", src[i:])
            close = "]" + m.group(1) + "]"
            end = src.find(close, i + len(m.group(0)))
            end = n if end < 0 else end + len(close)
            out.append(" " * (end - i))
            i = end
        elif c in "'\"":
            j = i + 1
            while j < n and src[j] != c:
                j += 2 if src[j] == "\\" else 1
            j = min(j + 1, n)
            out.append(" " * (j - i))
            i = j
        else:
            out.append(c)
            i += 1
    return "".join(out)


def check_file(path, rt):
    with open(path, "r", encoding="utf-8") as fh:
        src = fh.read()
    # Lua 5.1's `load` takes a function, not a string; lupa's compile() handles
    # the difference and raises on a syntax error.
    try:
        rt.compile(src, os.path.basename(path))
    except Exception as e:
        return str(e).replace("\n", " ")
    return None


# LuaJIT 2.1 accepts goto / labelled continue, which stock 5.1 rejects. The mod
# uses them and they work in CET, so neutralise them before the 5.1 gate rather
# than reporting a false failure.
LUAJIT_EXT = re.compile(r"\bgoto\s+[A-Za-z_][A-Za-z0-9_]*|::\s*[A-Za-z_][A-Za-z0-9_]*\s*::")


def check_luajit_dialect(path):
    """Re-parse with goto/labels stripped, so 5.1 can check the rest."""
    src = open(path, encoding="utf-8").read()
    if not LUAJIT_EXT.search(blank_noncode(src)):
        return None, False
    stripped = LUAJIT_EXT.sub("do end", src)
    try:
        lua51.LuaRuntime().compile(stripped, os.path.basename(path))
    except Exception as e:
        return str(e).replace("\n", " "), True
    return None, True


def main():
    # Default to the mod sources AND the test/bench Lua under tools/. The test
    # files are real LuaJIT too -- a `#` comment sneaked into one once and the
    # gate missed it because tools/ was never walked.
    if len(sys.argv) > 1:
        roots = [sys.argv[1]]
    else:
        roots = [MOD_DEFAULT,
                 os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tools")]
        roots = [r for r in roots if os.path.isdir(r)]
    if not roots:
        sys.exit("no such directory")

    rt51 = lua51.LuaRuntime()
    files = []
    for root in roots:
        for base, dirs, names in os.walk(root):
            dirs[:] = [d for d in dirs if d not in ("Data", ".git", "map", "map_bin")]
            for nm in sorted(names):
                if nm.endswith(".lua"):
                    files.append(os.path.join(base, nm))

    bad = 0
    for path in files:
        err = check_file(path, rt51)
        src = blank_noncode(open(path, encoding="utf-8").read())
        hits = [label for pat, label in NEWER if re.search(pat, src)]
        if BITWISE.search(src):
            hits.append("bitwise operator (5.3)")
        if err:
            err2, has_ext = check_luajit_dialect(path)
            if has_ext and err2 is None and not hits:
                print(f"ok    {path}  (LuaJIT goto/label extension)")
                continue
            bad += 1
            print(f"FAIL  {path}\n      {err2 or err}")
        elif hits:
            bad += 1
            print(f"FAIL  {path}\n      parses on 5.1 but uses: {', '.join(hits)}")
        else:
            print(f"ok    {path}")

    print(f"\n{len(files)} files, {bad} problem(s)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
