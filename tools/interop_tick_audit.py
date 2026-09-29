#!/usr/bin/env python3
"""
Static audit of Lua -> C# (REDscript) traffic on the per-frame path.

Why static: the game is not available here, and the question is not "how many
milliseconds" but "how many cross-language transitions does one tick make".
That is countable from source and needs no running game.

Method
------
1. Split every Lua file into function bodies (block-depth on Lua keywords).
2. Count interop primitives per body with an explicit pattern list.
3. Apply loop multipliers for primitives sitting inside a fixed-iteration loop
   (the 32-ray Fibonacci scan is the big one).
4. Sum over a hand-derived reach table: which functions one tick actually
   touches in each situation, and how many times.

The reach table is derived by reading Event:CheckAllEvents,
Core:OperateAerialVehicle, AV:Operate and Engine:Update.  It is deliberately
explicit rather than auto-walked: those functions are branchy, and an automatic
walk would pull every branch in at once and overcount badly.
"""
import os
import re
from collections import defaultdict

MOD = os.path.join("source", "resources", "bin", "x64", "plugins",
                  "cyber_engine_tweaks", "mods", "DriveAerialVehicle")

PRIMITIVES = [
    ("REDscript", r"\bGame\.[A-Za-z_]\w*\s*[(:]"),
    ("SyncRaycast", r":SyncRaycastByQueryFilter\s*\("),
    ("FlyAVSys",   r"\bfly_av_system[:.]\w+"),
    ("entity:",    r"\bentity[:.][A-Z]\w*\s*\("),
    ("player:",    r"\bplayer[:.][A-Z]\w*\s*\("),
    ("inkTextRef", r"\binkTextRef[.:]\w+"),
    ("widget",     r"\bself\.(hud_\w+|input_hint_controller|ink_\w+|landing_vfx_component)[:.]\w+"),
    ("GameSettings", r"\bGameSettings[.:]\w+"),
    ("SaveLock",   r"\bSaveLocksManager[.:]\w+"),
]

BLOCK_OPEN = re.compile(r"\b(function|if|for|while)\b")
# `do` is deliberately absent: `for ... do` already counts via `for`.
END = re.compile(r"\bend\b")
FUNC_DEF = re.compile(r"^\s*(?:local\s+)?function\s+([\w.:]+)\s*\(")


def strip_noise(src):
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if src[i:i + 2] == "--":
            m = re.match(r"--\[(=*)\[", src[i:])
            if m:
                close = "]" + m.group(1) + "]"
                j = src.find(close, i)
                j = n if j < 0 else j + len(close)
            else:
                j = src.find("\n", i)
                j = n if j < 0 else j
            out.append(re.sub(r"[^\n]", " ", src[i:j]))
            i = j
            continue
        if c in "\"'":
            j = i + 1
            while j < n:
                if src[j] == "\\":
                    j += 2
                    continue
                if src[j] == c or src[j] == "\n":
                    j += 1
                    break
                j += 1
            out.append(c + " " * max(0, j - i - 2) + c)
            i = j
            continue
        out.append(c)
        i += 1
    return "".join(out)


def extract_functions(path):
    with open(path, "r", encoding="utf-8") as fh:
        clean = strip_noise(fh.read())
    lines = clean.split("\n")
    funcs, i = {}, 0
    while i < len(lines):
        m = FUNC_DEF.match(lines[i])
        if m:
            name, depth, j, body = m.group(1), 0, i, []
            while j < len(lines):
                depth += len(BLOCK_OPEN.findall(lines[j])) - len(END.findall(lines[j]))
                body.append(lines[j])
                if j > i and depth <= 0:
                    break
                j += 1
            funcs.setdefault(name, "\n".join(body))
            i = j
        i += 1
    return funcs


# --------------------------------------------------------------------------
# Loop multipliers: a primitive sitting inside a fixed-count loop.
# (file, method) -> {primitive label: iterations}
# --------------------------------------------------------------------------
LOOP_MULT = {
    ("navigation.lua", "CollectSphericalRepulsion"): {"SyncRaycast": 32},
    ("navigation.lua", "HasSphericalCollision"):     {"SyncRaycast": 32},
    ("navigation.lua", "RecordObstacleScan"):        {"REDscript": 32},
}


