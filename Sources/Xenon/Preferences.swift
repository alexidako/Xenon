import SwiftUI

/// Display units. Data is always stored in K, eV and Å; these only change how it is shown.
enum TemperatureUnit: String, CaseIterable, Identifiable {
    case kelvin = "K", celsius = "°C", fahrenheit = "°F"
    var id: String { rawValue }
    func fromKelvin(_ k: Double) -> Double {
        switch self { case .kelvin: return k; case .celsius: return k - 273.15; case .fahrenheit: return (k - 273.15) * 9 / 5 + 32 }
    }
    func toKelvin(_ v: Double) -> Double {
        switch self { case .kelvin: return v; case .celsius: return v + 273.15; case .fahrenheit: return (v - 32) * 5 / 9 + 273.15 }
    }
}

enum EnergyUnit: String, CaseIterable, Identifiable {
    case eV = "eV", kJ = "kJ/mol", kcal = "kcal/mol"
    var id: String { rawValue }
    private static let evToKJ = 96.485332, evToKcal = 23.060549
    func fromEV(_ e: Double) -> Double {
        switch self { case .eV: return e; case .kJ: return e * Self.evToKJ; case .kcal: return e * Self.evToKcal }
    }
}

enum LengthUnit: String, CaseIterable, Identifiable {
    case angstrom = "Å", picometer = "pm", nanometer = "nm"
    var id: String { rawValue }
    func fromAngstrom(_ a: Double) -> Double {
        switch self { case .angstrom: return a; case .picometer: return a * 100; case .nanometer: return a / 10 }
    }
}

final class Preferences: ObservableObject {
    static let shared = Preferences()
    private let defaults: UserDefaults

    @Published var temperature: TemperatureUnit { didSet { defaults.set(temperature.rawValue, forKey: "unit.temperature") } }
    @Published var energy: EnergyUnit { didSet { defaults.set(energy.rawValue, forKey: "unit.energy") } }
    @Published var length: LengthUnit { didSet { defaults.set(length.rawValue, forKey: "unit.length") } }

    init(defaults: UserDefaults? = nil) {
        // Visual tests must not depend on (or change) the user's real settings.
        let d = defaults ?? (VRT.isActive ? UserDefaults(suiteName: "xenon.vrt.prefs")! : .standard)
        self.defaults = d
        temperature = TemperatureUnit(rawValue: d.string(forKey: "unit.temperature") ?? "") ?? .kelvin
        energy = EnergyUnit(rawValue: d.string(forKey: "unit.energy") ?? "") ?? .eV
        length = LengthUnit(rawValue: d.string(forKey: "unit.length") ?? "") ?? .angstrom
    }

    func resetToDefaults() { temperature = .kelvin; energy = .eV; length = .angstrom }

    /// Shows a stored value (K, eV or Å) in the user's unit, e.g. "1,538 °C".
    func temperatureText(_ kelvin: Double?) -> String { text(kelvin.map(temperature.fromKelvin), temperature.rawValue) }
    func energyText(_ ev: Double?) -> String { text(ev.map(energy.fromEV), energy.rawValue) }
    func lengthText(_ angstrom: Double?) -> String { text(angstrom.map(length.fromAngstrom), length.rawValue) }

    private func text(_ v: Double?, _ unit: String) -> String {
        guard let v else { return "—" }
        return v.formatted(.number.precision(.significantDigits(1...6))) + " " + unit
    }

    /// (value, unit) for an overlay's quantity, for legends.
    func display(_ overlay: Overlay, _ v: Double) -> String {
        switch overlay {
        case .meltingPoint, .boilingPoint: return formatNumber(temperature.fromKelvin(v)) + " " + temperature.rawValue
        case .ionization, .electronAffinity: return formatNumber(energy.fromEV(v)) + " " + energy.rawValue
        case .covalent, .vdw: return formatNumber(length.fromAngstrom(v)) + " " + length.rawValue
        default: return formatNumber(v) + (overlay.unit.isEmpty ? "" : " " + overlay.unit)
        }
    }
}

