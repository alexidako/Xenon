import SwiftUI
import AppKit

/// Visual regression testing. `Xenon --vrt <dir>` opens every screen in a fixed state at a fixed window
/// size, saves a PNG of the window for each, and quits. `--vrt-compare` then diffs two such folders.
enum VRT {
    static let size = NSSize(width: 1400, height: 880)

    struct Scenario {
        let name: String
        let env: [String: String]
        init(_ name: String, _ env: [String: String] = [:]) { self.name = name; self.env = env }
    }

    static let scenarios: [Scenario] = [
        // periodic table: color modes
        Scenario("table-family"),
        Scenario("table-blocks", ["XENON_OVERLAY": "Blocks"]),
        Scenario("table-groups", ["XENON_OVERLAY": "Groups"]),
        Scenario("table-colors", ["XENON_OVERLAY": "Colors"]),
        Scenario("table-iconic-cas", ["XENON_OVERLAY": "Iconic", "XENON_NUMERATION": "CAS"]),
        Scenario("table-electronegativity-iupac", ["XENON_OVERLAY": "Electronegativity (Pauling)", "XENON_NUMERATION": "IUPAC"]),
        Scenario("table-state", ["XENON_OVERLAY": "State of matter"]),
        Scenario("table-discovery", ["XENON_OVERLAY": "Discovery date"]),
        Scenario("table-ask-liquid", ["XENON_QUERY": "liquid at room temperature"]),
        Scenario("table-ask-halogens", ["XENON_QUERY": "halogens discovered before 1850"]),
        Scenario("table-ask-unsupported", ["XENON_QUERY": "density of lead"]),
        // element detail tabs
        Scenario("detail-overview", ["XENON_START": "26"]),
        Scenario("detail-atom", ["XENON_START": "26:atom"]),
        Scenario("detail-isotopes", ["XENON_START": "6:isotopes"]),
        Scenario("detail-spectrum", ["XENON_START": "1:spectrum"]),
        Scenario("detail-misc", ["XENON_START": "79:misc"]),
        Scenario("detail-links", ["XENON_START": "8:links"]),
        // reference
        Scenario("glossary", ["XENON_SECTION": "Glossary", "XENON_ITEM": "isotope"]),
        Scenario("glossary-magnetic-moment", ["XENON_SECTION": "Glossary", "XENON_ITEM": "magnetic moment"]),
        Scenario("glossary-decay-mode", ["XENON_SECTION": "Glossary", "XENON_ITEM": "decay mode"]),
        Scenario("risk-safety", ["XENON_SECTION": "Risk & Safety", "XENON_R": "11-23", "XENON_S": "2-16"]),
        Scenario("reference-tables", ["XENON_SECTION": "Reference Tables"]),
        Scenario("equipment", ["XENON_SECTION": "Lab Equipment", "XENON_ITEM": "beaker"]),
        // visual tools
        Scenario("editor-empty", ["XENON_SECTION": "Molecule Editor"]),
        Scenario("editor-ethanol", ["XENON_SECTION": "Molecule Editor", "XENON_EDITOR": "Ethanol"]),
        Scenario("editor-benzene", ["XENON_SECTION": "Molecule Editor", "XENON_EDITOR": "Benzene"]),
        Scenario("molecules-ball-stick", ["XENON_SECTION": "Molecules", "XENON_MOL": "porphyrin"]),
        Scenario("molecules-space-filling", ["XENON_SECTION": "Molecules", "XENON_MOL": "ethanol", "XENON_MOL_STYLE": "Space filling"]),
        Scenario("vbt-molecule-ethanol", ["XENON_SECTION": "Valence Bond Theory", "XENON_MOL": "ethanol"]),
        Scenario("vbt-molecule-co2", ["XENON_SECTION": "Valence Bond Theory", "XENON_MOL": "carbon dioxide"]),
        Scenario("vbt-resonance-nitrate", ["XENON_SECTION": "Valence Bond Theory", "XENON_VBT_MODE": "Resonance", "XENON_RESONANCE": "Nitrate"]),
        Scenario("vbt-resonance-benzene", ["XENON_SECTION": "Valence Bond Theory", "XENON_VBT_MODE": "Resonance", "XENON_RESONANCE": "Benzene"]),
        Scenario("vbt-resonance-co", ["XENON_SECTION": "Valence Bond Theory", "XENON_VBT_MODE": "Resonance", "XENON_RESONANCE": "Carbon monoxide"]),
        Scenario("vbt-molecule-co", ["XENON_SECTION": "Valence Bond Theory", "XENON_MOL": "carbon monoxide"]),
        Scenario("vbt-predict-sf6", ["XENON_SECTION": "Valence Bond Theory", "XENON_VBT_MODE": "Predict", "XENON_VBT_ELEMENT": "S", "XENON_VBT_SIGMA": "6"]),
        Scenario("vbt-predict-ethene", ["XENON_SECTION": "Valence Bond Theory", "XENON_VBT_MODE": "Predict", "XENON_VBT_ELEMENT": "C", "XENON_VBT_SIGMA": "3", "XENON_VBT_PI": "1"]),
        Scenario("filling-empty", ["XENON_SECTION": "Electron Filling", "XENON_FILL_Z": "8"]),
        Scenario("filling-oxygen-half", ["XENON_SECTION": "Electron Filling", "XENON_FILL_Z": "8", "XENON_FILL_PLACED": "6"]),
        Scenario("filling-oxygen-done", ["XENON_SECTION": "Electron Filling", "XENON_FILL_Z": "8", "XENON_FILL_PLACED": "8"]),
        Scenario("filling-refused", ["XENON_SECTION": "Electron Filling", "XENON_FILL_Z": "8", "XENON_FILL_TRY": "2s"]),
        Scenario("filling-chromium-strict", ["XENON_SECTION": "Electron Filling", "XENON_FILL_Z": "24", "XENON_FILL_PLACED": "24"]),
        Scenario("settings", ["XENON_SECTION": "Settings"]),
        Scenario("quiz-setup", ["XENON_SECTION": "Quiz"]),
        Scenario("quiz-question", ["XENON_SECTION": "Quiz", "XENON_QUIZ_PHASE": "question", "XENON_QUIZ_SEED": "5", "XENON_QUIZ_KIND": "Symbol → name"]),
        Scenario("quiz-correct", ["XENON_SECTION": "Quiz", "XENON_QUIZ_PHASE": "answered", "XENON_QUIZ_SEED": "5", "XENON_QUIZ_KIND": "Periodic trends"]),
        Scenario("quiz-wrong", ["XENON_SECTION": "Quiz", "XENON_QUIZ_PHASE": "wrong", "XENON_QUIZ_SEED": "9", "XENON_QUIZ_KIND": "Electron configurations"]),
        Scenario("quiz-table", ["XENON_SECTION": "Quiz", "XENON_QUIZ_PHASE": "wrong", "XENON_QUIZ_SEED": "3", "XENON_QUIZ_KIND": "Find it on the table"]),
        Scenario("quiz-results", ["XENON_SECTION": "Quiz", "XENON_QUIZ_PHASE": "results", "XENON_QUIZ_SEED": "2", "XENON_QUIZ_KIND": "Element families"]),
        Scenario("orbital-pz", ["XENON_SECTION": "Orbitals", "XENON_ORBITAL": "pz"]),
        Scenario("orbital-dz2", ["XENON_SECTION": "Orbitals", "XENON_ORBITAL": "dz2"]),
        Scenario("orbital-dxy", ["XENON_SECTION": "Orbitals", "XENON_ORBITAL": "dxy"]),
        Scenario("orbital-hybrid-sp3", ["XENON_SECTION": "Orbitals", "XENON_ORBITAL_MODE": "Hybrid", "XENON_HYBRID": "sp3"]),
        Scenario("orbital-hybrid-sp2", ["XENON_SECTION": "Orbitals", "XENON_ORBITAL_MODE": "Hybrid", "XENON_HYBRID": "sp2"]),
        Scenario("orbital-hybrid-sp3d2", ["XENON_SECTION": "Orbitals", "XENON_ORBITAL_MODE": "Hybrid", "XENON_HYBRID": "sp3d2"]),
        Scenario("orbital-sigma-bonding", ["XENON_SECTION": "Orbitals", "XENON_ORBITAL_MODE": "Bonding", "XENON_INTERACTION": "σ  p + p (end-on)"]),
        Scenario("orbital-sigma-anti", ["XENON_SECTION": "Orbitals", "XENON_ORBITAL_MODE": "Bonding", "XENON_INTERACTION": "σ  p + p (end-on)", "XENON_ANTI": "1"]),
        Scenario("orbital-pi-bonding", ["XENON_SECTION": "Orbitals", "XENON_ORBITAL_MODE": "Bonding", "XENON_INTERACTION": "π  p + p (side-on)"]),
        Scenario("orbital-ss-far", ["XENON_SECTION": "Orbitals", "XENON_ORBITAL_MODE": "Bonding", "XENON_INTERACTION": "σ  s + s", "XENON_DISTANCE": "3.6"]),
        Scenario("molecule-orbitals-water", ["XENON_SECTION": "Molecules", "XENON_MOL": "water", "XENON_ORBITALS": "σ, lone pairs & π"]),
        Scenario("molecule-orbitals-co2", ["XENON_SECTION": "Molecules", "XENON_MOL": "carbon dioxide", "XENON_ORBITALS": "σ, lone pairs & π"]),
        Scenario("molecule-orbitals-ethanol-oxygen-only", ["XENON_SECTION": "Molecules", "XENON_MOL": "ethanol", "XENON_ORBITALS": "σ, lone pairs & π", "XENON_ORBITAL_ATOMS": "O1"]),
        Scenario("molecule-orbitals-ethanol", ["XENON_SECTION": "Molecules", "XENON_MOL": "ethanol", "XENON_ORBITALS": "σ bonds & lone pairs"]),
        Scenario("isotope-chart-decay", ["XENON_SECTION": "Isotope Chart"]),
        Scenario("isotope-chart-halflife", ["XENON_SECTION": "Isotope Chart", "XENON_ISO_MODE": "Half-life"]),
        Scenario("isotope-chart-abundance", ["XENON_SECTION": "Isotope Chart", "XENON_ISO_MODE": "Natural abundance"]),
        Scenario("plot", ["XENON_SECTION": "Plot Data"]),
        // calculators and solvers
        Scenario("calc-molmass", ["XENON_SECTION": "Calculators"]),
        Scenario("calc-gas", ["XENON_SECTION": "Calculators", "XENON_CALC": "Gas"]),
        Scenario("calc-concentration", ["XENON_SECTION": "Calculators", "XENON_CALC": "Concentration"]),
        Scenario("calc-nuclear", ["XENON_SECTION": "Calculators", "XENON_CALC": "Nuclear decay"]),
        Scenario("calc-titration", ["XENON_SECTION": "Calculators", "XENON_CALC": "Titration", "XENON_EXAMPLE": "1"]),
        Scenario("solver-balance", ["XENON_SECTION": "Equation Solver"]),
        Scenario("solver-stoichiometry", ["XENON_SECTION": "Equation Solver", "XENON_EQ_MODE": "Stoichiometry", "XENON_STOICH": "10,30"]),
        Scenario("spectrum-matcher", ["XENON_SECTION": "Spectrum Matcher"]),
        Scenario("export", ["XENON_SECTION": "Export Data"]),
    ]

