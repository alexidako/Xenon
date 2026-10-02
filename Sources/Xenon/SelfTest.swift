import Foundation

/// Command-line checks of the logic engines: `swift run Xenon --selftest`
enum SelfTest {
    static var failures = 0

    static func check(_ ok: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
        print((ok ? "PASS  " : "FAIL  ") + name + (ok ? "" : "   -> " + detail()))
        if !ok { failures += 1 }
    }

    static func symbols(_ r: ElementQuery.Result?) -> [String] { r?.matches.map(\.symbol) ?? [] }

    /// `Xenon --query "text"` prints what the plain-language search finds.
    static func query(_ text: String) {
        if let r = ElementQuery.run(text) { print("\(r.matches.count) match(es) [\(r.description)]: " + r.matches.map(\.symbol).joined(separator: " ")) }
        else { print("not a query (falls back to name search)") }
        exit(0)
    }

    static func geometry(_ name: String) {
        let m = Embed3D.embed(SketchTemplates.make(name, cx: 0, cy: 0), name: name)
        for (i, a) in m.atoms.enumerated() { print(i, a.symbol, String(format: "%.2f %.2f %.2f", a.x, a.y, a.z)) }
        for b in m.bonds { print("bond", b.a, b.b, b.order) }
        let c = m.atoms.firstIndex { $0.symbol == "C" && m.bonds.contains { ($0.a == m.atoms.firstIndex(of: $0.a == 0 ? m.atoms[0] : m.atoms[0]) ?? -1) } } ?? 0
        _ = c
        let carbonyl = m.bonds.first { $0.order == 2 }!.a
        let nb = m.bonds.compactMap { $0.a == carbonyl ? $0.b : ($0.b == carbonyl ? $0.a : nil) }
        print("carbonyl C =", carbonyl, "neighbors", nb, "angles", VBT.angles(at: carbonyl, in: m, neighbors: nb))
        exit(0)
    }

    static func run() {
        setvbuf(stdout, nil, _IONBF, 0)      // so a crash does not swallow the results printed before it
        // ---- natural-language query ----
        let q = ElementQuery.run
        let liquid = symbols(q("liquid at room temperature", nil))
        check(liquid.contains("Hg") && liquid.contains("Br") && liquid.count <= 3, "liquid at room temperature", "\(liquid)")
        check(symbols(q("noble gases", nil)).sorted() == ["Ar", "He", "Kr", "Ne", "Og", "Rn", "Xe"], "noble gases", "\(symbols(q("noble gases", nil)))")
        check(Set(symbols(q("halogens discovered before 1850", nil))) == ["Cl", "Br", "I"], "halogens discovered before 1850", "\(symbols(q("halogens discovered before 1850", nil)))")
        check(symbols(q("highest electronegativity", nil)).first == "F", "highest electronegativity", "\(symbols(q("highest electronegativity", nil)))")
        check(symbols(q("heaviest noble gas", nil)).first == "Og", "heaviest noble gas", "\(symbols(q("heaviest noble gas", nil)))")
        let hot = symbols(q("melting point above 3000 K", nil))
        check(["W", "Re", "Ta", "Os"].allSatisfy(hot.contains) && !hot.contains("Fe"), "melting point above 3000 K", "\(hot)")
        check(Set(symbols(q("group 17", nil))) == ["F", "Cl", "Br", "I", "At", "Ts"], "group 17", "\(symbols(q("group 17", nil)))")
        check(Set(symbols(q("period 2 nonmetals", nil))) == ["C", "N", "O"], "period 2 nonmetals", "\(symbols(q("period 2 nonmetals", nil)))")
        let cold = symbols(q("boiling point below 0 °C", nil))
        check(cold.contains("He") && cold.contains("N") && cold.contains("O") && !cold.contains("Fe"), "boiling point below 0 °C", "\(cold)")
        check(q("iron", nil) == nil && q("mercury", nil) == nil && q("sodium", nil) == nil, "plain names are not queries")
        check(symbols(q("discovered in sweden", nil)).contains("S") == false && !symbols(q("discovered in sweden", nil)).isEmpty, "discovered in sweden", "\(symbols(q("discovered in sweden", nil)))")
        check(q("density of lead", nil)?.unsupported == true, "unsupported property is reported")
        check(Set(symbols(q("lowest melting point", nil))).contains("He"), "lowest melting point", "\(symbols(q("lowest melting point", nil)))")
        check(Set(symbols(q("s-block metals in period 3", nil))) == ["Na", "Mg"], "s-block metals in period 3", "\(symbols(q("s-block metals in period 3", nil)))")
        let radio = symbols(q("radioactive group 17", ElementQuery.stable))
        check(Set(radio) == ["At", "Ts"], "radioactive group 17", "\(radio)")

        // ---- stoichiometry ----
        StoichSelfTest.run()
        // ---- spectrum matcher ----
        MatcherSelfTest.run()
        // ---- text markup ----
        MarkupSelfTest.run()
        // ---- robustness ----
        MainActor.assumeIsolated { FuzzTests.run() }
        // ---- resonance ----
        MainActor.assumeIsolated { ResonanceSelfTest.run() }
        // ---- quick lookup ----
        MainActor.assumeIsolated { PaletteSelfTest.run() }
        // ---- settings ----
        MainActor.assumeIsolated { PreferencesSelfTest.run() }
        // ---- 3D viewer controls ----
        MainActor.assumeIsolated { TrackballSelfTest.run() }
        // ---- quiz ----
        MainActor.assumeIsolated { QuizSelfTest.run() }
        // ---- electron filling ----
        MainActor.assumeIsolated { FillingSelfTest.run() }
        // ---- orbitals ----
        MainActor.assumeIsolated { OrbitalSelfTest.run(); OverlayFilterSelfTest.run() }
        // ---- geometry optimizer ----
        MainActor.assumeIsolated { OptimizerSelfTest.run(); AngleOverlaySelfTest.run() }
        // ---- molecule editor ----
        MainActor.assumeIsolated { EditorSelfTest.run() }
        // ---- valence bond theory ----
        VBTSelfTest.run()

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
