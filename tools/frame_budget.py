#!/usr/bin/env python3
"""Per-frame budget for DriveAerialVehicle from the CET hook-level profile."""
import csv
import re

BS = chr(92)
rows = list(csv.DictReader(open('docs/cet_functions.csv', encoding='utf-8')))


def rel(r):
    s = r['source'].replace(BS, '/')
    m = re.search(r'mods/[^/]+/(.+)$', s)
    return (m.group(1) if m else s) + ':' + r['line']


dav = [r for r in rows if r['cet_mod'] == 'DriveAerialVehicle']
FRAMES = [int(r['calls']) for r in dav if rel(r) == 'init.lua:448'][0]
grand = sum(float(r['exclusive_ms']) for r in rows)
dtot = sum(float(r['exclusive_ms']) for r in dav)

print('profiled frames (onUpdate/onDraw call count) = %d' % FRAMES)
print('all-mod Lua exclusive = %.1f ms -> %.1f us/frame' % (grand, grand * 1000 / FRAMES))
print('DAV exclusive         = %.1f ms -> %.1f us/frame (%.1f%% of all CET Lua)'
      % (dtot, dtot * 1000 / FRAMES, 100 * dtot / grand))
print()

groups = [
    ('onUpdate funnel (Cron + Engine)', ['init.lua:448']),
    ('PlayerPuppet.OnAction', ['Modules/core.lua:404']),
    ('Input/Axis proxy', ['init.lua:395']),
    ('VehicleComponentPS.GetHasAnyDoorOpen', ['Modules/event.lua:188']),
    ('Mappin IsTracked + UpdateRootState', ['Modules/core.lua:1234', 'Modules/core.lua:1239']),
    ('UISystem.QueueEvent x2', ['Modules/hud.lua:154', 'Modules/hud.lua:193']),
    ('hudCar speed/rpm overrides', ['Modules/hud.lua:106', 'Modules/hud.lua:118']),
    ('Dialog overrides (entry-area)', ['Modules/hud.lua:71', 'Modules/hud.lua:83', 'Modules/hud.lua:92']),
]

print('%-42s %8s %8s %9s %8s' % ('group', 'ms', 'us/frame', 'calls', 'of DAV'))
print('-' * 80)
acc = 0.0
for name, keys in groups:
    sel = [r for r in dav if rel(r) in keys]
    ms = sum(float(r['exclusive_ms']) for r in sel)
    c = sum(int(r['calls']) for r in sel)
    acc += ms
    print('%-42s %8.1f %8.1f %9d %7.1f%%'
          % (name, ms, ms * 1000 / FRAMES, c, 100 * ms / dtot))
print('-' * 80)
print('%-42s %8.1f %8.1f' % ('named above', acc, acc * 1000 / FRAMES))
print('%-42s %8.1f %8.1f' % ('DAV total', dtot, dtot * 1000 / FRAMES))
print()
print('at 60 fps (16667 us/frame), DAV occupies %.2f%% of the frame budget'
      % (100 * (dtot * 1000 / FRAMES) / 16667))
print('  onUpdate alone: %.2f%%' % (100 * (1096.04 * 1000 / FRAMES) / 16667))