struct SettingsView: View {
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        Form {
            Section("Units") {
                Picker("Temperature", selection: $prefs.temperature) { ForEach(TemperatureUnit.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Energy (ionization, electron affinity)", selection: $prefs.energy) { ForEach(EnergyUnit.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Length (atomic radii)", selection: $prefs.length) { ForEach(LengthUnit.allCases) { Text($0.rawValue).tag($0) } }
                Text("These change how values are shown in the element details and the table legend. Calculators have their own unit menus.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Preview: Iron") {
                let fe = ElementStore.all[25]
                LabeledContent("Melting point") { Text(prefs.temperatureText(fe.meltingPoint)) }
                LabeledContent("First ionization energy") { Text(prefs.energyText(fe.ionization)) }
                LabeledContent("Covalent radius") { Text(prefs.lengthText(fe.radiusCovalent)) }
            }
            Section { Button("Restore defaults") { prefs.resetToDefaults() } }
            Section("About") {
                LabeledContent("Xenon") { Text("Version \(AppInfo.version)") }
                LabeledContent("Built by") { Text(AppInfo.author).textSelection(.enabled) }
                LabeledContent("Made with") { Text(AppInfo.builtWith.replacingOccurrences(of: "Developed with ", with: "").replacingOccurrences(of: ".", with: "")) }
                Text("Element, isotope and spectrum data from the Blue Obelisk project (MIT). Glossary, lab equipment, hazard symbols, molecules, icons and the original application: KDE Kalzium (GPL-2.0-or-later).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 360)
        .navigationTitle("Settings")
    }
}

@MainActor enum PreferencesSelfTest {
    static func run() {
        let d = UserDefaults(suiteName: "xenon.test.prefs")!
        d.removePersistentDomain(forName: "xenon.test.prefs")
        let p = Preferences(defaults: d)
        SelfTest.check(p.temperature == .kelvin && p.energy == .eV && p.length == .angstrom, "settings: defaults are K, eV, Å")
        let fe = ElementStore.all[25]
        p.temperature = .celsius
        let melt = p.temperatureText(fe.meltingPoint)
        SelfTest.check(melt.hasSuffix("°C") && (melt.hasPrefix("1,53") || melt.hasPrefix("1,54")), "settings: iron melts at about 1538 °C", melt)
        SelfTest.check(abs(TemperatureUnit.celsius.fromKelvin(273.15)) < 1e-9 && abs(TemperatureUnit.fahrenheit.fromKelvin(373.15) - 212) < 1e-9 && abs(TemperatureUnit.fahrenheit.fromKelvin(255.372) - 0) < 0.01,
                       "settings: 273.15 K = 0 °C, 373.15 K = 212 °F, 255.37 K = 0 °F")
        for t in TemperatureUnit.allCases { for v in [0.0, 100, 1234.5] { if abs(t.toKelvin(t.fromKelvin(v)) - v) > 1e-9 { SelfTest.check(false, "settings: temperature round trip \(t.rawValue)") } } }
        SelfTest.check(abs(EnergyUnit.kJ.fromEV(1) - 96.485) < 0.001 && abs(EnergyUnit.kcal.fromEV(1) - 23.0605) < 0.001, "settings: 1 eV = 96.485 kJ/mol = 23.06 kcal/mol")
        SelfTest.check(LengthUnit.picometer.fromAngstrom(1.2) == 120 && abs(LengthUnit.nanometer.fromAngstrom(10) - 1) < 1e-12, "settings: 1.2 Å = 120 pm; 10 Å = 1 nm")
        p.energy = .kJ; p.length = .picometer
        let q = Preferences(defaults: d)
        SelfTest.check(q.temperature == .celsius && q.energy == .kJ && q.length == .picometer, "settings: choices survive a restart")
        SelfTest.check(q.temperatureText(nil) == "—" && q.energyText(nil) == "—", "settings: missing data shows a dash in every unit")
        let h = ElementStore.all[0]
        SelfTest.check(q.energyText(h.ionization).contains("kJ/mol") && q.energyText(h.ionization).hasPrefix("1,31"), "settings: hydrogen ionization is about 1312 kJ/mol", q.energyText(h.ionization))
        p.resetToDefaults()
        SelfTest.check(Preferences(defaults: d).energy == .eV, "settings: restore defaults is saved")
        SelfTest.check(!AppInfo.author.isEmpty && !AppInfo.version.isEmpty, "about: the author and version are filled in")
        d.removePersistentDomain(forName: "xenon.test.prefs")
    }
}
