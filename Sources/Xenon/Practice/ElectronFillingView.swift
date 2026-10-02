import SwiftUI

/// Build an element's electron configuration yourself. Pauli, Hund and Aufbau are enforced, with an explanation when you break one.
struct ElectronFillingView: View {
    @State private var z = Int(ProcessInfo.processInfo.environment["XENON_FILL_Z"] ?? "") ?? 8
    @State private var state = FillState()
    @State private var strict = ProcessInfo.processInfo.environment["XENON_FILL_RELAXED"] == nil
    @State private var removing = false
    @State private var warning: String?
    @State private var hint: (sub: Int, box: Int)?
    @State private var started = false

    private var element: Element { ElementStore.all[max(0, min(117, z - 1))] }
    private var verdict: FillState.Verdict { state.verdict(for: element) }

    /// Rows to show: everything up to one past the last subshell this element uses.
    private var visibleRows: Range<Int> {
        let used = Set(Subshells.aufbau(z).keys).union(Subshells.actual(element).keys).compactMap(Subshells.index(of:))
        return 0..<min(Subshells.order.count, (used.max() ?? 0) + 2)
    }

    /// "**Aufbau:** fill the lowest-energy ..." with both parts translated.
    private func rule(_ name: String, _ text: String) -> Text {
        Text(verbatim: tr(name)).bold() + Text(verbatim: " " + tr(text))
    }

