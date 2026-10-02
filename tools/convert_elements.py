#!/usr/bin/env python3
"""Convert Kalzium's libscience/data/elements.xml (Blue Obelisk, MIT) to elements.json."""
import json, sys
import xml.etree.ElementTree as ET

NS = {"c": "http://www.xml-cml.org/schema"}
SRC = sys.argv[1]
DST = sys.argv[2]

def num(s):
    try: return float(s)
    except (TypeError, ValueError): return None

out = []
for atom in ET.parse(SRC).getroot().iter("{http://www.xml-cml.org/schema}atom"):
    d = {}
    for e in atom:
        key = e.get("dictRef", "").replace("bo:", "")
        if e.tag.endswith("label"):
            d[key] = e.get("value")
        else:
            d[key] = (e.text or "").strip()
    if "atomicNumber" not in d:
        continue
    z = int(d["atomicNumber"])
    if z < 1:
        continue
    color = [float(x) for x in d.get("elementColor", "0.5 0.5 0.5").split()]
    out.append({
        "z": z,
        "symbol": d["symbol"],
        "name": d["name"],
        "mass": num(d.get("mass")),
        "exactMass": num(d.get("exactMass")),
        "ionization": num(d.get("ionization")),
        "electronAffinity": num(d.get("electronAffinity")),
        "electronegativity": num(d.get("electronegativityPauling")),
        "radiusCovalent": num(d.get("radiusCovalent")),
        "radiusVDW": num(d.get("radiusVDW")),
        "boilingPoint": num(d.get("boilingpoint")),
        "meltingPoint": num(d.get("meltingpoint")),
        "block": d.get("periodTableBlock"),
        "period": int(d["period"]) if d.get("period") else None,
        "group": int(d["group"]) if d.get("group") else None,
        "family": d.get("family"),
        "configuration": d.get("electronicConfiguration"),
        "nameOrigin": d.get("nameOrigin"),
        "discoveryDate": d.get("discoveryDate"),
        "discoveryCountry": [x.strip() for x in d.get("discoveryCountry", "").split(",") if x.strip()],
        "discoverers": [x.strip() for x in d.get("discoverers", "").split(";") if x.strip()],
        "oxidation": [int(x) for x in d.get("oxidation", "").replace(" ", "").split(",") if x],
        "color": color,
    })
out.sort(key=lambda e: e["z"])
json.dump(out, open(DST, "w"), indent=1)
print(f"wrote {len(out)} elements")
