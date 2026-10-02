import Foundation

/// Rules for filling orbitals with electrons: Aufbau (lowest energy first), Pauli (two per orbital) and Hund
/// (spread out before pairing). Used by the Electron Filling practice screen.
enum Subshells {
    struct Sub: Hashable, Identifiable {
        let n: Int
        let l: Int
        var id: String { name }
        var letter: String { String("spdf"[String.Index(utf16Offset: l, in: "spdf")]) }
        var name: String { "\(n)\(letter)" }
        var orbitals: Int { 2 * l + 1 }
        var capacity: Int { 2 * orbitals }
    }

    /// 1s 2s 2p 3s 3p 4s 3d 4p 5s 4d 5p 6s 4f 5d 6p 7s 5f 6d 7p (Madelung order)
    static let order: [Sub] = (1...7).flatMap { n in (0...min(n - 1, 3)).map { Sub(n: n, l: $0) } }
        .sorted { ($0.n + $0.l, $0.n) < ($1.n + $1.l, $1.n) }

    static func index(of name: String) -> Int? { order.firstIndex { $0.name == name } }

    static func superscript(_ n: Int) -> String {
        String(String(n).map { c -> Character in
            "⁰¹²³⁴⁵⁶⁷⁸⁹"[String.Index(utf16Offset: Int(String(c))!, in: "⁰¹²³⁴⁵⁶⁷⁸⁹")]
        })
    }

    /// "3d⁵ 4s¹", written the conventional way (by shell, then s p d f).
    static func format(_ config: [String: Int]) -> String {
        config.filter { $0.value > 0 }
            .sorted { a, b in
                let sa = order[index(of: a.key)!], sb = order[index(of: b.key)!]
                return (sa.n, sa.l) < (sb.n, sb.l)
            }
            .map { "\($0.key)\(superscript($0.value))" }.joined(separator: " ")
    }

    /// The configuration the Aufbau order predicts for `z` electrons.
    static func aufbau(_ z: Int) -> [String: Int] {
        var left = z, out: [String: Int] = [:]
        for s in order where left > 0 { let k = min(left, s.capacity); out[s.name] = k; left -= k }
        return out
    }

    /// The measured configuration from the element data (noble-gas cores expanded).
    static func actual(_ e: Element) -> [String: Int] {
        var out: [String: Int] = [:]
        for s in ElectronConfiguration.subshells(e.configuration ?? "") { out["\(s.n)\(s.l)", default: 0] += s.electrons }
        return out
    }
}

struct FillState: Equatable {
    /// electrons per orbital box, grouped by subshell in Aufbau order (0, 1 or 2 each)
    var boxes: [[Int]] = Subshells.order.map { [Int](repeating: 0, count: $0.orbitals) }

    var total: Int { boxes.joined().reduce(0, +) }

    func count(_ sub: Int) -> Int { boxes[sub].reduce(0, +) }

    func isFull(_ sub: Int) -> Bool { count(sub) == Subshells.order[sub].capacity }

    var configuration: [String: Int] {
        var out: [String: Int] = [:]
        for (i, s) in Subshells.order.enumerated() where count(i) > 0 { out[s.name] = count(i) }
        return out
    }

    enum Outcome: Equatable { case ok, refused(String) }

    /// Tries to add one electron to a box.
    mutating func place(sub: Int, box: Int, electrons z: Int, strictAufbau: Bool) -> Outcome {
        let s = Subshells.order[sub]
        if total >= z { return .refused("All \(z) electrons are already placed. Remove one first.") }
        if boxes[sub][box] >= 2 {
            return .refused("Pauli exclusion principle: an orbital holds at most two electrons, with opposite spins.")
        }
        if strictAufbau, let lower = (0..<sub).first(where: { !isFull($0) }) {
            return .refused("Aufbau principle: electrons fill the lowest-energy subshell first. \(Subshells.order[lower].name) is not full yet.")
        }
        if boxes[sub][box] == 1, boxes[sub].contains(0) {
            return .refused("Hund's rule: in \(s.name), put one electron in each orbital (all spinning the same way) before pairing any up.")
        }
        boxes[sub][box] += 1
        return .ok
    }

    @discardableResult mutating func remove(sub: Int, box: Int) -> Bool {
        guard boxes[sub][box] > 0 else { return false }
        boxes[sub][box] -= 1
        return true
    }

