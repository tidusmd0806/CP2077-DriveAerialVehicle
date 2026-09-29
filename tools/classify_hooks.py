#!/usr/bin/env python3
"""Classify DAV profile rows: always-on global hooks vs the onUpdate funnel."""
import csv
import re

BS = chr(92)
rows = [r for r in csv.DictReader(open('docs/cet_functions.csv', encoding='utf-8'))
        if r['cet_mod'] == 'DriveAerialVehicle']
tot = sum(float(r['exclusive_ms']) for r in rows)


def rel(r):
    s = r['source'].replace(BS, '/')
    m = re.search(r'mods/[^/]+/(.+)$', s)
    return (m.group(1) if m else s) + ':' + r['line']


# Hooks that fire for the whole game / whole input stream regardless of whether the
# AV exists. They are pure overhead while the mod is "idle".
ALWAYS_ON = {
    'Modules/core.lua:404',    # PlayerPuppet.OnAction
    'init.lua:395',            # Input/Axis proxy
    'init.lua:358',            # Input/Key proxy
    'Modules/event.lua:188',   # VehicleComponentPS.GetHasAnyDoorOpen
    'Modules/core.lua:1234',   # BaseMappinBaseController.IsTracked
    'Modules/core.lua:1239',   # BaseMappinBaseController.UpdateRootState
    'Modules/hud.lua:154',     # UISystem.QueueEvent
    'Modules/hud.lua:193',     # UISystem.QueueEvent (after)
    'Modules/hud.lua:106',     # hudCarController.OnSpeedValueChanged
    'Modules/hud.lua:118',     # hudCarController.OnRpmValueChanged
    'Modules/hud.lua:171',     # VehicleComponent.ReactToHPChange
    'Modules/event.lua:164',   # Entity.ScheduleAppearanceChange
}

g = gc = 0.0
print('--- ALWAYS-ON GLOBAL HOOKS (fire whether or not the AV exists) ---')
sel = [(rel(r), r) for r in rows if rel(r) in ALWAYS_ON]
sel.sort(key=lambda kv: -float(kv[1]['exclusive_ms']))
for k, r in sel:
    g += float(r['exclusive_ms'])
    gc += int(r['calls'])
    print('  %-36s %8.2f ms  %7d calls  %6.1f us/call  worker=%6.1f ms'
          % (k, float(r['exclusive_ms']), int(r['calls']), float(r['avg_us']),
             float(r['worker_ms'])))
print('  TOTAL %.1f ms = %.1f%% of DAV, %d calls' % (g, 100 * g / tot, gc))
print()
on = [r for r in rows if rel(r) == 'init.lua:448'][0]
print('DAV total      : %8.1f ms, %d calls' % (tot, sum(int(r['calls']) for r in rows)))
print('onUpdate only  : %8.1f ms (%.1f%%)' % (float(on['exclusive_ms']), 100 * float(on['exclusive_ms']) / tot))
rest = tot - float(on['exclusive_ms'])
print('non-onUpdate   : %8.1f ms (%.1f%% of DAV)' % (rest, 100 * rest / tot))
print('  of which always-on global hooks: %.1f ms = %.1f%% of non-onUpdate'
      % (g, 100 * g / rest))
