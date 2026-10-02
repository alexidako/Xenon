import Foundation

struct MolAtom: Hashable {
    var symbol: String
    var x: Double, y: Double, z: Double
}

struct MolBond: Hashable {
    var a: Int, b: Int, order: Int
}

struct Molecule: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var atoms: [MolAtom]
    var bonds: [MolBond]

    var formula: String {
        var counts: [String: Int] = [:]
        for a in atoms { counts[a.symbol, default: 0] += 1 }
        func part(_ s: String) -> String { counts[s].map { $0 == 1 ? s : "\(s)\($0)" } ?? "" }
        var out = ""
        if counts["C"] != nil { out += part("C") + part("H") }
        for s in counts.keys.sorted() where !(counts["C"] != nil && (s == "C" || s == "H")) { out += part(s) }
        return out
    }

    var mass: Double {
        let table = Dictionary(uniqueKeysWithValues: ElementStore.all.map { ($0.symbol, $0.mass ?? 0) })
        return atoms.reduce(0) { $0 + (table[$1.symbol] ?? 0) }
    }
}

// MARK: parsing

enum MoleculeIO {
    enum Format: String, CaseIterable { case cml, mol, xyz }

    static func load(url: URL) -> Molecule? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        // "2_2_2-trifluoroethanol" -> "2,2,2-Trifluoroethanol"; "carbon_dioxide" -> "Carbon dioxide"
        var fallbackName = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "(?<=\\d)_(?=\\d)", with: ",", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
        fallbackName = fallbackName.prefix(1).uppercased() + fallbackName.dropFirst()
        switch url.pathExtension.lowercased() {
        case "cml": return parseCML(text, fallbackName: fallbackName)
        case "mol", "sdf": return parseMOL(text, fallbackName: fallbackName)
        case "xyz": return parseXYZ(text, fallbackName: fallbackName)
        default: return nil
        }
    }

    // CML: <atom id elementType x3 y3 z3/>, <bond atomRefs2 order/>
    static func parseCML(_ text: String, fallbackName: String) -> Molecule? {
        final class Delegate: NSObject, XMLParserDelegate {
            var atoms: [MolAtom] = []; var ids: [String: Int] = [:]; var bonds: [MolBond] = []
            var name: String?; var inName = false; var buf = ""
            func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
                switch e {
                case "atom":
                    if let el = a["elementType"], let x = a["x3"].flatMap(Double.init), let y = a["y3"].flatMap(Double.init), let z = a["z3"].flatMap(Double.init) {
                        ids[a["id"] ?? "\(atoms.count)"] = atoms.count
                        atoms.append(MolAtom(symbol: el, x: x, y: y, z: z))
                    }
                case "bond":
                    let refs = (a["atomRefs2"] ?? "").split(separator: " ").map(String.init)
                    if refs.count == 2, let i = ids[refs[0]], let j = ids[refs[1]] {
                        let order = Int(a["order"] ?? "1") ?? (a["order"] == "S" ? 1 : a["order"] == "D" ? 2 : a["order"] == "T" ? 3 : 1)
                        bonds.append(MolBond(a: i, b: j, order: max(1, order)))
                    }
                case "name": inName = true; buf = ""
                default: break
                }
            }
            func parser(_ p: XMLParser, foundCharacters s: String) { if inName { buf += s } }
            func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
                if e == "name" { inName = false; if name == nil { name = buf.trimmingCharacters(in: .whitespacesAndNewlines) } }
            }
        }
        guard let data = text.data(using: .utf8) else { return nil }
        let d = Delegate(); let p = XMLParser(data: data); p.delegate = d
        guard p.parse(), !d.atoms.isEmpty else { return nil }
        return Molecule(name: d.name.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackName, atoms: d.atoms, bonds: d.bonds)
    }

    // MDL MOL V2000
    static func parseMOL(_ text: String, fallbackName: String) -> Molecule? {
        let lines = text.components(separatedBy: .newlines)
        guard lines.count > 4 else { return nil }
        let counts = lines[3].split(whereSeparator: { $0 == " " }).compactMap { Int($0.prefix(3)) }
        // counts line is fixed width: aaabbb...
        let na = Int(lines[3].prefix(3).trimmingCharacters(in: .whitespaces)) ?? counts.first ?? 0
        let nb = Int(lines[3].dropFirst(3).prefix(3).trimmingCharacters(in: .whitespaces)) ?? 0
        guard na > 0, nb >= 0, na <= 100_000, nb <= 1_000_000, lines.count >= 4 + na + nb else { return nil }
        var atoms: [MolAtom] = []
        for l in lines[4..<4 + na] {
            let f = l.split(separator: " ")
            guard f.count >= 4, let x = Double(f[0]), let y = Double(f[1]), let z = Double(f[2]) else { return nil }
            atoms.append(MolAtom(symbol: String(f[3]), x: x, y: y, z: z))
        }
        var bonds: [MolBond] = []
        for l in lines[4 + na..<4 + na + nb] {
            let f = l.split(separator: " ").compactMap { Int($0) }
            if f.count >= 3 { bonds.append(MolBond(a: f[0] - 1, b: f[1] - 1, order: max(1, min(3, f[2])))) }
        }
        let title = lines[0].trimmingCharacters(in: .whitespaces)
        return Molecule(name: title.isEmpty ? fallbackName : title, atoms: atoms, bonds: bonds)
    }

    // XYZ has no bonds; infer them from distances.
    static func parseXYZ(_ text: String, fallbackName: String) -> Molecule? {
        let lines = text.components(separatedBy: .newlines)
        guard lines.count > 2, let n = Int(lines[0].trimmingCharacters(in: .whitespaces)), n > 0, n <= 100_000, lines.count >= 2 + n else { return nil }
        var atoms: [MolAtom] = []
        for l in lines[2..<2 + n] {
            let f = l.split(separator: " ")
            guard f.count >= 4, let x = Double(f[1]), let y = Double(f[2]), let z = Double(f[3]) else { return nil }
            atoms.append(MolAtom(symbol: String(f[0]), x: x, y: y, z: z))
        }
        return Molecule(name: lines[1].isEmpty ? fallbackName : lines[1], atoms: atoms, bonds: inferBonds(atoms))
    }

    static func inferBonds(_ atoms: [MolAtom]) -> [MolBond] {
        let cov = Dictionary(uniqueKeysWithValues: ElementStore.all.map { ($0.symbol, $0.radiusCovalent ?? 0.8) })
        var bonds: [MolBond] = []
        for i in 0..<atoms.count {
            for j in (i + 1)..<atoms.count {
                let d = sqrt(pow(atoms[i].x - atoms[j].x, 2) + pow(atoms[i].y - atoms[j].y, 2) + pow(atoms[i].z - atoms[j].z, 2))
                if d > 0.4, d < (cov[atoms[i].symbol] ?? 0.8) + (cov[atoms[j].symbol] ?? 0.8) + 0.4 { bonds.append(MolBond(a: i, b: j, order: 1)) }
            }
        }
        return bonds
    }

    // MARK: export (stand-in for Kalzium's OpenBabel converter)

    static func export(_ m: Molecule, as format: Format) -> String {
        func f(_ v: Double) -> String { String(format: "%.6f", v) }
        switch format {
        case .xyz:
            return "\(m.atoms.count)\n\(m.name)\n" + m.atoms.map { "\($0.symbol) \(f($0.x)) \(f($0.y)) \(f($0.z))" }.joined(separator: "\n") + "\n"
        case .mol:
            var s = "\(m.name)\n Xenon\n\n"
            s += String(format: "%3d%3d  0  0  0  0  0  0  0  0999 V2000\n", m.atoms.count, m.bonds.count)
            for a in m.atoms { s += String(format: "%10.4f%10.4f%10.4f ", a.x, a.y, a.z) + a.symbol.padding(toLength: 3, withPad: " ", startingAt: 0) + " 0  0  0  0  0\n" }
            for b in m.bonds { s += String(format: "%3d%3d%3d  0  0  0\n", b.a + 1, b.b + 1, b.order) }
            return s + "M  END\n"
        case .cml:
            var s = "<molecule>\n <name>\(m.name)</name>\n <atomArray>\n"
            for (i, a) in m.atoms.enumerated() { s += "  <atom id=\"a\(i + 1)\" elementType=\"\(a.symbol)\" x3=\"\(f(a.x))\" y3=\"\(f(a.y))\" z3=\"\(f(a.z))\"/>\n" }
            s += " </atomArray>\n <bondArray>\n"
            for b in m.bonds { s += "  <bond atomRefs2=\"a\(b.a + 1) a\(b.b + 1)\" order=\"\(b.order)\"/>\n" }
            return s + " </bondArray>\n</molecule>\n"
        }
    }
}

enum MoleculeLibrary {
    static let bundled: [Molecule] = {
        let urls = (Bundle.module.urls(forResourcesWithExtension: "cml", subdirectory: "molecules") ?? [])
            + (Bundle.module.urls(forResourcesWithExtension: "mol", subdirectory: "molecules") ?? [])
            + (Bundle.module.urls(forResourcesWithExtension: "cml", subdirectory: nil) ?? [])
            + (Bundle.module.urls(forResourcesWithExtension: "mol", subdirectory: nil) ?? [])
        var seen = Set<String>()
        return urls.filter { seen.insert($0.lastPathComponent).inserted }
            .compactMap(MoleculeIO.load(url:))
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }()
}
