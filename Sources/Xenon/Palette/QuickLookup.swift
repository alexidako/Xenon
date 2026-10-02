import SwiftUI

/// What ⌘K can jump to.
struct PaletteItem: Identifiable, Hashable {
    enum Target: Hashable {
        case screen(Screen)
        case element(Int)
        case glossary(String)
        case equipment(String)
        case molecule(UUID)
    }
    let title: String
    let subtitle: String
    let icon: String
    let target: Target
    let score: Int
    var id: String { "\(target)" }
}

enum QuickLookup {
    /// 0 = no match; higher is better.
    static func score(_ text: String, _ q: String) -> Int {
        let t = text.lowercased()
        if t == q { return 100 }
        if t.hasPrefix(q) { return 80 }
        if t.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { $0.hasPrefix(q) }) { return 60 }
        if t.contains(q) { return 40 }
        return 0
    }

    private static let screenAliases: [Screen: [String]] = [
        .table: ["periodic table", "elements", "table"], .glossary: ["glossary", "terms", "definitions"],
        .rs: ["risk", "safety", "r/s phrases", "hazard"], .tables: ["greek", "roman numerals", "prefixes", "reference tables"],
        .equipment: ["lab equipment", "tools", "glassware"], .editor: ["molecule editor", "draw", "sketch"],
        .molecules: ["molecules", "3d", "viewer"], .orbitals: ["orbitals", "orbital", "s p d", "hybrid"],
        .filling: ["electron filling", "aufbau", "hund", "pauli", "configuration"], .quiz: ["quiz", "test", "flashcards", "practice"],
        .vbt: ["valence bond theory", "vbt", "hybridization", "resonance", "formal charge"], .isotopes: ["isotope chart", "nuclides", "decay"],
        .plot: ["plot data", "graph", "trends"], .calculators: ["calculators", "gas law", "molar mass", "concentration", "titration", "nuclear decay", "half-life"],
        .solver: ["equation solver", "balance equation", "stoichiometry", "limiting reagent"], .matcher: ["spectrum matcher", "spectra", "emission lines"],
        .export: ["export data", "csv", "html", "xml"], .settings: ["settings", "units", "preferences", "celsius", "kelvin"],
    ]

    static func search(_ raw: String, limit: Int = 14) -> [PaletteItem] {
        let q = raw.trimmingCharacters(in: .whitespaces).lowercased()
        var out: [PaletteItem] = []

        for s in Screen.allCases {
            let best = ([s.rawValue, tr(s.rawValue)] + (screenAliases[s] ?? [])).map { q.isEmpty ? 30 : score($0, q) }.max() ?? 0
            if best > 0 { out.append(PaletteItem(title: s.rawValue, subtitle: "Go to screen", icon: s.icon, target: .screen(s), score: q.isEmpty ? 30 : best + 5)) }
        }
        guard !q.isEmpty else { return Array(out.prefix(limit)) }

        for e in ElementStore.all {
            var best = max(score(e.name, q), score(tr(e.name), q), score(e.symbol, q) == 100 ? 95 : 0)
            if String(e.z) == q { best = max(best, 95) }
            if best > 0 { out.append(PaletteItem(title: "\(tr(e.name)) (\(e.symbol))", subtitle: tr("Element {z}", ["z": e.z]), icon: "square.grid.3x3", target: .element(e.z), score: best + 10)) }
        }
        for g in ReferenceStore.data?.glossary ?? [] {
            let best = max(score(g.name, q), score(tr(g.name), q))
            if best > 0 { out.append(PaletteItem(title: tr(g.name), subtitle: tr("Glossary"), icon: "book", target: .glossary(g.name), score: best)) }
        }
        for t in ReferenceStore.data?.tools ?? [] {
            let best = max(score(t.name, q), score(tr(t.name), q))
            if best > 0 { out.append(PaletteItem(title: tr(t.name), subtitle: tr("Lab equipment"), icon: "flask", target: .equipment(t.name), score: best - 5)) }
        }
        for m in MoleculeLibrary.bundled {
            let best = max(score(m.name, q), score(tr(m.name), q), score(m.formula, q))
            if best > 0 { out.append(PaletteItem(title: tr(m.name), subtitle: "\(tr("Molecule")) · \(Markup.formulaText(m.formula))", icon: "atom", target: .molecule(m.id), score: best - 5)) }
        }
        return Array(out.sorted { ($0.score, $1.title) > ($1.score, $0.title) }.prefix(limit))
    }
}

/// Where the palette sends the app.
final class Jump: ObservableObject {
    static let shared = Jump()
    @Published var element: Int?
    @Published var glossary: String?
    @Published var equipment: String?
    @Published var paletteOpen = false