    var body: some View {
        HSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    ForEach(Array(visibleRows), id: \.self) { sub in row(sub) }
                }
                .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 480)
            side.frame(minWidth: 300, idealWidth: 340, maxWidth: 420)
        }
        .navigationTitle("Electron Filling")
        .onAppear {
            guard !started else { return }
            started = true
            // Test hook: pre-place the first N electrons by following the rules.
            if let n = Int(ProcessInfo.processInfo.environment["XENON_FILL_PLACED"] ?? "") {
                for _ in 0..<n { if let t = state.nextTarget(electrons: z) { _ = state.place(sub: t.sub, box: t.box, electrons: z, strictAufbau: false) } }
            }
            if let w = ProcessInfo.processInfo.environment["XENON_FILL_TRY"] {          // "2s" = attempt to place into that subshell
                if let i = Subshells.index(of: w), case .refused(let why) = state.place(sub: i, box: 0, electrons: z, strictAufbau: strict) { warning = why }
            }
        }
    }

    // MARK: pieces

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(spacing: 0) {
                Text("\(element.z)").font(.caption)
                Text(element.symbol).font(.system(size: 34, weight: .bold))
            }
            .frame(width: 64, height: 64)
            .background(RoundedRectangle(cornerRadius: 8).fill(element.familyKind?.color ?? .gray.opacity(0.4)))
            .foregroundStyle(.black.opacity(0.85))
            VStack(alignment: .leading, spacing: 4) {
                Text(element.name).font(.title.bold())
                Text(tr("{n} of {z} electrons placed", ["n": state.total, "z": z])).foregroundStyle(.secondary)
                ProgressView(value: Double(state.total), total: Double(z)).frame(width: 220)
            }
        }
    }

    private func row(_ sub: Int) -> some View {
        let s = Subshells.order[sub]
        return HStack(spacing: 10) {
            Text(s.name).font(.title3.monospaced().weight(.semibold)).frame(width: 40, alignment: .trailing)
            HStack(spacing: 6) {
                ForEach(0..<s.orbitals, id: \.self) { b in
                    FillBox(electrons: state.boxes[sub][b], highlighted: hint.map { $0.sub == sub && $0.box == b } ?? false)
                        .onTapGesture { tap(sub, b) }
                }
            }
            Text(state.count(sub) == 0 ? "" : "\(state.count(sub))/\(s.capacity)").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var side: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Element", selection: $z) {
                    ForEach(ElementStore.all) { Text("\($0.z)  \(tr($0.name))").tag($0.z) }
                }
                .onChange(of: z) { _, _ in reset() }
                HStack {
                    Button("Random") { z = Int.random(in: 1...54); reset() }
                    Button("Reset") { reset() }
                    Button("Hint") { hint = state.nextTarget(electrons: z); warning = nil }.disabled(state.total >= z)
                    Button("Fill for me") { autofill() }
                }
                Picker("Click", selection: $removing) { Text("Adds an electron").tag(false); Text("Removes an electron").tag(true) }
                    .pickerStyle(.segmented).labelsHidden()
                Toggle("Strict Aufbau order", isOn: $strict)
                    .help("Turn off to build exceptions such as chromium and copper")

                if let w = warning {
                    Label(w, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
                if state.total == z {
                    let v = verdict
                    Label(v.message, systemImage: v.matchesActual ? "checkmark.seal.fill" : "info.circle.fill")
                        .font(.callout).foregroundStyle(v.matchesActual ? Color.green : Color.blue)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background((v.matchesActual ? Color.green : Color.blue).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
                GroupBox("Your configuration") {
                    Text(state.total == 0 ? "—" : Subshells.format(state.configuration)).font(.title3.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading).padding(6).textSelection(.enabled)
                }
                GroupBox("The three rules") {
                    VStack(alignment: .leading, spacing: 6) {
                        rule("Aufbau:", "fill the lowest-energy subshell first (1s, 2s, 2p, 3s, 3p, 4s, 3d …).")
                        rule("Pauli:", "an orbital holds at most 2 electrons, spinning opposite ways (↑ then ↓).")
                        rule("Hund:", "in a subshell, give every orbital one electron before pairing any up.")
                    }.font(.callout).padding(6).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(16)
        }
    }

    // MARK: actions

    private func tap(_ sub: Int, _ box: Int) {
        hint = nil
        if removing {
            if !state.remove(sub: sub, box: box) { warning = "That orbital is already empty." } else { warning = nil }
            return
        }
        switch state.place(sub: sub, box: box, electrons: z, strictAufbau: strict) {
        case .ok: warning = nil
        case .refused(let why): warning = why
        }
    }

    private func reset() { state = FillState(); warning = nil; hint = nil }

    private func autofill() {
        reset()
        let real = Subshells.actual(element), predicted = Subshells.aufbau(z)
        if !strict && real != predicted {                       // build the real (exceptional) configuration, still obeying Hund
            for (name, n) in real.sorted(by: { Subshells.index(of: $0.key)! < Subshells.index(of: $1.key)! }) {
                let i = Subshells.index(of: name)!
                for _ in 0..<n {
                    let box = state.boxes[i].firstIndex(of: 0) ?? state.boxes[i].firstIndex(of: 1)!
                    _ = state.place(sub: i, box: box, electrons: z, strictAufbau: false)
                }
            }
        } else {
            while let t = state.nextTarget(electrons: z) { _ = state.place(sub: t.sub, box: t.box, electrons: z, strictAufbau: strict) }
        }
    }
}

struct FillBox: View {
    let electrons: Int
    var highlighted = false

    /// "**Aufbau:** fill the lowest-energy ..." with both parts translated.
    private func rule(_ name: String, _ text: String) -> Text {
        Text(verbatim: tr(name)).bold() + Text(verbatim: " " + tr(text))
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(highlighted ? Color.yellow.opacity(0.25) : Color.secondary.opacity(0.10))
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(highlighted ? Color.yellow : Color.secondary.opacity(0.7), lineWidth: highlighted ? 2.5 : 1.5)
            HStack(spacing: 3) {
                if electrons >= 1 { Image(systemName: "arrow.up").font(.system(size: 17, weight: .bold)) }
                if electrons >= 2 { Image(systemName: "arrow.down").font(.system(size: 17, weight: .bold)) }
            }
        }
        .frame(width: 50, height: 44)
        .contentShape(Rectangle())
    }
}
