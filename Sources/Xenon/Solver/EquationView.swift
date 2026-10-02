import SwiftUI

struct EquationView: View {
    enum Mode: String, CaseIterable, Identifiable { case balance = "Balance", stoich = "Stoichiometry"; var id: String { rawValue } }
    @State private var mode: Mode = Mode(rawValue: ProcessInfo.processInfo.environment["XENON_EQ_MODE"] ?? "") ?? .balance
    @State private var equation = ProcessInfo.processInfo.environment["XENON_EQ"] ?? "aCH3CH2OH + bO2 -> cH2O + dCO2"
    @State private var answer: String?
    @State private var error: String?

    private let examples = [
        "aCH3CH2OH + bO2 -> cH2O + dCO2",
        "aAl + bHCl -> cAlCl3 + dH2",
        "aH + bO -> 5H2O",
        "aFe[2+] + bMnO4[-] + cH3O[+] -> dMn[2+] + eH2O + fFe[3+]",
        "aCH3(CH2)3COOH + bO2 -> cH2O + dCO2",
    ]

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) { ForEach(Mode.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 320).padding(10)
            Divider()
            if mode == .stoich {
                VStack(spacing: 0) {
                    TextField("", text: $equation, prompt: Text("e.g. aH2 + bO2 -> cH2O"))
                        .font(.title3.monospaced()).textFieldStyle(.roundedBorder).padding(12)
                    StoichiometryView(equation: equation)
                }
            } else { balanceForm }
        }
        .navigationTitle("Equation Solver")
    }

    private var balanceForm: some View {
        Form {
            Section("Equation") {
                TextField("", text: $equation, prompt: Text("e.g. aH2 + bO2 -> cH2O"))
                    .font(.title3.monospaced()).textFieldStyle(.roundedBorder)
                    .onSubmit(solve)
                HStack {
                    Button("Solve", action: solve).keyboardShortcut(.defaultAction)
                    Menu("Examples") {
                        ForEach(examples, id: \.self) { ex in Button(ex) { equation = ex; solve() } }
                    }.fixedSize()
                    Spacer()
                }
            }
            Section("Result") {
                if let answer {
                    HStack {
                        Text(Markup.formulaText(answer)).font(.title3.monospaced()).textSelection(.enabled)
                        Spacer()
                        Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(Markup.formulaText(answer), forType: .string) }
                    }
                } else if let error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                } else {
                    Text("Enter an equation and press Solve.").foregroundStyle(.secondary)
                }
            }
            Section("How to write equations") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Put a single lowercase letter in front of a molecule to leave its coefficient open, or a number to fix it. The solver finds the smallest whole numbers that balance every element and the electric charge.")
                    Text("aH + bO -> 5H2O   gives   10 H + 5 O -> 5 H2O").font(.callout.monospaced())
                    Text("Use square brackets for charges, for example Fe[2+] or OH[-]. Parentheses are allowed: CH3(CH2)3COOH.")
                    Text("The same letter used twice stands for the same quantity.")
                    Text("Equations that need fractional coefficients, or cannot be balanced, report “Not found”.")
                }
                .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { if ProcessInfo.processInfo.environment["XENON_SECTION"] == "Equation Solver" { solve() } }
    }

    private func solve() {
        let known = Set(ElementStore.all.map(\.symbol))
        switch EquationSolver.solve(equation, isElement: { known.contains($0) }) {
        case .success(let s): answer = s; error = nil
        case .failure(.notFound): answer = nil; error = tr("Not found: no whole-number solution exists for this equation.")
        case .failure(.parse(let why)): answer = nil; error = tr("Parse error: {why}.", ["why": why])
        }
    }
}
