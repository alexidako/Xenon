import SwiftUI

struct TableScreen: View {
    @State private var selection: Element? = {
        let z = (ProcessInfo.processInfo.environment["XENON_START"] ?? "")
            .split(separator: ":").first.flatMap { Int($0) } ?? 1
        return ElementStore.all.first { $0.z == z }
    }()
    @State private var overlay: Overlay = Overlay(rawValue: ProcessInfo.processInfo.environment["XENON_OVERLAY"] ?? "") ?? .family
    @State private var numeration: Numeration = Numeration(rawValue: ProcessInfo.processInfo.environment["XENON_NUMERATION"] ?? "") ?? .none
    @State private var temperature: Double = 298
    @State private var year: Double = 2020
    @State private var query = ProcessInfo.processInfo.environment["XENON_QUERY"] ?? ""
    @State private var showLegend = true
    @ObservedObject private var jump = Jump.shared
    @State private var showInspector = true

    private var queryResult: ElementQuery.Result? {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.count >= (QueryVocab.language == "zh" ? 2 : 3) ? ElementQuery.run(q) : nil
    }

    private var yearRange: ClosedRange<Double> { Overlay.discovery.range(in: ElementStore.all) }

    var body: some View {
        VStack(spacing: 0) {
            controls.frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            Divider()
            if let nl = queryResult { QueryBanner(result: nl, select: { selection = $0 }); Divider() }
            if showLegend { LegendView(overlay: overlay).padding(.horizontal, 12).padding(.vertical, 8).frame(minWidth: 0, maxWidth: .infinity, alignment: .leading); Divider() }
            PeriodicTableView(elements: ElementStore.all, overlay: overlay, temperature: temperature,
                              query: query, numeration: numeration, matchSet: queryResult.map { Set($0.matches.map(\.z)) },
                              yearLimit: overlay == .discovery ? year : nil, selection: $selection)
        }
        .inspector(isPresented: $showInspector) {
            Group {
                if let selection { DetailView(element: selection) }
                else { Text("Select an element").foregroundStyle(.secondary) }
            }
            .inspectorColumnWidth(min: 340, ideal: 440, max: 640)
        }
        .onAppear { if let z = jump.element { selection = ElementStore.all.first { $0.z == z }; jump.element = nil } }
        .onChange(of: jump.element) { _, z in if let z { selection = ElementStore.all.first { $0.z == z }; jump.element = nil } }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showInspector.toggle() } label: { Label("Element details", systemImage: "sidebar.right") }
                    .help("Show or hide the element details")
            }
        }
        .searchable(text: $query, prompt: "Search or ask a question")
        .navigationTitle("Periodic Table")
    }

    private var controls: some View {
        // wraps in a narrow window or with long translations; the legend toggle stays at the right when there is room
        FlowLayout(spacing: 14, trailingLast: true) { controlItems; legendToggle }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .padding(10)
    }

    private var legendToggle: some View { Toggle("Legend", isOn: $showLegend).toggleStyle(.checkbox).fixedSize() }

    @ViewBuilder private var controlItems: some View {
        Picker("Color by", selection: $overlay) {
            Section("Color schemes") { ForEach(Overlay.schemes) { Text($0.rawValue).tag($0) } }
            Section("Gradients") { ForEach(Overlay.gradients) { Text($0.rawValue).tag($0) } }
            Section("Special") { Text(Overlay.state.rawValue).tag(Overlay.state) }
        }
        .fixedSize()
        Picker("Numeration", selection: $numeration) {
            ForEach(Numeration.allCases) { Text($0.rawValue).tag($0) }
        }
        .fixedSize()
        if overlay == .state {
            Slider(value: $temperature, in: 0...6000).frame(width: 200)
            Text(Preferences.shared.temperatureText(temperature)).monospacedDigit().fixedSize()
        }
        if overlay == .discovery {
            Slider(value: $year, in: yearRange).frame(width: 200)
            Text(tr("up to {year}", ["year": Int(year)])).monospacedDigit().fixedSize()
        }
    }
}

struct LegendView: View {
    let overlay: Overlay
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        switch overlay.kind {
        case .scheme, .state:
            if let note = overlay.note {
                Text(note).font(.callout).foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 12) {
                    ForEach(overlay.legend, id: \.0) { name, color in
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 14, height: 14)
                            Text(name).font(.callout)
                        }
                    }
                }
            }
        case .gradient:
            let r = overlay.range(in: ElementStore.all)
            HStack(spacing: 8) {
                Text(prefs.display(overlay, r.lowerBound)).font(.callout.monospacedDigit())
                LinearGradient(colors: (0...10).map { Overlay.gradientColor(Double($0) / 10) }, startPoint: .leading, endPoint: .trailing)
                    .frame(height: 12).clipShape(Capsule()).frame(maxWidth: 320)
                Text(prefs.display(overlay, r.upperBound)).font(.callout.monospacedDigit())
                Spacer()
            }
        }
    }
}

/// Minimal wrapping row layout for legend swatches.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    /// When everything fits on one row, push the last item to the right edge.
    var trailingLast = false

    private func rows(_ subviews: Subviews, width: CGFloat) -> (positions: [CGPoint], size: CGSize, oneRow: Bool) {
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0, rowsUsed = 1
        var pos: [CGPoint] = []
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0; rowsUsed += 1 }
            pos.append(CGPoint(x: x, y: y))
            x += s.width + spacing; rowH = max(rowH, s.height); maxX = max(maxX, x - spacing)
        }
        return (pos, CGSize(width: maxX, height: y + rowH), rowsUsed == 1)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let r = rows(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: trailingLast && r.oneRow ? max(r.size.width, proposal.width ?? 0) : r.size.width, height: r.size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let r = rows(subviews, width: bounds.width)
        for (i, v) in subviews.enumerated() {
            let s = v.sizeThatFits(.unspecified)
            var p = CGPoint(x: bounds.minX + r.positions[i].x, y: bounds.minY + r.positions[i].y)
            if trailingLast, r.oneRow, i == subviews.count - 1, subviews.count > 1 { p.x = bounds.maxX - s.width }
            v.place(at: p, proposal: ProposedViewSize(s))
        }
    }
}

struct QueryBanner: View {
    let result: ElementQuery.Result
    let select: (Element) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: result.unsupported ? "exclamationmark.circle" : "sparkle.magnifyingglass")
                Text(result.description).font(.callout.weight(.medium))
                if !result.unsupported { Text("· " + tr("{n} found", ["n": result.matches.count])).font(.callout).foregroundStyle(.secondary) }
            }
            .foregroundStyle(result.unsupported ? .orange : .primary)
            if !result.matches.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(result.matches) { e in
                        Button { select(e) } label: {
                            Text(e.symbol).font(.callout.monospaced().weight(.semibold))
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background((e.familyKind?.color ?? .gray).opacity(0.8), in: RoundedRectangle(cornerRadius: 5))
                                .foregroundStyle(.black.opacity(0.85))
                        }
                        .buttonStyle(.plain)
                        .help(tr(e.name))
                    }
                }
            } else if !result.unsupported {
                Text("No element matches.").font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4))
    }
}