    func go(_ item: PaletteItem) {
        switch item.target {
        case .screen(let s): Navigation.shared.target = s
        case .element(let z): element = z; Navigation.shared.target = .table
        case .glossary(let n): glossary = n; Navigation.shared.target = .glossary
        case .equipment(let n): equipment = n; Navigation.shared.target = .equipment
        case .molecule(let id): UserMolecules.shared.focus = id; Navigation.shared.target = .molecules
        }
        paletteOpen = false
    }
}

struct PaletteView: View {
    @ObservedObject private var jump = Jump.shared
    @State private var query = ProcessInfo.processInfo.environment["XENON_PALETTE"] ?? ""
    @State private var index = 0
    @FocusState private var focused: Bool

    private var results: [PaletteItem] { QuickLookup.search(query) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Jump to a screen, element, term or molecule", text: $query)
                    .textFieldStyle(.plain).font(.title3).focused($focused)
                    .onSubmit { choose() }
                    .onChange(of: query) { _, _ in index = 0 }
            }.padding(14)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { i, item in
                            HStack(spacing: 10) {
                                Image(systemName: item.icon).frame(width: 22).foregroundStyle(.secondary)
                                Text(item.title)
                                Spacer()
                                Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(i == index ? Color.accentColor.opacity(0.85) : .clear, in: RoundedRectangle(cornerRadius: 7))
                            .foregroundStyle(i == index ? Color.white : Color.primary)
                            .contentShape(Rectangle())
                            .onTapGesture { index = i; choose() }
                            .id(i)
                        }
                        if results.isEmpty { Text(tr("Nothing found for “{q}”", ["q": query])).foregroundStyle(.secondary).padding(20) }
                    }.padding(8)
                }
                .onChange(of: index) { _, i in proxy.scrollTo(i) }
            }
            .frame(height: 340)
        }
        .frame(width: 560)
        .onAppear { focused = true }
        .onKeyPress(.downArrow) { index = min(index + 1, max(0, results.count - 1)); return .handled }
        .onKeyPress(.upArrow) { index = max(index - 1, 0); return .handled }
        .onKeyPress(.escape) { jump.paletteOpen = false; return .handled }
    }

    private func choose() {
        guard results.indices.contains(index) else { return }
        jump.go(results[index])
    }
}

@MainActor enum PaletteSelfTest {
    static func run() {
        func top(_ q: String) -> PaletteItem.Target? { QuickLookup.search(q).first?.target }
        let w = ElementStore.all.first { $0.symbol == "W" }!, fe = ElementStore.all.first { $0.symbol == "Fe" }!
        SelfTest.check(top("tungsten") == .element(w.z), "⌘K: 'tungsten' jumps to tungsten", "\(String(describing: top("tungsten")))")
        SelfTest.check(top("fe") == .element(fe.z), "⌘K: the symbol 'Fe' finds iron before anything else", "\(String(describing: top("fe")))")
        SelfTest.check(top("26") == .element(26), "⌘K: an atomic number finds its element")
        SelfTest.check(top("gas law") == .screen(.calculators), "⌘K: 'gas law' opens the calculators", "\(String(describing: top("gas law")))")
        SelfTest.check(top("aufbau") == .screen(.filling) && top("balance equation") == .screen(.solver), "⌘K: topic words find their screens")
        SelfTest.check(top("celsius") == .screen(.settings), "⌘K: 'celsius' leads to the settings")
        SelfTest.check(QuickLookup.search("magnetic").contains { $0.target == .glossary("Magnetic Moment") }, "⌘K: glossary terms are searchable")
        SelfTest.check(QuickLookup.search("beaker").contains { $0.target == .equipment("Beaker") }, "⌘K: lab equipment is searchable")
        SelfTest.check(QuickLookup.search("c2h6o").contains { if case .molecule = $0.target { return true }; return false }, "⌘K: molecules are found by formula")
        SelfTest.check(QuickLookup.search("zzzzqq").isEmpty, "⌘K: nonsense finds nothing")
        SelfTest.check(QuickLookup.search("").count >= 10 && QuickLookup.search("   ").count >= 10, "⌘K: an empty box lists the screens")
        let items = QuickLookup.search("o")
        SelfTest.check(Set(items.map(\.id)).count == items.count && items.count <= 14, "⌘K: results are unique and limited to 14", "\(items.count)")
        var crashed = false
        for q in ["(", "[", "\\", "%%", "💥", String(repeating: "a", count: 500), "a b c", "-1", "9999"] { _ = QuickLookup.search(q); crashed = crashed || false }
        SelfTest.check(!crashed, "⌘K: odd input does not crash")
    }
}