def load(pre_fix=False):
    """Load interop counts per function.

    pre_fix=True replays the pre-fix source shape: every `self:GetEntity()` is
    turned back into `Game.FindEntityByID(self.entity_id)`.  That lets the tool
    report before/after from the same checkout without needing git, so the
    baseline can never drift away from the code being measured.
    """
    tbl = {}
    # hand-written leaf that has no named function of its own
    tbl[("av.lua", "GetPlayerPosition")] = {"REDscript": 1, "player:": 1}
    for fn in sorted(os.listdir(os.path.join(MOD, "Modules"))):
        if not fn.endswith(".lua"):
            continue
        with open(os.path.join(MOD, "Modules", fn), "r", encoding="utf-8") as fh:
            src = fh.read()
        if pre_fix:
            src = src.replace("self:GetEntity()", "Game.FindEntityByID(self.entity_id)")
        for full, body in extract_functions_from_text(src).items():
            meth = full.split(":")[-1].split(".")[-1]
            det = defaultdict(int)
            for label, pat in PRIMITIVES:
                det[label] += len(re.findall(pat, body))
            mult = LOOP_MULT.get((fn, meth), {})
            for label, times in mult.items():
                if det[label]:
                    det[label] *= times
            tbl[(fn, meth)] = dict(det)
    return tbl


def extract_functions_from_text(src):
    clean = strip_noise(src)
    lines = clean.split("\n")
    funcs, i = {}, 0
    while i < len(lines):
        m = FUNC_DEF.match(lines[i])
        if m:
            name, depth, j, body = m.group(1), 0, i, []
            while j < len(lines):
                depth += len(BLOCK_OPEN.findall(lines[j])) - len(END.findall(lines[j]))
                body.append(lines[j])
                if j > i and depth <= 0:
                    break
                j += 1
            funcs.setdefault(name, "\n".join(body))
            i = j
        i += 1
    return funcs


def extract_functions(path):
    with open(path, "r", encoding="utf-8") as fh:
        return extract_functions_from_text(fh.read())


