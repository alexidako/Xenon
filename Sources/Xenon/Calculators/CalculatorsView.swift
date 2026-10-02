import SwiftUI

struct CalculatorsView: View {
    enum Kind: String, CaseIterable, Identifiable {
        case molMass = "Molecular mass", gas = "Gas", concentration = "Concentration"
        case nuclear = "Nuclear decay", titration = "Titration"
        var id: String { rawValue }
    }
    @State private var kind: Kind = Kind(rawValue: ProcessInfo.processInfo.environment["XENON_CALC"] ?? "") ?? .molMass

    var body: some View {
        VStack(spacing: 0) {
            Picker("Calculator", selection: $kind) { ForEach(Kind.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden().padding(10)
            Divider()
            switch kind {
            case .molMass: MolMassView()
            case .gas: GasView()
            case .concentration: ConcView()
            case .nuclear: NuclearView()
            case .titration: TitrationView()
            }
        }
        .navigationTitle("Calculators")
    }
}
