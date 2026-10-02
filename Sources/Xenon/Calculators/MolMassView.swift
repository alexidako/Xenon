import SwiftUI

struct MolMassView: View {
    @State private var formula = "Ca(OH)2"
    @State private var newAlias = ""
    @State private var newExpansion = ""
    @State private var aliasMessage = ""
    @State private var aliases = AliasStore.all

    private var parsed: [ElementCount]? { FormulaParser.parse(formula) }
    private var totalMass: Double { parsed?.reduce(0) { $0 + $1.mass } ?? 0 }

    var body: some View {
        Form {
            Section("Formula") {
                TextField("Formula", text: $formula, prompt: Text("e.g. Ca(OH)2 or EtOH"))
                    .textFieldStyle(.roundedBorder).font(.title3.monospaced())
                Text("Use element symbols, parentheses and counts. Aliases such as Et, Me and Ph are expanded.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let parsed {
                Section("Result") {
                    LabeledContent("Molecular mass") {
                        Text(totalMass.formatted(.number.precision(.fractionLength(0...4))) + " u")
                            .font(.title2.bold()).textSelection(.enabled)
                    }
                    Table(parsed) {
                        TableColumn("Element") { Text($0.element.name) }
                        TableColumn("Count") { Text("\($0.count)").monospacedDigit() }
                        TableColumn("Atomic mass") { Text(formatNumber($0.element.mass ?? 0)).monospacedDigit() }
                        TableColumn("Mass") { Text(formatNumber($0.mass)).monospacedDigit() }
                        TableColumn("Share") {
                            Text((totalMass > 0 ? $0.mass / totalMass * 100 : 0)
                                .formatted(.number.precision(.fractionLength(2))) + " %").monospacedDigit()
                        }
                    }
                    .frame(minHeight: 40 + 28 * CGFloat(parsed.count))
                }
            } else {
                Section { Label("Invalid input", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            }
            Section("Aliases") {
                ForEach(aliases.keys.sorted(), id: \.self) { k in
                    LabeledContent(k) {
                        HStack {
                            Text(aliases[k] ?? "").font(.body.monospaced())
                            if AliasStore.user[k] != nil {
                                Button(role: .destructive) { remove(k) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                            }
                        }
                    }
                }
                HStack {
                    TextField("Symbol", text: $newAlias).frame(width: 100)
                    TextField("Expansion, e.g. C2H5", text: $newExpansion)
                    Button("Add") { add() }
                }
                if !aliasMessage.isEmpty { Text(aliasMessage).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
    }

    private func add() {
        aliasMessage = ""
        guard newAlias.count >= 2 else { aliasMessage = "A symbol needs two or more letters."; return }
        guard FormulaParser.parse(newAlias) == nil else { aliasMessage = "That symbol is already used."; return }
        guard FormulaParser.parse(newExpansion) != nil else { aliasMessage = "The expansion is not a valid formula."; return }
        AliasStore.user[newAlias] = newExpansion
        aliases = AliasStore.all; newAlias = ""; newExpansion = ""; aliasMessage = "Added."
    }

    private func remove(_ k: String) {
        var u = AliasStore.user; u[k] = nil; AliasStore.user = u; aliases = AliasStore.all
    }
}
