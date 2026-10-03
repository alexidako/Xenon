import SwiftUI

@main
struct XenonApp: App {
    init() {
        if CommandLine.arguments.contains("--selftest") { SelfTest.run() }
        if let i = CommandLine.arguments.firstIndex(of: "--geometry"), i + 1 < CommandLine.arguments.count { MainActor.assumeIsolated { SelfTest.geometry(CommandLine.arguments[i + 1]) } }
        if let i = CommandLine.arguments.firstIndex(of: "--vrt-compare"), i + 3 < CommandLine.arguments.count {
            exit(VRTCompare.run(baseline: CommandLine.arguments[i + 1], current: CommandLine.arguments[i + 2], diffDir: CommandLine.arguments[i + 3]))
        }
        if let i = CommandLine.arguments.firstIndex(of: "--query"), i + 1 < CommandLine.arguments.count { SelfTest.query(CommandLine.arguments[i + 1]) }
        // Needed when launched via `swift run` (no app bundle).
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("Xenon") {
            AppRoot()
        }
        .defaultSize(width: 1380, height: 820)
        .commands {
            CommandGroup(replacing: .appInfo) { Button("About Xenon") { AboutPanel.show() } }
            CommandGroup(after: .textEditing) { Button("Quick Lookup…") { Jump.shared.paletteOpen = true }.keyboardShortcut("k", modifiers: .command) }
            CommandMenu("Go") {
                ForEach(Array(Screen.shortcutOrder.enumerated()), id: \.element) { i, s in
                    Button(tr(s.rawValue)) { Navigation.shared.target = s }.keyboardShortcut(KeyEquivalent(Character(String(i + 1 == 10 ? 0 : i + 1))), modifiers: .command)
                }
            }
            CommandGroup(replacing: .help) {
                Button("Quick Lookup (⌘K)") { Jump.shared.paletteOpen = true }
                Link("Original Kalzium", destination: URL(string: "https://apps.kde.org/kalzium/")!)
            }
        }
        Settings { SettingsView() }
    }
}

enum Screen: String, CaseIterable, Identifiable {
    case table = "Periodic Table"
    case glossary = "Glossary"
    case rs = "Risk & Safety"
    case tables = "Reference Tables"
    case equipment = "Lab Equipment"
    case editor = "Molecule Editor"
    case molecules = "Molecules"
    case orbitals = "Orbitals"
    case filling = "Electron Filling"
    case quiz = "Quiz"
    case vbt = "Valence Bond Theory"
    case isotopes = "Isotope Chart"
    case plot = "Plot Data"
    case calculators = "Calculators"
    case solver = "Equation Solver"
    case matcher = "Spectrum Matcher"
    case export = "Export Data"
    case settings = "Settings"

    var id: String { rawValue }

    /// Sidebar sections, in order.
    static let groups: [(title: String, items: [Screen])] = [
        ("Explore", [.table, .isotopes, .plot, .matcher]),
        ("Learn", [.quiz, .filling, .glossary]),
        ("Molecules & Bonding", [.editor, .molecules, .orbitals, .vbt]),
        ("Tools", [.calculators, .solver, .export]),
        ("Reference", [.rs, .tables, .equipment]),
    ]
    /// Order used for ⌘1 … ⌘0.
    static var shortcutOrder: [Screen] { groups.flatMap(\.items).prefix(10).map { $0 } }

    var icon: String {
        switch self {
        case .table: return "square.grid.3x3"
        case .glossary: return "book"
        case .rs: return "exclamationmark.triangle"
        case .tables: return "tablecells"
        case .equipment: return "flask"
        case .editor: return "pencil.and.scribble"
        case .molecules: return "atom"
        case .orbitals: return "circle.hexagongrid"
        case .filling: return "rectangle.split.3x1"
        case .quiz: return "questionmark.bubble"
        case .vbt: return "link"
        case .isotopes: return "circle.grid.cross"
        case .plot: return "chart.xyaxis.line"
        case .calculators: return "function"
        case .solver: return "equal.circle"
        case .matcher: return "waveform.path.ecg"
        case .export: return "square.and.arrow.up"
        case .settings: return "gearshape"
        }
    }
}

struct RootView: View {
    @ObservedObject private var nav = Navigation.shared
    @ObservedObject private var jump = Jump.shared
    @State private var section: Screen? = {
        if let s = Screen(rawValue: ProcessInfo.processInfo.environment["XENON_SECTION"] ?? "") { return s }
        if VRT.isActive { return .table }                       // tests always start from the same screen
        return Screen(rawValue: UserDefaults.standard.string(forKey: "lastScreen") ?? "") ?? .table
    }()

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                ForEach(Screen.groups, id: \.title) { group in
                    Section(tr(group.title)) {
                        ForEach(group.items) { s in Label(tr(s.rawValue), systemImage: s.icon).tag(s) }
                    }
                }
                Section { Label(tr(Screen.settings.rawValue), systemImage: Screen.settings.icon).tag(Screen.settings) }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 255, max: 300)
        } detail: {
            switch section ?? .table {
            case .table: TableScreen()
            case .glossary: GlossaryView()
            case .rs: RSPhrasesView()
            case .tables: TablesView()
            case .equipment: EquipmentView()
            case .editor: EditorView()
            case .molecules: MoleculeView()
            case .orbitals: OrbitalView()
            case .filling: ElectronFillingView()
            case .quiz: QuizView()
            case .vbt: VBTView()
            case .isotopes: IsotopeChartView()
            case .plot: PlotView()
            case .calculators: CalculatorsView()
            case .solver: EquationView()
            case .matcher: SpectrumMatcherView()
            case .export: ExportView()
            case .settings: SettingsView()
            }
        }
        .sheet(isPresented: $jump.paletteOpen) { PaletteView() }
        .onAppear { if ProcessInfo.processInfo.environment["XENON_PALETTE"] != nil { jump.paletteOpen = true } }
        .onChange(of: nav.target) { _, t in
            if let t { section = t; nav.target = nil }
        }
        .onChange(of: section) { _, s in if !VRT.isActive, let s { UserDefaults.standard.set(s.rawValue, forKey: "lastScreen") } }
    }
}

/// Hosts the real UI. In `--vrt` mode it is rebuilt for each test scenario.
struct AppRoot: View {
    @State private var token = 0

    var body: some View {
        RootView()
            .id(token)
            .frame(minWidth: 1020, minHeight: 640)
            .task { if VRT.isActive { await VRT.run { token += 1 } } }
    }
}

enum AboutPanel {
    static func show() {
        let credits = NSMutableAttributedString(string: """
        \(AppInfo.tagline)

        Built by \(AppInfo.author), \(AppInfo.year).
        \(AppInfo.builtWith)

        Element, isotope and spectrum data: Blue Obelisk project (MIT).
        Glossary, lab equipment, hazard symbols, molecules, icons and the original application: KDE Kalzium (GPL-2.0-or-later).

        Press ⌘K anywhere to jump to a screen, element or term.
        """, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor])
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: AppInfo.name, .applicationVersion: AppInfo.version, .version: "", .credits: credits])
        NSApp.activate(ignoringOtherApps: true)
    }
}
