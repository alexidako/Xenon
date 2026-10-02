import SwiftUI

/// Export selected elements and properties as HTML, XML or CSV (Kalzium's "Export Data" dialog).
struct ExportView: View {
    enum Format: String, CaseIterable, Identifiable { case html = "HTML", xml = "XML", csv = "CSV"; var id: String { rawValue } }

    struct Property: Identifiable, Hashable {
        let name: String
        let value: (Element) -> String
        var id: String { name }
        static func == (a: Property, b: Property) -> Bool { a.name == b.name }
        func hash(into h: inout Hasher) { h.combine(name) }
    }

    private static func num(_ v: Double?, _ unit: String = "") -> String {
        guard let v else { return "" }
        let s = v.formatted(.number.precision(.fractionLength(0...5)).grouping(.never))
        return unit.isEmpty ? s : "\(s) \(unit)"
    }

    static let properties: [Property] = [
        Property(name: "Atomic Number") { String($0.z) },
        Property(name: "Symbol") { $0.symbol },
        Property(name: "Mass") { num($0.mass, "u") },
        Property(name: "Exact Mass") { num($0.exactMass, "u") },
        Property(name: "Ionization") { num($0.ionization, "eV") },
        Property(name: "Electron Affinity") { num($0.electronAffinity, "eV") },
        Property(name: "Electronegativity") { num($0.electronegativity) },
        Property(name: "Covalent Radius") { num($0.radiusCovalent, "Å") },
        Property(name: "Van der Waals Radius") { num($0.radiusVDW, "Å") },
        Property(name: "Melting Point") { num($0.meltingPoint, "K") },
        Property(name: "Boiling Point") { num($0.boilingPoint, "K") },
        Property(name: "Family") { $0.familyKind?.label ?? "" },
    ]

    @State private var elements = Set<Int>(ElementStore.all.map(\.z))
    @State private var props = Set<Property>(Array(properties.prefix(3)))
    @State private var format: Format = .html
    @State private var message = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Elements").font(.headline)
                        Spacer()
                        Button("All") { elements = Set(ElementStore.all.map(\.z)) }.buttonStyle(.link)
                        Button("None") { elements = [] }.buttonStyle(.link)
                    }
                    List(ElementStore.all, selection: $elements) { Text("\($0.z)  \($0.name)").tag($0.z) }
                }
                .padding(12)
                Divider()
                VStack(alignment: .leading) {
                    HStack {
                        Text("Properties").font(.headline)
                        Spacer()
                        Button("All") { props = Set(Self.properties) }.buttonStyle(.link)
                        Button("None") { props = [] }.buttonStyle(.link)
                    }
                    List(Self.properties, selection: $props) { Text($0.name).tag($0) }
                }
                .padding(12)
            }
            Divider()
            HStack {
                Picker("Format", selection: $format) { ForEach(Format.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).frame(width: 220)
                Text("\(elements.count) elements, \(props.count) properties").foregroundStyle(.secondary)
                Spacer()
                if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary) }
                Button("Export…", action: export).disabled(elements.isEmpty || props.isEmpty).keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .navigationTitle("Export Data")
    }

    private func export() {
        let els = ElementStore.all.filter { elements.contains($0.z) }
        let ps = Self.properties.filter { props.contains($0) }
        let text: String
        switch format {
        case .html: text = html(els, ps)
        case .xml: text = xml(els, ps)
        case .csv: text = csv(els, ps)
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "elements." + format.rawValue.lowercased()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try text.write(to: url, atomically: true, encoding: .utf8); message = "Saved \(url.lastPathComponent)" }
        catch { message = "Save failed: \(error.localizedDescription)" }
    }

    private func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func html(_ els: [Element], _ ps: [Property]) -> String {
        var s = """
        <html>
        <head>
        <meta http-equiv="Content-Type" content="text/html; charset=UTF-8"/>
        <style type="text/css">
        body { font-family: arial; } .property { font-style: italic; }
        th { font-weight: bold; text-align: left; background-color: #F0F0F0; }
        </style>
        </head>
        <body>
        <table>

        """
        for e in els {
            s += "<tr>\n<th colspan=\"2\">\(esc(e.name))</th>\n</tr>\n"
            for p in ps { s += "<tr>\n<td class=\"property\">\(esc(p.name))</td>\n<td class=\"value\">\(esc(p.value(e)))</td>\n</tr>\n" }
        }
        return s + "</table>\n</body>\n</html>\n"
    }

    private func xml(_ els: [Element], _ ps: [Property]) -> String {
        var s = "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>\n<elements>\n"
        for e in els {
            s += "  <element name=\"\(esc(e.name))\">\n"
            for p in ps { s += "    <property name=\"\(esc(p.name))\">\(esc(p.value(e)))</property>\n" }
            s += "  </element>\n"
        }
        return s + "</elements>\n"
    }

    private func csv(_ els: [Element], _ ps: [Property]) -> String {
        func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var s = (["Name"] + ps.map(\.name)).map(q).joined(separator: ",") + "\n"
        for e in els { s += ([e.name] + ps.map { $0.value(e) }).map(q).joined(separator: ",") + "\n" }
        return s
    }
}
