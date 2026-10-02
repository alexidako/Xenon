import SwiftUI

struct Decay: Decodable, Hashable {
    let mode: String
    let energy: Double?   // MeV
    let percent: Double?

    /// "betaminusneutron" -> "β⁻ + n"
    var label: String {
        let tokens: [(String, String)] = [
            ("betaminus", "β⁻"), ("betaplus", "β⁺"), ("alpha", "α"),
            ("neutron", "n"), ("proton", "p"), ("fission", "fission"), ("ec", "EC"),
        ]
        var rest = Substring(mode)
        var parts: [String] = []
        outer: while !rest.isEmpty {
            var count = ""
            while let c = rest.first, c.isNumber { count.append(c); rest = rest.dropFirst() }
            for (key, symbol) in tokens where rest.hasPrefix(key) {
                parts.append(count + (symbol == "fission" ? tr("Fission") : symbol))
                rest = rest.dropFirst(key.count)
                continue outer
            }
            parts.append(String(rest)); break
        }
        return parts.joined(separator: " + ")
    }
}

struct Isotope: Identifiable, Decodable, Hashable {
    let z: Int
    let a: Int
    let mass: Double?
    let spin: String?
    let magneticMoment: Double?
    let halfLife: Double?   // seconds
    let abundance: Double?  // percent
    let decays: [Decay]

    var id: Int { z * 1000 + a }

    var halfLifeText: String {
        guard let s = halfLife else { return abundance != nil ? "stable" : "—" }
        let units: [(String, Double)] = [
            ("y", 31_557_600), ("d", 86_400), ("h", 3_600), ("min", 60), ("s", 1),
            ("ms", 1e-3), ("µs", 1e-6), ("ns", 1e-9), ("ps", 1e-12),
        ]
        for (name, size) in units where s >= size {
            let v = s / size
            return v.formatted(.number.precision(.significantDigits(1...4))) + " " + name
        }
        return String(format: "%.2e s", s)
    }
}

struct SpectrumLine: Decodable, Hashable {
    let intensity: Double
    let wavelength: Double  // angstrom
    var nanometers: Double { wavelength / 10 }
}

enum IsotopeStore {
    static let all: [Isotope] = load("isotopes") ?? []
    static let byElement: [Int: [Isotope]] = Dictionary(grouping: all, by: \.z)
}

enum SpectrumStore {
    static let byElement: [Int: [SpectrumLine]] = {
        let raw: [String: [SpectrumLine]] = load("spectra") ?? [:]
        return Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in Int(k).map { ($0, v) } })
    }()
}

private func load<T: Decodable>(_ name: String) -> T? {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json"),
          let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(T.self, from: data)
}

/// Approximate display color for a visible wavelength in nm (Bruton's algorithm).
func wavelengthColor(_ nm: Double, clampToVisible: Bool = false) -> Color {
    if clampToVisible, nm < 380 || nm > 780 { return Color(white: nm < 380 ? 0.35 : 0.2) }
    var r = 0.0, g = 0.0, b = 0.0
    switch nm {
    case 380..<440: r = -(nm - 440) / 60; b = 1
    case 440..<490: g = (nm - 440) / 50; b = 1
    case 490..<510: g = 1; b = -(nm - 510) / 20
    case 510..<580: r = (nm - 510) / 70; g = 1
    case 580..<645: r = 1; g = -(nm - 645) / 65
    case 645...780: r = 1
    default: return .gray
    }
    let edge: Double = nm < 420 ? 0.3 + 0.7 * (nm - 380) / 40 : nm > 700 ? 0.3 + 0.7 * (780 - nm) / 80 : 1
    return Color(red: r * edge, green: g * edge, blue: b * edge)
}
