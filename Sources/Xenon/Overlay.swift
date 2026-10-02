import SwiftUI

enum Numeration: String, CaseIterable, Identifiable {
    case none = "No numeration", iupac = "IUPAC", cas = "CAS", oldIUPAC = "Old IUPAC"
    var id: String { rawValue }

    /// One label per column of the 18-column table.
    var items: [String] {
        switch self {
        case .none: return []
        case .iupac: return (1...18).map(String.init)
        case .cas: return ["IA", "IIA", "IIIB", "IVB", "VB", "VIB", "VIIB", "VIII", "VIII", "VIII", "IB", "IIB",
                           "IIIA", "IVA", "VA", "VIA", "VIIA", "VIIIA"]
        case .oldIUPAC: return ["1A", "2A", "3A", "4A", "5A", "6A", "7A", "8", "8", "8", "1B", "2B", "3B", "4B", "5B", "6B", "7B", "0"]
        }
    }
}

enum Overlay: String, CaseIterable, Identifiable {
    // color schemes
    case monochrome = "Monochrome"
    case blocks = "Blocks"
    case family = "Family"
    case groups = "Groups"
    case colors = "Colors"
    case iconic = "Iconic"
    // gradients
    case mass = "Atomic mass"
    case covalent = "Covalent radius"
    case vdw = "Van der Waals radius"
    case electronegativity = "Electronegativity (Pauling)"
    case electronAffinity = "Electron affinity"
    case ionization = "First ionization energy"
    case meltingPoint = "Melting point"
    case boilingPoint = "Boiling point"
    case discovery = "Discovery date"
    // special
    case state = "State of matter"

    var id: String { rawValue }

    enum Kind { case scheme, gradient, state }
    var kind: Kind {
        switch self {
        case .monochrome, .blocks, .family, .groups, .colors, .iconic: return .scheme
        case .state: return .state
        default: return .gradient
        }
    }

    static var schemes: [Overlay] { allCases.filter { $0.kind == .scheme } }
    static var gradients: [Overlay] { allCases.filter { $0.kind == .gradient } }

    func value(_ e: Element) -> Double? {
        switch self {
        case .mass: return e.mass
        case .covalent: return e.radiusCovalent
        case .vdw: return e.radiusVDW
        case .electronegativity: return e.electronegativity
        case .electronAffinity: return e.electronAffinity
        case .ionization: return e.ionization
        case .meltingPoint: return e.meltingPoint
        case .boilingPoint: return e.boilingPoint
        case .discovery: return e.discoveryYear
        default: return nil
        }
    }

    var unit: String {
        switch self {
        case .mass: return "u"
        case .meltingPoint, .boilingPoint: return "K"
        case .ionization, .electronAffinity: return "eV"
        case .covalent, .vdw: return "Å"
        default: return ""
        }
    }

    // MARK: scheme colors

    static let blockColors: [(String, Color)] = [
        ("s-Block", Color(red: 0.93, green: 0.50, blue: 0.40)), ("p-Block", Color(red: 0.55, green: 0.78, blue: 0.50)),
        ("d-Block", Color(red: 0.45, green: 0.62, blue: 0.88)), ("f-Block", Color(red: 0.78, green: 0.58, blue: 0.82)),
    ]
    static let groupColors: [Color] = (0..<8).map { Color(hue: Double($0) / 8, saturation: 0.45, brightness: 0.92) }

    /// Swatches for scheme legends.
    var legend: [(String, Color)] {
        switch self {
        case .monochrome: return [("All the elements", Color(white: 0.72))]
        case .blocks: return Self.blockColors
        case .family: return Family.allCases.map { ($0.label, $0.color) }
        case .groups: return (0..<8).map { ("Group \($0 + 1)", Self.groupColors[$0]) }
        case .colors: return []
        case .iconic: return []
        case .state: return [MatterState.solid, .liquid, .gas, .unknown].map { ($0.rawValue, $0.color) }
        default: return []
        }
    }

    var note: String? {
        switch self {
        case .colors: return "Nice colors without meaning (from the Open Babel project)."
        case .iconic: return "Each element is represented by an icon that shows what it is used for."
        default: return nil
        }
    }

    /// Fill color for a tile.
    func color(for e: Element, temperature: Double, range: ClosedRange<Double>) -> Color {
        switch self {
        case .monochrome: return Color(white: 0.72)
        case .blocks:
            let i = ["s", "p", "d", "f"].firstIndex(of: e.block ?? "") ?? 0
            return Self.blockColors[i].1
        case .family: return e.familyKind?.color ?? .gray.opacity(0.4)
        case .groups: return Self.groupColors[max(0, min(7, (e.group ?? 1) - 1))]
        case .colors:
            let c = e.color + [0.5, 0.5, 0.5]
            return Color(red: c[0], green: c[1], blue: c[2])
        case .iconic: return Color(white: 0.9)
        case .state: return e.state(atKelvin: temperature).color
        default:
            guard let v = value(e), range.upperBound > range.lowerBound else { return .gray.opacity(0.25) }
            return Self.gradientColor((v - range.lowerBound) / (range.upperBound - range.lowerBound))
        }
    }

    /// Gradient from cool blue (low) to red (high).
    static func gradientColor(_ t: Double) -> Color {
        Color(hue: 0.60 - 0.60 * min(max(t, 0), 1), saturation: 0.55, brightness: 0.92)
    }

    func range(in elements: [Element]) -> ClosedRange<Double> {
        let vals = elements.compactMap(value)
        return (vals.min() ?? 0)...(vals.max() ?? 1)
    }
}

// MARK: element icons

enum ElementIcons {
    private static var cache: [Int: NSImage] = [:]

    static func image(_ z: Int) -> NSImage? {
        if let c = cache[z] { return c }
        guard let url = Bundle.module.url(forResource: "\(z)", withExtension: "svg", subdirectory: "icons")
                ?? Bundle.module.url(forResource: "\(z)", withExtension: "svg"),
              let img = NSImage(contentsOf: url) else { return nil }
        cache[z] = img
        return img
    }
}
