import SwiftUI

struct IsotopeListView: View {
    let element: Element

    var body: some View {
        let list = IsotopeStore.byElement[element.z] ?? []
        VStack(alignment: .leading, spacing: 10) {
            Text("\(list.count) known isotopes")
                .foregroundStyle(.secondary)
            if list.isEmpty {
                Text("No isotope data.").foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                    GridRow {
                        Text("Isotope"); Text("Abundance"); Text("Half-life"); Text("Spin"); Text("Decay")
                    }
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Divider().gridCellUnsizedAxes(.horizontal)
                    ForEach(list) { iso in
                        GridRow {
                            Text("\(iso.a)\(element.symbol)").fontWeight(iso.abundance != nil ? .semibold : .regular)
                            AbundanceCell(percent: iso.abundance)
                            Text(iso.halfLifeText).monospacedDigit().fixedSize()
                            Text(iso.spin ?? "—")
                            Text(decaySummary(iso)).fixedSize()
                        }
                        .font(.callout)
                    }
                }
                .padding(.bottom, 6)
                }
            }
        }
    }

    private func decaySummary(_ iso: Isotope) -> String {
        iso.decays.prefix(2).map { d in
            d.percent.map { "\(d.label) \($0.formatted(.number.precision(.significantDigits(1...3))))%" } ?? d.label
        }.joined(separator: ", ")
    }
}

private struct AbundanceCell: View {
    let percent: Double?
    private let barWidth: CGFloat = 40

    var body: some View {
        if let percent {
            HStack(spacing: 6) {
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(Color.accentColor)
                        .frame(width: max(2, barWidth * percent / 100))
                }
                .frame(width: barWidth, height: 6)
                Text(percent.formatted(.number.precision(.significantDigits(1...4))) + "%")
                    .monospacedDigit()
                    .fixedSize()
            }
        } else {
            Text("—").foregroundStyle(.secondary)
        }
    }
}