    /// Where the next electron should go, following all three rules.
    func nextTarget(electrons z: Int) -> (sub: Int, box: Int)? {
        guard total < z, let sub = (0..<Subshells.order.count).first(where: { !isFull($0) }) else { return nil }
        if let empty = boxes[sub].firstIndex(of: 0) { return (sub, empty) }
        if let single = boxes[sub].firstIndex(of: 1) { return (sub, single) }
        return nil
    }

    struct Verdict {
        let complete: Bool
        let matchesAufbau: Bool
        let matchesActual: Bool
        let message: String
    }

    func verdict(for e: Element) -> Verdict {
        guard total == e.z else {
            return Verdict(complete: false, matchesAufbau: false, matchesActual: false,
                           message: "\(total) of \(e.z) electrons placed.")
        }
        let mine = configuration, predicted = Subshells.aufbau(e.z), real = Subshells.actual(e)
        let a = mine == predicted, r = mine == real
        var msg: String
        if r && a {
            msg = "Correct. \(e.name) is \(Subshells.format(real)), exactly what the Aufbau order predicts."
        } else if r {
            msg = "Correct! This is the real configuration of \(e.name): \(Subshells.format(real)). It breaks the simple Aufbau order (which predicts \(Subshells.format(predicted))) because \(FillState.reason(for: e))."
        } else if a {
            msg = "This follows the Aufbau order, but real \(e.name) is an exception: \(Subshells.format(real)), because \(FillState.reason(for: e)). Turn off “Strict Aufbau” to build it."
        } else {
            msg = "Not quite. \(e.name) is \(Subshells.format(real))."
        }
        return Verdict(complete: true, matchesAufbau: a, matchesActual: r, message: msg)
    }

    static func reason(for e: Element) -> String {
        let real = Subshells.actual(e)
        if real["3d"] == 5 || real["4d"] == 5 || real["5d"] == 5 { return "a half-filled d subshell is especially stable" }
        if real["3d"] == 10 || real["4d"] == 10 || real["5d"] == 10 { return "a completely filled d subshell is especially stable" }
        return "the s, d and f subshells are so close in energy that electrons shift between them"
    }
}

