import SwiftUI

// MARK: Glossary

struct GlossaryView: View {
    private let entries = ReferenceStore.data?.glossary ?? []
    @State private var selection: GlossaryEntry.ID? = {
        let all = ReferenceStore.data?.glossary ?? []
        let want = ProcessInfo.processInfo.environment["XENON_ITEM"]?.lowercased()
        return (all.first { want != nil && $0.name.lowercased().contains(want!) } ?? all.first)?.id
    }()
    @State private var query = ""
    @ObservedObject private var jump = Jump.shared

    private var filtered: [GlossaryEntry] {
        let q = query.lowercased()
        return q.isEmpty ? entries : entries.filter {
            $0.name.lowercased().contains(q) || tr($0.name).lowercased().contains(q) || Markup.plain($0.desc).lowercased().contains(q) || Markup.plain(tr($0.desc)).lowercased().contains(q)
        }
    }

    var body: some View {
        HSplitView {
            List(filtered, selection: $selection) { Text($0.name).tag($0.id) }
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)
            Group {
                if let e = entries.first(where: { $0.id == selection }) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(Markup.attributed(tr(e.name))).font(.largeTitle.bold())
                            Text(Markup.attributed(tr(e.desc))).font(.title3)
                            if !e.refs.isEmpty {
                                Text("See also").font(.headline).padding(.top, 8)
                                ForEach(e.refs, id: \.self) { ref in
                                    Button(tr(ref)) { selection = ref; query = "" }.buttonStyle(.link)
                                }
                            }
                        }
                        .padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Text("Select a term").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear { if let g = jump.glossary { selection = g; jump.glossary = nil } }
        .searchable(text: $query, prompt: "Search the glossary")
        .navigationTitle("Glossary")
    }
}

// MARK: R/S phrases

struct RSPhrasesView: View {
    private let data = ReferenceStore.data
    @State private var rText = ProcessInfo.processInfo.environment["XENON_R"] ?? ""
    @State private var sText = ProcessInfo.processInfo.environment["XENON_S"] ?? ""

    /// Parses "10-23-45" style input; returns nil when malformed.
    private func parse(_ s: String) -> [Int]? {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return [] }
        if t.hasPrefix("-") || t.hasSuffix("-") { return nil }
        let parts = t.split(separator: "-", omittingEmptySubsequences: false).map { Int($0.trimmingCharacters(in: .whitespaces)) }
        return parts.contains(nil) ? nil : parts.compactMap { $0 }
    }

    var body: some View {
        let r = parse(rText), s = parse(sText)
        VStack(alignment: .leading, spacing: 14) {
            Text("Enter phrase numbers separated by dashes, for example R 11-23-36 and S 2-16.")
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("R-phrases (risks)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    TextField("", text: $rText, prompt: Text("e.g. 11-23")).textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("S-phrases (safety)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    TextField("", text: $sText, prompt: Text("e.g. 2-16")).textFieldStyle(.roundedBorder)
                }
            }
            if r == nil || s == nil {
                Label("Invalid input: use numbers separated by single dashes.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    section("R-phrases (risks)", prefix: "R", numbers: r ?? [], table: data?.rphrases ?? [:])
                    section("S-phrases (safety)", prefix: "S", numbers: s ?? [], table: data?.sphrases ?? [:])
                    if (r ?? []).isEmpty && (s ?? []).isEmpty && r != nil && s != nil {
                        Text("You asked for no R/S-phrases.").foregroundStyle(.secondary)
                    }
                    hazardSymbols
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .navigationTitle("Risk & Safety Phrases")
    }

    /// A safety phrase in the current language (the translations are stored as "R11: Highly flammable").
    private func phrase(_ prefix: String, _ n: Int, _ text: String) -> String {
        let full = tr("\(prefix)\(n): \(text)")
        return full.replacingOccurrences(of: "^\(prefix)\(n):\\s*", with: "", options: .regularExpression)
    }

    @ViewBuilder private func section(_ title: String, prefix: String, numbers: [Int], table: [String: String]) -> some View {
        if !numbers.isEmpty {
            Text(title).font(.title2.bold())
            ForEach(Array(numbers.enumerated()), id: \.offset) { _, n in
                HStack(alignment: .firstTextBaseline) {
                    Text("\(prefix)\(n)").font(.body.monospaced().bold()).frame(width: 46, alignment: .leading)
                    Text(table[String(n)].map { phrase(prefix, n, $0) } ?? tr("No phrase with this number."))
                        .foregroundStyle(table[String(n)] == nil ? .secondary : .primary)
                }
            }
        }
    }

    private var hazardSymbols: some View {
        let letters = ["E": "Explosive", "O": "Oxidizing", "F": "Flammable", "T": "Toxic",
                       "C": "Corrosive", "X": "Harmful / irritant", "N": "Dangerous for the environment"]
        return VStack(alignment: .leading, spacing: 8) {
            Text("Hazard symbols").font(.title2.bold()).padding(.top, 16)
            HStack(alignment: .top, spacing: 16) {
                ForEach(letters.keys.sorted(), id: \.self) { k in
                    VStack {
                        if let img = ReferenceStore.image("hazard_\(k).png", in: "hazardsymbols") {
                            Image(nsImage: img).resizable().scaledToFit().frame(width: 64, height: 64)
                        }
                        Text(letters[k] ?? "").font(.caption).multilineTextAlignment(.center).frame(width: 84)
                    }
                }
            }
        }
    }
}

// MARK: Reference tables

struct TablesView: View {
    private let data = ReferenceStore.data
    var body: some View {
        TabView {
            Table(data?.greek ?? []) {
                TableColumn("Uppercase", value: \.upper)
                TableColumn("Lowercase", value: \.lower)
                TableColumn("Name", value: \.name)
            }
            .tabItem { Text("Greek alphabet") }
            Table(data?.numbers ?? []) {
                TableColumn("Number", value: \.number)
                TableColumn("Prefix") { Text($0.prefix) }
                TableColumn("Roman numeral", value: \.roman)
            }
            .tabItem { Text("Numeric prefixes & Roman numerals") }
        }
        .padding()
        .navigationTitle("Reference Tables")
    }
}

// MARK: Lab equipment

struct EquipmentView: View {
    private let tools = ReferenceStore.data?.tools ?? []
    @State private var selection: LabTool.ID? = {
        let all = ReferenceStore.data?.tools ?? []
        let want = ProcessInfo.processInfo.environment["XENON_ITEM"]?.lowercased()
        return (all.first { want != nil && $0.name.lowercased().contains(want!) } ?? all.first)?.id
    }()
    @State private var query = ""
    @ObservedObject private var jump = Jump.shared

    private var filtered: [LabTool] {
        query.isEmpty ? tools : tools.filter { $0.name.localizedCaseInsensitiveContains(query) || tr($0.name).localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        HSplitView {
            List(filtered, selection: $selection) { Text($0.name).tag($0.id) }
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)
            Group {
                if let t = tools.first(where: { $0.id == selection }) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(tr(t.name)).font(.largeTitle.bold())
                            if let img = ReferenceStore.image(t.picture, in: "toolpics") {
                                Image(nsImage: img).resizable().scaledToFit().frame(maxHeight: 280)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            Text(Markup.attributed(tr(t.desc))).font(.title3)
                        }
                        .padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Text("Select a piece of equipment").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear { if let g = jump.equipment { selection = g; jump.equipment = nil } }
        .searchable(text: $query, prompt: "Search equipment")
        .navigationTitle("Lab Equipment")
    }
}
