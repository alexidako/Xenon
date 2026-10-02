#!/usr/bin/env python3
"""Extract Kalzium's reference data (R/S phrases, tables, glossary, lab equipment) to JSON
and copy the picture assets. Usage: convert_reference.py <kalzium-src> <resources-dir>"""
import json, re, shutil, sys, os
import xml.etree.ElementTree as ET

SRC, RES = sys.argv[1], sys.argv[2]

# --- R/S phrases: strings like "R12: Extremely flammable" in rsdialog.cpp ---
rs = open(f"{SRC}/src/rsdialog.cpp", encoding="utf-8").read()
def phrases(letter):
    out = {}
    for m in re.finditer(r'"(%s(\d+)(?:/\d+)*: [^"]*)"' % letter, rs):
        out[int(m.group(2))] = m.group(1).split(": ", 1)[1]
    return out
rphrases, sphrases = phrases("R"), phrases("S")

# --- tables from tablesdialog.cpp ---
td = open(f"{SRC}/src/tablesdialog.cpp", encoding="utf-8").read()
def section(name_start, name_end):
    a = td.index(name_start); b = td.index(name_end, a) if name_end else len(td)
    return td[a:b]
greek_src = section("void TablesDialog::createGreekSymbolTable", "void TablesDialog::createNumbersTable")
nums_src = section("void TablesDialog::createNumbersTable", None)

def cells(src):
    d = {}
    for m in re.finditer(r'setItem\((\d+), (\d+), new MyWidgetItem\((.*)\)\);', src):
        row, col, expr = int(m.group(1)), int(m.group(2)), m.group(3)
        q = re.match(r'QString\(QChar\((\d+)\)\)', expr)
        if q: val = chr(int(q.group(1)))
        else:
            q = re.search(r'"([^"]*)"', expr)
            val = q.group(1) if q else expr
        d[(row, col)] = val
    return d

g = cells(greek_src)
greek = [{"upper": g.get((r, 0), ""), "lower": g.get((r, 1), ""), "name": g.get((r, 2), "")}
         for r in range(24)]
n = cells(nums_src)
numbers = [{"number": n.get((r, 0), ""), "prefix": n.get((r, 1), ""), "roman": n.get((r, 2), "")}
           for r in range(28)]

# --- glossary and lab equipment ---
glossary = []
for it in ET.parse(f"{SRC}/data/knowledge.xml").getroot().iter("item"):
    glossary.append({"name": it.findtext("name"), "desc": (it.findtext("desc") or "").strip(),
                     "refs": [r.text for r in it.iter("refitem")]})
glossary.sort(key=lambda x: x["name"].lower())

tools = []
for it in ET.parse(f"{SRC}/data/tools.xml").getroot().iter("item"):
    desc = re.sub(r"\s*<br\s*/?>\s*", "\n", it.findtext("desc") or "").strip()
    tools.append({"picture": it.findtext("picture"), "name": it.findtext("name"), "desc": desc})

# one-line "what is it used for" per element, from the school iconset
uses = {}
for line in open(f"{SRC}/data/iconsets/school/iconinformation.txt", encoding="utf-8"):
    m = re.match(r"\s*(\d+)\s+(.*\S)", line)
    if m and not m.group(2).startswith("Information is missing"):
        uses[m.group(1)] = m.group(2)

json.dump({"uses": uses, "rphrases": {str(k): v for k, v in rphrases.items()},
           "sphrases": {str(k): v for k, v in sphrases.items()},
           "greek": greek, "numbers": numbers, "glossary": glossary, "tools": tools},
          open(f"{RES}/reference.json", "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print(len(rphrases), "R,", len(sphrases), "S,", len(greek), "greek,", len(numbers), "numbers,",
      len(glossary), "glossary,", len(tools), "tools")

for sub in ("toolpics", "hazardsymbols"):
    os.makedirs(f"{RES}/{sub}", exist_ok=True)
    for f in os.listdir(f"{SRC}/data/{sub}"):
        if f.lower().endswith((".jpg", ".png")):
            shutil.copy(f"{SRC}/data/{sub}/{f}", f"{RES}/{sub}/{f}")

os.makedirs(f"{RES}/icons", exist_ok=True)
for f in os.listdir(f"{SRC}/data/iconsets/school"):
    if re.fullmatch(r"\d+\.svg", f):
        shutil.copy(f"{SRC}/data/iconsets/school/{f}", f"{RES}/icons/{f}")
print(len(uses), "element uses,", len(os.listdir(f"{RES}/icons")), "icons")

os.makedirs(f"{RES}/molecules", exist_ok=True)
for f in os.listdir(f"{SRC}/data/molecules"):
    if f.endswith((".cml", ".mol")):
        shutil.copy(f"{SRC}/data/molecules/{f}", f"{RES}/molecules/{f}")
