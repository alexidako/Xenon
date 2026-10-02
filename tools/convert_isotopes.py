#!/usr/bin/env python3
"""Convert Kalzium's isotopes.xml and spectra.xml (Blue Obelisk, MIT) to JSON."""
import json, re, sys
import xml.etree.ElementTree as ET

CML = "{http://www.xml-cml.org/schema}"
src_iso, src_spec, dst_iso, dst_spec = sys.argv[1:5]

YEAR = 31_557_600  # seconds per Julian year

def sig_digits(v):
    m = f"{v:.15g}".split("e")[0].replace(".", "").lstrip("0").rstrip("0")
    return len(m)

# The upstream XML labels every half-life as seconds, but some long-lived isotopes
# (U-238, Th-232, K-40, ...) are actually given in YEARS. Genuine second-valued entries are
# either non-round (converted from years) or whole hours/days; year-valued entries are round
# numbers of at most 4 significant digits that are not whole hours. Zr-93 is the exception
# that happens to be divisible by 3600.
YEAR_OVERRIDES = {(40, 93), (92, 236), (90, 230), (28, 59), (42, 93)}
SECOND_OVERRIDES = {(77, 192)}  # Ir-192, 73.8 d: genuine seconds that look like years

def looks_like_years(z, a, v):
    if (z, a) in YEAR_OVERRIDES: return True
    if (z, a) in SECOND_OVERRIDES: return False
    if v is None or v < 1e5 or abs(v - round(v)) > 1e-6 or sig_digits(v) > 4: return False
    return v >= 1e8 or v % 60 != 0

def num(s):
    try: return float(s)
    except (TypeError, ValueError): return None

isotopes = []
converted = []
for iso in ET.parse(src_iso).getroot().iter(CML + "isotope"):
    d = {}
    for e in iso.findall(CML + "scalar"):
        d[e.get("dictRef", "").replace("bo:", "")] = (e.text or "").strip()
    if "atomicNumber" not in d or iso.get("number") is None:
        continue  # empty reference elements
    decays = []
    for k, v in d.items():
        if k.endswith("Decay") and k != "Decay":
            mode = k[:-5]
            decays.append({"mode": mode, "energy": num(v),
                           "percent": num(d.get(k + "Likeliness"))})
    decays.sort(key=lambda x: -(x["percent"] or 0))
    z_, a_ = int(d["atomicNumber"]), int(iso.get("number"))
    hl = num(d.get("halfLife"))
    if looks_like_years(z_, a_, hl):
        converted.append((z_, a_, hl)); hl = hl * YEAR
    isotopes.append({
        "z": int(d["atomicNumber"]),
        "a": int(iso.get("number")),
        "mass": num(d.get("exactMass")),
        "spin": d.get("spin"),
        "magneticMoment": num(d.get("magneticMoment")),
        "halfLife": hl,
        "abundance": num(d.get("relativeAbundance")),
        "decays": decays,
    })
isotopes.sort(key=lambda i: (i["z"], i["a"]))
json.dump(isotopes, open(dst_iso, "w"), separators=(",", ":"))
print(f"wrote {len(isotopes)} isotopes; {len(converted)} half-lives reinterpreted as years")
for z, a, v in converted: print("  ", z, a, f"{v:.4g} y")

spectra = {}
for sp in ET.parse(src_spec).getroot().iter(CML + "spectrum"):
    z = int(re.sub(r"\D", "", sp.get("id")))
    # a few intensities carry a "*" footnote marker
    # xValue = relative intensity, yValue = wavelength in angstrom
    spectra[z] = [{"intensity": float(p.get("xValue").rstrip("*")), "wavelength": float(p.get("yValue"))}
                  for p in sp.iter(CML + "peak")]
json.dump(spectra, open(dst_spec, "w"), separators=(",", ":"))
print(f"wrote spectra for {len(spectra)} elements, {sum(map(len, spectra.values()))} peaks")