# --------------------------------------------------------------------------
# Reach table: (file, method, calls_per_tick) actually executed per situation.
# Nested cost is already folded in by listing the nested helper separately.
# --------------------------------------------------------------------------
# Reach weights already fold in nesting: e.g. GetPosition is reached directly by
# CheckDistance AND transitively via IsPlayerInEntryArea, GetGroundPosition and
# Navigation:GetHeight, so its weight is the sum of all of those.
SITUATIONS = [
    ("A  Normal, no vehicle summoned",
     [("core.lua", "UpdateGarageInfo", 0.01)],   # 1 Hz throttle, not per tick
     "Engine:Update returns at `if not self.is_finished_init then return end`; "
     "OperateAerialVehicle matches neither IsInVehicle nor IsWaiting. "
     "The 100 Hz loop runs but has nothing to do."),

    ("B  Waiting (vehicle on ground, player outside)",
     [("av.lua", "IsDespawned", 1),              # CheckDespawn
      ("av.lua", "IsPlayerInEntryArea", 2),      # CheckInEntryArea + CheckDoor
      ("av.lua", "IsPlayerIn", 2),              # CheckInAV + OperateAerialVehicle gate
      ("av.lua", "IsDestroyed", 1),
      ("av.lua", "GetPlayerPosition", 1),        # CheckDistance: Game.GetPlayer():GetWorldPosition()
      ("av.lua", "GetPosition", 5),             # 1 CheckDistance + 2 IsPlayerInEntryArea
                                                # + 1 GetGroundPosition + 1 GetHeight
      ("av.lua", "GetQuaternion", 2),            # via ChangeWorldCordinate in IsPlayerInEntryArea
      ("av.lua", "GetGroundPosition", 2),        # CheckHeight + CalculateIdleMode->GetHeight
      ("av.lua", "SetLandingVFXPosition", 1),
      ("av.lua", "ProjectLandingWarning", 1),
      ("av.lua", "GetDoorState", 1),
      ("engine.lua", "IsOnGround", 1),           # CalculateIdleMode -> IsCollision
      ("av.lua", "GetEulerAngles", 2),           # CalculateIdleMode + Engine:Run
      ("engine.lua", "GetDirectionAndAngularVelocity", 1),   # Engine:Run
      ("engine.lua", "ChangeVelocity", 1),        # Engine:Update (ChangeVelocity control type)
      ("engine.lua", "GetPhysicsState", 1),      # Engine:Update
      ("av.lua", "MoveThruster", 1),
      ("av.lua", "ControlSound", 1)],
     "7 checks/tick. Every AV accessor re-runs Game.FindEntityByID - the entity "
     "handle is never cached."),

    ("C  InVehicle, manual flight",
     [("av.lua", "IsPlayerIn", 2),              # CheckInAV + OperateAerialVehicle gate
      ("event.lua", "CheckCombat", 1),
      ("av.lua", "IsEngineOn", 1),
      ("av.lua", "IsDestroyed", 1),
      ("engine.lua", "GetDirectionAndAngularVelocity", 3),
                                                # GetCurrentSpeed + Engine:Run + Engine:Update
      ("av.lua", "GetGroundPosition", 2),        # CheckHeight + CalculateIdleMode path
      ("av.lua", "GetPosition", 3),             # via GetGroundPosition x2 + GetHeight
      ("av.lua", "SetLandingVFXPosition", 1),
      ("av.lua", "ProjectLandingWarning", 1),
      ("hud.lua", "IsVisibleConsumeItemSlot", 1),
      ("hud.lua", "SetHPDisplay", 1),
      ("hud.lua", "SetSpeedMeterValue", 1),
      ("hud.lua", "SetRPMMeterValue", 1),
      ("av.lua", "GetEulerAngles", 2),           # CalculateAVMode + Engine:Run
      ("av.lua", "GetForward", 1),
      ("av.lua", "GetRight", 1),
      ("av.lua", "IsDespawned", 2),             # Engine:Run + Engine:Update guard chain
      ("engine.lua", "AddForce", 1),             # Engine:Update (AddForce control type)
      ("engine.lua", "GetPhysicsState", 1),
      ("av.lua", "MoveThruster", 1),
      ("av.lua", "ControlSound", 1)],
     "10 checks/tick + the full Operate -> CalculateAVMode -> Engine:Run -> "
     "AddForce chain, all at 100 Hz."),

    ("D  InVehicle + autopilot (local avoidance)",
     [("av.lua", "IsPlayerIn", 2),
      ("event.lua", "CheckCombat", 1),
      ("av.lua", "IsEngineOn", 1),
      ("av.lua", "IsDestroyed", 1),
      ("engine.lua", "GetDirectionAndAngularVelocity", 3),
      ("av.lua", "GetGroundPosition", 2),
      ("av.lua", "GetPosition", 3),
      ("av.lua", "SetLandingVFXPosition", 1),
      ("av.lua", "ProjectLandingWarning", 1),
      ("hud.lua", "IsVisibleConsumeItemSlot", 1),
      ("hud.lua", "SetHPDisplay", 1),
      ("hud.lua", "SetSpeedMeterValue", 1),
      ("hud.lua", "SetRPMMeterValue", 1),
      ("engine.lua", "AddForce", 1),
      ("engine.lua", "GetPhysicsState", 1),
      ("navigation.lua", "CollectSphericalRepulsion", 1)],
     "Same 10 checks, plus a 32-ray synchronous sphere scan every tick."),
]


# Functions whose body contained a Game.FindEntityByID(self.entity_id) before
# fix (1).  After the fix they all route through AV:GetEntity(), which resolves
# at most once per rendered frame instead of once per call.  Used to project the
# post-fix numbers without re-deriving the whole reach table by hand.
FIND_ENTITY_METHODS = {
    "IsPlayerIn", "IsDestroyed", "IsDespawned", "IsEngineOn", "GetPosition",
    "GetForward", "GetRight", "GetUp", "GetQuaternion", "GetEulerAngles",
    "IsMountedCombatSeat", "ToggleCrystalDome", "ChangeDoorState", "LockDoor",
    "UnlockDoor", "GetDoorState", "SetDestroyAppearance", "ToggleRadio",
    "ChangeAppearance", "ProjectLandingWarning", "SetThrusterComponent",
    "MoveThruster", "ToggleThruster", "ToggleHeliThruster", "Unmount",
}