    static var isActive: Bool { CommandLine.arguments.contains("--vrt") }

    static func argument(after flag: String) -> String? {
        guard let i = CommandLine.arguments.firstIndex(of: flag), i + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[i + 1]
    }

    private static let envKeys: [String] = Array(Set(scenarios.flatMap { $0.env.keys })) + ["XENON_SECTION"]

    @MainActor static func run(bump: @escaping () -> Void) async {
        let dir = argument(after: "--vrt") ?? "vrt/current"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let only = argument(after: "--only")

        try? await Task.sleep(nanoseconds: 1_200_000_000)
        guard let window = NSApp.windows.first(where: { $0.isVisible }) ?? NSApp.windows.first else { print("VRT: no window"); exit(2) }
        NSApp.appearance = NSAppearance(named: .darkAqua)       // same look on every machine/setting
        window.setContentSize(size)
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // The sidebar is translucent and shows whatever is behind the window, which would make screenshots depend on the
        // user's desktop. A solid backdrop directly behind the window (and hidden by it) removes that dependency.
        let backdrop = NSWindow(contentRect: window.frame.insetBy(dx: -30, dy: -30), styleMask: [.borderless], backing: .buffered, defer: false)
        backdrop.backgroundColor = NSColor(white: 0.12, alpha: 1)
        backdrop.isOpaque = true; backdrop.hasShadow = false; backdrop.ignoresMouseEvents = true
        backdrop.order(.below, relativeTo: window.windowNumber)
        defer { backdrop.orderOut(nil) }

        var failures = 0
        for s in scenarios where only == nil || s.name.contains(only!) {
            for k in envKeys { unsetenv(k) }
            for (k, v) in s.env { setenv(k, v, 1) }
            bump()                                              // rebuild the UI so it reads the new settings
            try? await Task.sleep(nanoseconds: 1_600_000_000)   // let SwiftUI, Charts and SceneKit finish drawing
            // An inactive window is drawn dimmer, so make sure it is the active one (the user may have switched apps).
            for _ in 0..<10 where !window.isKeyWindow || !NSApp.isActive {
                NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            if capture(window, to: "\(dir)/\(s.name).png") { print("captured \(s.name)") } else { print("FAILED  \(s.name)"); failures += 1 }
        }
        exit(failures == 0 ? 0 : 1)
    }

    /// Uses the system tool because direct window capture APIs are unavailable on recent macOS.
    private static func capture(_ window: NSWindow, to path: String) -> Bool {
        try? FileManager.default.removeItem(atPath: path)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
        do { try p.run(); p.waitUntilExit() } catch { return false }
        return FileManager.default.fileExists(atPath: path)
    }
}
