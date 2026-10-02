#!/usr/bin/env python3
"""Lists English strings in the Swift sources that have no translation (checks Russian, which has every key the others do)."""
import re, glob, os, sys
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
lang = sys.argv[1] if len(sys.argv) > 1 else 'ru'
folder = {'zh': 'zh-Hans'}.get(lang, lang)
have = set()
for m in re.finditer(r'^"((?:[^"\\]|\\.)*)" = ', open(os.path.join(ROOT, f'packaging/localization/{folder}.lproj/Localizable.strings'), encoding='utf-8').read(), re.M):
    have.add(m.group(1).replace('\\"', '"').replace('\\n', '\n').replace('\\\\', '\\'))
pat = re.compile(r'\b(?:tr|trc\("[a-z]+",\s*|Text|Button|Label|Section|Toggle|Picker|GroupBox|LabeledContent|TextField|Menu|Stepper|DisclosureGroup|TableColumn|Link)\(\s*"((?:[^"\\]|\\.)*)"')
pat2 = re.compile(r'\.(?:navigationTitle|help|tabItem|accessibilityLabel|searchable\(text:[^)]*prompt:)\(?\s*"((?:[^"\\]|\\.)*)"|prompt:\s*(?:Text\()?"((?:[^"\\]|\\.)*)"')
missing = {}
for f in glob.glob(os.path.join(ROOT, 'Sources/Xenon/**/*.swift'), recursive=True):
    if any(x in f for x in ('VRT/', 'SelfTest', 'FuzzTests')): continue
    for i, line in enumerate(open(f, encoding='utf-8'), 1):
        for m in list(pat.finditer(line)) + list(pat2.finditer(line)):
            k = next(g for g in m.groups() if g is not None)
            if '\\(' in k or not re.search(r'[A-Za-z]{2,}', k): continue
            k = k.replace('\\"', '"').replace('\\n', '\n')
            if k not in have: missing.setdefault(k, f'{os.path.relpath(f, ROOT)}:{i}')
for k, w in sorted(missing.items(), key=lambda x: x[1]): print(f'{w}\t{k}')
print(len(missing), 'missing', file=sys.stderr)
