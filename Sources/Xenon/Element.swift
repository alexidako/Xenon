import SwiftUI

struct Element: Identifiable, Decodable, Hashable {
    let z: Int
    let symbol: String
    let name: String
    let mass: Double?
    let exactMass: Double?
    let ionization: Double?
    let electronAffinity: Double?
    let electronegativity: Double?
    let radiusCovalent: Double?
    let radiusVDW: Double?
    let boilingPoint: Double?
    let meltingPoint: Double?
    let block: String?
    let period: Int?
    let group: Int?
    let family: String?
    let configuration: String?
    let nameOrigin: String?
    let discoveryDate: String?
    let discoverers: [String]
    let discoveryCountry: [String]
    let oxidation: [Int]
    let color: [Double]

    var id: Int { z }
    var discoveryYear: Double? { discoveryDate.flatMap { Double($0) } }

    /// (row, column) in the standard 18-column layout; f-block sits in rows 8 and 9.
    var gridPosition: (row: Int, col: Int) {
        switch z {
        case 1: return (0, 0)
        case 2: return (0, 17)
        case 3...4: return (1, z - 3)
        case 5...10: return (1, z - 5 + 12)
        case 11...12: return (2, z - 11)
        case 13...18: return (2, z - 13 + 12)
        case 19...36: return (3, z - 19)
        case 37...54: return (4, z - 37)
        case 55...56: return (5, z - 55)
        case 57...71: return (8, z - 57 + 2)
        case 72...86: return (5, z - 72 + 3)
        case 87...88: return (6, z - 87)
        case 89...103: return (9, z - 89 + 2)
        default: return (6, z - 104 + 3)
        }
    }

    /// Modern IUPAC group, 1–18 (the data file uses the older 1–8 numbering). nil for the f-block rows.
    var iupacGroup: Int? {
        let p = gridPosition
        return p.row < 8 ? p.col + 1 : nil
    }

    func state(atKelvin t: Double) -> MatterState {
        // Arsenic and berkelium are listed with a melting point above their boiling point: they sublime at
        // ordinary pressure, so they are solid below the "boiling" point and gas above it.
        if let m = meltingPoint, let b = boilingPoint, m > b { return t < b ? .solid : .gas }
        guard let melt = meltingPoint else { return .unknown }
        if t < melt { return .solid }
        guard let boil = boilingPoint else { return .unknown }
        return t < boil ? .liquid : .gas
    }
}

enum MatterState: String {
    case solid = "Solid", liquid = "Liquid", gas = "Gas", unknown = "Unknown"

    var color: Color {
        switch self {
        case .solid: return Color(red: 0.35, green: 0.45, blue: 0.75)
        case .liquid: return Color(red: 0.25, green: 0.65, blue: 0.85)
        case .gas: return Color(red: 0.85, green: 0.45, blue: 0.40)
        case .unknown: return Color.gray.opacity(0.35)
        }
    }
}

enum Family: String, CaseIterable {
    case alkali = "Alkali_Earth"
    case alkalineEarth = "Alkaline_Earth"
    case transition = "Transition"
    case otherMetal = "Other_Metal"
    case metalloid = "Metalloids"
    case nonMetal = "Non-Metal"
    case halogen = "Halogen"
    case nobleGas = "Noblegas"
    case rareEarth = "Rare_Earth"

    var label: String {
        switch self {
        case .alkali: return "Alkali metals"
        case .alkalineEarth: return "Alkaline earth metals"
        case .transition: return "Transition metals"
        case .otherMetal: return "Other metals"
        case .metalloid: return "Metalloids"
        case .nonMetal: return "Nonmetals"
        case .halogen: return "Halogens"
        case .nobleGas: return "Noble gases"
        case .rareEarth: return "Lanthanides & actinides"
        }
    }

    var color: Color {
        switch self {
        case .alkali: return Color(red: 0.90, green: 0.45, blue: 0.40)
        case .alkalineEarth: return Color(red: 0.93, green: 0.65, blue: 0.35)
        case .transition: return Color(red: 0.45, green: 0.62, blue: 0.85)
        case .otherMetal: return Color(red: 0.55, green: 0.75, blue: 0.70)
        case .metalloid: return Color(red: 0.70, green: 0.75, blue: 0.40)
        case .nonMetal: return Color(red: 0.55, green: 0.80, blue: 0.50)
        case .halogen: return Color(red: 0.35, green: 0.75, blue: 0.80)
        case .nobleGas: return Color(red: 0.70, green: 0.55, blue: 0.85)
        case .rareEarth: return Color(red: 0.85, green: 0.60, blue: 0.75)
        }
    }
}

extension Element {
    var familyKind: Family? { family.flatMap(Family.init(rawValue:)) }
}

enum ElementStore {
    static let all: [Element] = {
        guard let url = Bundle.module.url(forResource: "elements", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Element].self, from: data)
        else { return [] }
        return list
    }()
}
