import SwiftUI

struct PeriodicTableView: View {
    let elements: [Element]
    let overlay: Overlay
    let temperature: Double
    let query: String
    var numeration: Numeration = .none
    var matchSet: Set<Int>? = nil
    var yearLimit: Double? = nil
    @Binding var selection: Element?

    private let gap: CGFloat = 3
    private let pad: CGFloat = 16
    private let fGap: CGFloat = 14
    private var topInset: CGFloat { numeration == .none ? 0 : 18 }

    var body: some View {
        GeometryReader { geo in
            // Size tiles so all 18 columns and 10 rows fit the available space.
            let byWidth = (geo.size.width - 2 * pad) / 18 - gap
            let byHeight = (geo.size.height - 2 * pad - fGap - topInset) / 10 - gap
            table(cell: max(28, min(byWidth, byHeight, 72)), viewport: geo.size)
        }
    }

    private func table(cell: CGFloat, viewport: CGSize) -> some View {
        let range = overlay.range(in: elements)
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                // Markers showing where the lanthanides and actinides belong
                if elements.count > 100 {
                    ForEach([(5, "57–71"), (6, "89–103")], id: \.0) { row, label in
                        RoundedRectangle(cornerRadius: 5).strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .frame(width: cell, height: cell)
                            .overlay(Text(label).font(.system(size: max(8, cell * 0.16))).foregroundStyle(.secondary))
                            .offset(x: CGFloat(2) * (cell + gap), y: topInset + CGFloat(row) * (cell + gap))
                    }
                }
                ForEach(elements) { e in
                    let pos = e.gridPosition
                    let matches = matchSet.map { $0.contains(e.z) } ?? (q.isEmpty || e.name.lowercased().contains(q)
                        || e.symbol.lowercased().contains(q) || String(e.z) == q)
                        && (yearLimit == nil || overlay != .discovery || (e.discoveryYear ?? 0) <= yearLimit!)
                    Tile(cell: cell, element: e,
                         fill: overlay.color(for: e, temperature: temperature, range: range),
                         selected: selection == e,
                         dimmed: !matches,
                         iconic: overlay == .iconic)
                        .frame(width: cell, height: cell)
                        .offset(x: CGFloat(pos.col) * (cell + gap),
                                y: topInset + CGFloat(pos.row) * (cell + gap) + (pos.row >= 8 ? fGap : 0))
                        .onTapGesture { selection = e }
                }
            }
            .overlay(alignment: .topLeading) {
                ForEach(Array(numeration.items.enumerated()), id: \.offset) { i, label in
                    Text(label).font(.system(size: max(9, cell * 0.2), weight: .medium)).foregroundStyle(.secondary)
                        .frame(width: cell, height: 16)
                        .offset(x: CGFloat(i) * (cell + gap))
                }
            }
            .frame(width: 18 * (cell + gap), height: 10 * (cell + gap) + fGap + topInset, alignment: .topLeading)
            .padding(pad)
            .frame(minWidth: viewport.width, minHeight: viewport.height, alignment: .topLeading)
        }
    }
}

private struct Tile: View {
    let cell: CGFloat
    let element: Element
    let fill: Color
    let selected: Bool
    let dimmed: Bool
    var iconic = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(element.z)").font(.system(size: max(7, cell * 0.17)))
                Spacer()
            }
            Text(element.symbol).font(.system(size: cell * 0.36, weight: .semibold))
            Text(element.name).font(.system(size: max(6, cell * 0.13))).lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(3)
        .foregroundStyle(.black.opacity(0.85))
        .shadow(color: iconic ? .white : .clear, radius: 1.5)
        .background {
            // Icon first: a later .background would be drawn behind it.
            if iconic, let img = ElementIcons.image(element.z) {
                Image(nsImage: img).resizable().scaledToFill().opacity(0.9)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
        }
        .background(RoundedRectangle(cornerRadius: 5).fill(fill))
        .overlay(RoundedRectangle(cornerRadius: 5)
            .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2.5))
        .opacity(dimmed ? 0.25 : 1)
        .contentShape(Rectangle())
    }
}
