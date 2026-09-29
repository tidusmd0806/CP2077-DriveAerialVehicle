#!/usr/bin/env python3
"""Analyze a CET function-level profiling CSV.

Usage:
  python tools/analyze_cet_csv.py [csv] [mod] [--top N] [--file] [--calls]
"""
import csv
import sys
import collections
import re

argv = sys.argv[1:]
TOP = 40
if '--top' in argv:
    i = argv.index('--top')
    TOP = int(argv[i + 1])
    del argv[i:i + 2]
pos = [a for a in argv if not a.startswith('-')]
CSV = pos[0] if pos else 'docs/cet_functions.csv'
MOD = pos[1] if len(pos) > 1 else None


def short(src):
    # strip long absolute prefixes down to the mod-relative path
    m = re.search(r'cyber_engine_tweaks[\\/]mods[\\/][^\\/]+[\\/](.+)$', src, re.I)
    if m:
        return m.group(1)
    return src


rows = list(csv.DictReader(open(CSV, encoding='utf-8')))
for r in rows:
    for k in ('calls',):
        r['calls'] = int(float(r[k]))
    for k in ('exclusive_ms', 'share_pct', 'inclusive_ms', 'max_ms', 'avg_us',
              'main_ms', 'worker_ms', 'gc_ms'):
        r[k] = float(r[k])

grand = sum(r['exclusive_ms'] for r in rows)
print('grand total exclusive = %.1f ms over %d rows' % (grand, len(rows)))
print()

agg = collections.defaultdict(lambda: dict(calls=0, excl=0.0, incl=0.0, gc=0.0, lines=0))
for r in rows:
    a = agg[r['cet_mod']]
    a['calls'] += r['calls']
    a['excl'] += r['exclusive_ms']
    a['incl'] += r['inclusive_ms']
    a['gc'] += r['gc_ms']
    a['lines'] += 1
print('=== by mod ===')
for k, v in sorted(agg.items(), key=lambda kv: -kv[1]['excl']):
    print('%-32s lines=%4d calls=%8d excl=%8.1f (%5.2f%%) gc=%6.2f' %
          (k, v['lines'], v['calls'], v['excl'], 100 * v['excl'] / grand, v['gc']))
print()

sel = [r for r in rows if (MOD is None or r['cet_mod'] == MOD)]
stot = sum(r['exclusive_ms'] for r in sel)
print('=== %s: %d rows, %.1f ms exclusive (%.1f%% of all) ===' %
      (MOD or 'ALL', len(sel), stot, 100 * stot / grand))
sel.sort(key=lambda r: -r['exclusive_ms'])
for r in sel[:TOP]:
    print('%8.2f %5.2f%% c=%7d max=%7.2f avg=%8.1fus gc=%6.2f  %s:%s' %
          (r['exclusive_ms'], r['share_pct'], r['calls'], r['max_ms'],
           r['avg_us'], r['gc_ms'], short(r['source']), r['line']))
print()

# by file
fa = collections.defaultdict(lambda: dict(calls=0, excl=0.0, gc=0.0, lines=0))
for r in sel:
    f = short(r['source'])
    a = fa[f]
    a['calls'] += r['calls']
    a['excl'] += r['exclusive_ms']
    a['gc'] += r['gc_ms']
    a['lines'] += 1
print('=== %s by file ===' % (MOD or 'ALL'))
for k, v in sorted(fa.items(), key=lambda kv: -kv[1]['excl']):
    print('%-28s lines=%4d calls=%8d excl=%8.1f (%5.2f%% of file-set) gc=%6.2f' %
          (k, v['lines'], v['calls'], v['excl'], 100 * v['excl'] / max(stot, 1e-9), v['gc']))
