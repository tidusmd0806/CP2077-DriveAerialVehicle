#!/usr/bin/env python3
"""Map CET hook-level profile rows back to the mod source line."""
import csv
import sys
import os
import re

CSV = 'docs/cet_functions.csv'
MOD = 'DriveAerialVehicle'
SRC = 'source/resources/bin/x64/plugins/cyber_engine_tweaks/mods/DriveAerialVehicle'

argv = sys.argv[1:]
if '--mod' in argv:
    MOD = argv[argv.index('--mod') + 1]
if '--csv' in argv:
    CSV = argv[argv.index('--csv') + 1]

all_rows = [r for r in csv.DictReader(open(CSV, encoding='utf-8')) if r['cet_mod'] == MOD]
rows = all_rows
tot_all = sum(float(r['exclusive_ms']) for r in all_rows)
rows.sort(key=lambda r: -float(r['exclusive_ms']))

cache = {}


def srcline(path, ln):
    if path not in cache:
        try:
            cache[path] = open(os.path.join(SRC, path), encoding='utf-8',
                              errors='replace').read().split('\n')
        except OSError:
            cache[path] = []
    f = cache[path]
    if 1 <= ln <= len(f):
        return f[ln - 1].strip()
    return '<out of range>'


print('%-9s %6s %7s %8s %7s %8s %8s %6s  %s' %
      ('excl_ms', 'calls', 'avg_us', 'max_ms', 'gc_ms', 'main_ms', 'wkr_ms', 'ofDAV', 'location'))
print('-' * 145)
tot = 0.0
for r in rows:
    src = r['source']
    m = re.search(r'cyber_engine_tweaks[\\/]mods[\\/][^\\/]+[\\/](.+)$', src, re.I)
    rel = m.group(1) if m else src
    rel = rel.replace('\\', '/')
    ln = int(r['line'])
    tot += float(r['exclusive_ms'])
    print('%-9.2f %6d %7.1f %8.2f %7.2f %8.2f %8.2f %5.1f%%  %s:%d' %
          (float(r['exclusive_ms']), int(r['calls']), float(r['avg_us']),
           float(r['max_ms']), float(r['gc_ms']), float(r['main_ms']),
           float(r['worker_ms']), 100 * float(r['exclusive_ms']) / tot_all, rel, ln))
    print('          %s' % srcline(rel, ln)[:120])
print('-' * 130)
print('total exclusive %.2f ms' % tot)
