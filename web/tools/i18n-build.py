#!/usr/bin/env python3
"""Builds the translation dictionaries.

Inputs
  tools/i18n/keys.json            English strings the app can show (from tools/i18n-extract.mjs)
  KDE Kalzium po files            official translations of elements, glossary, lab equipment and the Kalzium interface
  tools/i18n/manual/<lang>.json   translations written for Xenon's own strings (English -> text)
Outputs
  src/i18n/locales/<lang>.json    one dictionary per language, English text -> translation
  tools/i18n/todo.json            strings that still have no translation in some language

Usage: i18n-build.py <path to kalzium/po>
"""
import ast, difflib, json, os, re, sys

LANGS = {'ru': 'ru', 'uk': 'uk', 'zh': 'zh_CN', 'es': 'es', 'fr': 'fr'}
PO_DIR = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser('~/Downloads/kalzium-master/po')
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..'))
os.makedirs(os.path.join(ROOT, 'src/i18n/locales'), exist_ok=True)

def parse_po(path):
    """Returns {msgid: msgstr} for translated, non-fuzzy, singular entries (context-free entries win)."""
    entries, cur, field, fuzzy = [], {}, None, False
    def flush():
        nonlocal cur
        if cur.get('id') is not None and 'str' in cur and not cur.get('plural'):
            entries.append(cur)
        cur = {}
    for raw in open(path, encoding='utf-8'):
        line = raw.rstrip('\n')
        if line.startswith('#,'):
            fuzzy = 'fuzzy' in line
            cur['fuzzy'] = fuzzy
        elif line.startswith('msgctxt'):
            if 'id' in cur: flush()
            cur['ctx'] = ast.literal_eval(line[7:].strip()); field = 'ctx'
        elif line.startswith('msgid_plural'):
            cur['plural'] = True; field = 'plural'
        elif line.startswith('msgid'):
            if 'id' in cur: flush()
            cur['id'] = ast.literal_eval(line[5:].strip()); field = 'id'
        elif line.startswith('msgstr['):
            cur['plural'] = True; field = 'pl'
        elif line.startswith('msgstr'):
            cur['str'] = ast.literal_eval(line[6:].strip()); field = 'str'
        elif line.startswith('"'):
            v = ast.literal_eval(line)
            if field in ('ctx', 'id', 'str'): cur[field] = cur.get(field, '') + v
        elif line == '' :
            if 'id' in cur: flush()
            fuzzy = False
    flush()
    out, withctx = {}, {}
    for e in entries:
        if not e['id'] or not e['str'] or e.get('fuzzy'): continue
        (withctx if e.get('ctx') else out).setdefault(e['id'], e['str'])
    for k, v in withctx.items(): out.setdefault(k, v)
    return out

def norm(s):
    return re.sub(r'\s+', ' ', s).strip()

keys = json.load(open(os.path.join(HERE, 'i18n/keys.json')))
# strings that only look like text: drop them
def keep(k):
    if k.startswith(' ') or k.endswith(' '): return False
    if re.match(r'^M[\d.-]', k) or '->' in k or '|' in k and not k.startswith(('unit|', 'theme|')): return False
    if re.match(r'^(a|b)[A-Z(]', k) or re.search(r'\\[bdsw(]', k): return False
    return True
keys = {k: v for k, v in keys.items() if keep(k)}

# Data strings that come from the JSON files
data = {}
ref = json.load(open(os.path.join(ROOT, 'src/data/reference.json')))
els = json.load(open(os.path.join(ROOT, 'src/data/elements.json')))
def add(s): 
    if s and s.strip(): data.setdefault(s, 'data')
for e in els: add(e['name']); add(e.get('nameOrigin'))
for g in ref['glossary']:
    add(g['name']); add(g['desc'])
    for r in g.get('refs', []): add(r)
for t in ref['tools']: add(t['name']); add(t['desc'])
for n, s in ref['rphrases'].items(): add(f'R{n}: {s}')
for n, s in ref['sphrases'].items(): add(f'S{n}: {s}')
for g in ref['greek']: add(g['name'])
for u in ref['uses'].values(): add(u)
mols = os.path.join(ROOT, 'src/data/molecules')
for f in os.listdir(mols):
    m = re.search(r'<name[^>]*>([^<]+)</name>', open(os.path.join(mols, f), encoding='utf-8').read())
    if m: add(m.group(1).strip())
extra = set()
for _c in os.listdir(os.path.join(HERE, 'i18n/manual')) if os.path.isdir(os.path.join(HERE, 'i18n/manual')) else []:
    extra |= set(json.load(open(os.path.join(HERE, 'i18n/manual', _c), encoding='utf-8')))
allkeys = list(keys) + [k for k in data if k not in keys] + [k for k in sorted(extra) if k not in keys and k not in data]

todo, stats = {}, {}
for code, po_code in LANGS.items():
    po = parse_po(os.path.join(PO_DIR, po_code, 'kalzium.po'))
    pon = {norm(k): v for k, v in po.items()}
    manual_path = os.path.join(HERE, f'i18n/manual/{code}.json')
    manual = json.load(open(manual_path, encoding='utf-8')) if os.path.exists(manual_path) else {}
    out, from_po, from_manual = {}, 0, 0
    for k in allkeys:
        if k in manual and manual[k]:
            out[k] = manual[k]; from_manual += 1                      # our own text wins
        elif k in po or norm(k) in pon:
            v = po.get(k) or pon[norm(k)]
            out[k] = v; from_po += 1
        elif len(k) > 60 and k in data and (near := difflib.get_close_matches(norm(k), list(pon), n=1, cutoff=0.93)):
            out[k] = pon[near[0]]; from_po += 1                     # same sentence with a small upstream wording change
        else:
            todo.setdefault(k, []).append(code)
    # keep the dictionaries small: drop identity entries
    out = {k: v for k, v in out.items() if v != k}
    json.dump(dict(sorted(out.items())), open(os.path.join(ROOT, f'src/i18n/locales/{code}.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=0)
    stats[code] = (len(allkeys), from_po, from_manual)
json.dump(todo, open(os.path.join(HERE, 'i18n/todo.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
for code, (n, p, m) in stats.items():
    print(f'{code}: {n} keys, {p} from KDE, {m} manual, {n - p - m} missing')