def main():
    tbl = load()                # current source (fix (1) applied)
    tbl0 = load(pre_fix=True)   # same source with GetEntity() replayed as FindEntityByID

    def cost(mod, meth):
        key = (mod, meth)
        if key not in tbl:
            return None
        return sum(tbl[key].values()), tbl[key]

    def cost0(mod, meth):
        key = (mod, meth)
        if key not in tbl0:
            return None
        return sum(tbl0[key].values())

    print("=" * 84)
    print("Lua -> C# interop transitions per tick   (DAV.time_resolution = 0.01 s = 100 Hz)")
    print("=" * 84)

    totals = {}
    totals0 = {}
    for label, reach, note in SITUATIONS:
        total = 0.0
        prim = defaultdict(float)
        rows, missing = [], []
        for mod, meth, w in reach:
            c = cost(mod, meth)
            if c is None:
                missing.append("%s:%s" % (mod, meth))
                continue
            n, det = c
            total += n * w
            for k, v in det.items():
                prim[k] += v * w
            rows.append((n * w, mod, meth, n, w, det))
        totals[label] = total
        totals0[label] = sum((cost0(m, f) or 0) * w for m, f, w in reach)
        print("\n### %s" % label)
        print("    %s" % note)
        print("    %-18s %-34s %6s %7s %s" %
              ("module", "function", "interop", "x tick", "breakdown"))
        for tot, mod, meth, n, w, det in sorted(rows, key=lambda r: -r[0]):
            br = ", ".join("%s=%g" % (k, v * w)
                          for k, v in sorted(det.items(), key=lambda kv: -kv[1] * w)
                          if v * w > 0)
            print("    %-18s %-34s %6g %7s %s" % (mod, meth, tot, ("x%g" % w), br))
        if missing:
            print("    (not found: %s)" % ", ".join(missing))
        print("    " + "-" * 78)
        print("    TOTAL  %6.0f per tick   =  %7.0f per second" % (total, total * 100))
        print("    mix    " + ", ".join("%s=%.0f" % (k, v)
                                       for k, v in sorted(prim.items(),
                                                         key=lambda kv: -kv[1])
                                       if v > 0))

    print("\n" + "=" * 84)
    print("Ground probe (Navigation:GetHeight -> SyncRaycastByQueryFilter)")
    print("-" * 84)
    print("  %-44s %14s %14s" % ("situation", "before f(2)", "after f(2)"))
    for label, reach, _ in SITUATIONS:
        # Each GetHeight used to cost one raycast plus two position resolutions
        # (one directly, one inside AV:GetGroundPosition).
        n = sum(w for mod, meth, w in reach if meth == "GetGroundPosition")
        if n == 0:
            print("  %-44s %14s %14s" % (label, "-", "-"))
            continue
        before_r = n * 100
        before_p = 2 * n * 100
        # Frame-cached: one probe per rendered frame regardless of caller count.
        for fps in (60,):
            after_r = fps
            after_p = fps
        print("  %-44s %9d/s (%d) %9d/s (%d)" % (
            label, before_r, before_p, after_r, after_p))
    print("  " + "-" * 82)
    print("  numbers are raycasts/s with (GetWorldPosition/s) alongside.")
    print("  before: one probe per caller -- Event:CheckHeight and")
    print("          Engine:CalculateIdleMode both ask in the same tick.")
    print("  after : one probe per rendered frame, position resolved once and")
    print("          handed to AV:GetGroundPosition(from_pos).")
    print("=" * 84)

    print("\n" + "=" * 84)
    print("Summary - C# transitions per second, fix (1) only")
    print("  (fix (2) is reported separately above; the two are additive)")
    print("  %-48s %9s %9s %9s" % ("situation", "before", "after f(1)", "saved"))
    for label, reach, _ in SITUATIONS:
        before = totals0[label]
        # AV:GetEntity() resolves at most once per rendered frame; charge one
        # transition per tick as a conservative upper bound.
        after = totals[label] + (1 if any(m == "av.lua" and f in FIND_ENTITY_METHODS
                                         for m, f, _w in reach) else 0)
        pct = (100.0 * (before - after) / before) if before else 0.0
        print("  %-48s %7.0f/s %8.0f/s %8.1f%%" % (label, before * 100,
                                                   after * 100, pct))
    print("  " + "-" * 70)
    print("  before  = same source with self:GetEntity() replayed as")
    print("            Game.FindEntityByID(self.entity_id) at every accessor")
    print("  after   = current source + one shared GetEntity resolution/tick")
    print("  Remaining: the entity method calls themselves, SyncRaycast,")
    print("  HUD writes and GameSettings reads.")
    print("=" * 84)


if __name__ == "__main__":
    main()