@MainActor enum FillingSelfTest {
    static func run() {
        let el = Dictionary(uniqueKeysWithValues: ElementStore.all.map { ($0.symbol, $0) })
        func fill(_ e: Element, strict: Bool = true, _ moves: [(String, Int)]) -> (FillState, [String]) {
            var s = FillState(), errors: [String] = []
            for (name, box) in moves {
                if case .refused(let why) = s.place(sub: Subshells.index(of: name)!, box: box, electrons: e.z, strictAufbau: strict) { errors.append(why) }
            }
            return (s, errors)
        }
        func autofill(_ e: Element) -> FillState {
            var s = FillState()
            while let t = s.nextTarget(electrons: e.z) { _ = s.place(sub: t.sub, box: t.box, electrons: e.z, strictAufbau: true) }
            return s
        }

        SelfTest.check(Subshells.order.prefix(8).map(\.name) == ["1s", "2s", "2p", "3s", "3p", "4s", "3d", "4p"], "filling: Aufbau order starts 1s 2s 2p 3s 3p 4s 3d 4p",
                       "\(Subshells.order.prefix(8).map(\.name))")
        SelfTest.check(Subshells.order[11...15].map(\.name) == ["6s", "4f", "5d", "6p", "7s"], "filling: later order continues 6s 4f 5d 6p 7s", "\(Subshells.order[11...15].map(\.name))")

        // each subshell obeys the rules
        let o = el["O"]!
        let (r1, e1) = fill(o, [("2s", 0)])
        SelfTest.check(e1.first?.contains("Aufbau") == true && r1.total == 0, "filling: placing 2s before 1s is full is refused (Aufbau)", "\(e1)")
        let (r2, e2) = fill(o, [("1s", 0), ("1s", 0), ("1s", 0)])
        SelfTest.check(r2.total == 2 && e2.count == 1 && e2[0].contains("Pauli"), "filling: a third electron in one orbital is refused (Pauli)", "\(e2)")
        let (r3, e3) = fill(o, [("1s", 0), ("1s", 0), ("2s", 0), ("2s", 0), ("2p", 0), ("2p", 0)])
        SelfTest.check(r3.total == 5 && e3.count == 1 && e3[0].contains("Hund"), "filling: pairing in 2p before every box has one electron is refused (Hund)", "\(e3)")
        let (r4, e4) = fill(o, [("1s", 0), ("1s", 0), ("2s", 0), ("2s", 0), ("2p", 0), ("2p", 1), ("2p", 2), ("2p", 0)])
        SelfTest.check(e4.isEmpty && r4.total == 8 && r4.verdict(for: o).matchesActual, "filling: oxygen built by hand passes every rule and matches 1s² 2s² 2p⁴", "\(e4) \(r4.verdict(for: o).message)")
        let (r5, e5) = fill(o, [("1s", 0), ("1s", 0), ("2s", 0), ("2s", 0), ("2p", 0), ("2p", 1), ("2p", 2), ("2p", 0), ("2p", 1)])
        SelfTest.check(r5.total == 8 && e5.last?.contains("already placed") == true, "filling: no more electrons than the element has")

        // the helper that plays the correct next move reproduces the data for ordinary elements
        let ordinary = ["H", "He", "C", "N", "O", "Ne", "Na", "Si", "Cl", "Ar", "K", "Ca", "Sc", "Fe", "Zn", "Br", "Kr", "Sr", "Sn", "Xe", "Ba", "Pb", "Rn"]
        let bad = ordinary.filter { autofill(el[$0]!).verdict(for: el[$0]!).matchesActual == false }
        SelfTest.check(bad.isEmpty, "filling: following the rules reproduces the measured configuration of 23 ordinary elements", "\(bad)")

        // exceptions: strict Aufbau gives the wrong answer, relaxing it can build the real one
        let cr = el["Cr"]!
        let strictCr = autofill(cr)
        SelfTest.check(strictCr.configuration == Subshells.aufbau(24) && !strictCr.verdict(for: cr).matchesActual && strictCr.verdict(for: cr).message.contains("exception"),
                       "filling: chromium by strict Aufbau (4s² 3d⁴) is flagged as the textbook answer, not the real one", strictCr.verdict(for: cr).message)
        var s = FillState()
        let moves: [(String, Int)] = [("1s", 0), ("1s", 0), ("2s", 0), ("2s", 0), ("2p", 0), ("2p", 1), ("2p", 2), ("2p", 0), ("2p", 1), ("2p", 2),
                                      ("3s", 0), ("3s", 0), ("3p", 0), ("3p", 1), ("3p", 2), ("3p", 0), ("3p", 1), ("3p", 2), ("4s", 0),
                                      ("3d", 0), ("3d", 1), ("3d", 2), ("3d", 3), ("3d", 4)]
        var refused = 0
        for (n, b) in moves { if case .refused = s.place(sub: Subshells.index(of: n)!, box: b, electrons: 24, strictAufbau: false) { refused += 1 } }
        SelfTest.check(refused == 0 && s.verdict(for: cr).matchesActual && s.verdict(for: cr).message.contains("half-filled"),
                       "filling: with strict Aufbau off, real chromium (4s¹ 3d⁵) is accepted and explained", "\(refused) \(s.verdict(for: cr).message)")
        let cu = el["Cu"]!
        SelfTest.check(FillState.reason(for: cu).contains("completely filled"), "filling: copper's exception is explained as a full d subshell")
        let exceptions = ElementStore.all.filter { Subshells.aufbau($0.z) != Subshells.actual($0) }.map(\.symbol)
        SelfTest.check(["Cr", "Cu", "Nb", "Mo", "Ru", "Rh", "Pd", "Ag", "La", "Ce", "Gd", "Pt", "Au", "Th", "U"].allSatisfy(exceptions.contains) && !exceptions.contains("Fe") && !exceptions.contains("O"),
                       "filling: the known exceptions (Cr, Cu, Pd, Au, …) are detected from the data, ordinary elements are not", "\(exceptions)")

        var rm = FillState()
        _ = rm.place(sub: 0, box: 0, electrons: 2, strictAufbau: true)
        SelfTest.check(rm.remove(sub: 0, box: 0) && rm.total == 0 && !rm.remove(sub: 0, box: 0), "filling: electrons can be removed, and an empty box cannot go negative")
    }
}
