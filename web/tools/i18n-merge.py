#!/usr/bin/env python3
"""Merge tools/i18n/manual_src/*.py (tuples of key, ru, uk, zh, es, fr) into tools/i18n/manual/<lang>.json."""
import glob, json, os
LANGS = ['ru', 'uk', 'zh', 'es', 'fr']
out = {l: {} for l in LANGS}
for f in sorted(glob.glob('tools/i18n/manual_src/*.py')):
    ns = {}
    exec(open(f, encoding='utf-8').read(), ns)
    for row in ns['B']:
        assert len(row) == 6, row[0]
        for l, v in zip(LANGS, row[1:]):
            out[l][row[0]] = v
os.makedirs('tools/i18n/manual', exist_ok=True)
for l in LANGS:
    json.dump(out[l], open(f'tools/i18n/manual/{l}.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=1, sort_keys=True)
    print(l, len(out[l]))
