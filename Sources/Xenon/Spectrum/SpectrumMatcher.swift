import Foundation

/// Ranks elements by how well their known spectral lines explain a set of observed wavelengths.
enum SpectrumMatcher {
    struct Match: Hashable { let observed: Double; let line: Double; let intensity: Double }

    struct Candidate: Identifiable {
        let element: Element
        let matches: [Match]
        let precision: Double   // share of observed lines this element explains
        let recall: Double      // share of its (intensity-weighted) lines in the window that were observed
        var id: Int { element.z }
        var score: Double { precision + recall == 0 ? 0 : 2 * precision * recall / (precision + recall) }
    }

    /// Observed wavelengths in nm. Tolerance in nm.
    static func rank(observed: [Double], tolerance: Double, lines: [Int: [SpectrumLine]] = SpectrumStore.byElement,
                     elements: [Element] = ElementStore.all) -> [Candidate] {
        let obs = observed.filter { $0 > 0 }
        guard let lo = obs.min(), let hi = obs.max() else { return [] }
        // compare against everything the element emits in the observed window (at least the visible range)
        let windowLo = min(lo, 380) - tolerance, windowHi = max(hi, 780) + tolerance
        let byZ = Dictionary(uniqueKeysWithValues: elements.map { ($0.z, $0) })

        var out: [Candidate] = []
        for (z, all) in lines {
            guard let e = byZ[z] else { continue }
            let inWindow = all.filter { $0.nanometers >= windowLo && $0.nanometers <= windowHi }
            guard !inWindow.isEmpty else { continue }
            var matches: [Match] = []
            var explained = 0
            var matchedLines = Set<Int>()
            for o in obs {
                var best: (idx: Int, d: Double)?
                for (i, l) in inWindow.enumerated() {
                    let d = abs(l.nanometers - o)
                    if d <= tolerance, best == nil || d < best!.d { best = (i, d) }
                }
                if let b = best {
                    explained += 1; matchedLines.insert(b.idx)
                    matches.append(Match(observed: o, line: inWindow[b.idx].nanometers, intensity: inWindow[b.idx].intensity))
                }
            }
            guard explained > 0 else { continue }
            // an observed line may sit within tolerance of several element lines; count them all as "seen"
            for (i, l) in inWindow.enumerated() where obs.contains(where: { abs($0 - l.nanometers) <= tolerance }) { matchedLines.insert(i) }
            let total = inWindow.reduce(0.0) { $0 + max($1.intensity, 1) }
            let seen = matchedLines.reduce(0.0) { $0 + max(inWindow[$1].intensity, 1) }
            out.append(Candidate(element: e, matches: matches, precision: Double(explained) / Double(obs.count), recall: seen / total))
        }
        return out.sorted { $0.score != $1.score ? $0.score > $1.score : $0.element.z < $1.element.z }
    }

    /// Every element with a line within tolerance of this wavelength, nearest first.
    static func assignments(for nm: Double, tolerance: Double, lines: [Int: [SpectrumLine]] = SpectrumStore.byElement,
                            elements: [Element] = ElementStore.all) -> [(Element, Double)] {
        let byZ = Dictionary(uniqueKeysWithValues: elements.map { ($0.z, $0) })
        return lines.compactMap { z, ls -> (Element, Double)? in
            guard let e = byZ[z], let d = ls.map({ abs($0.nanometers - nm) }).min(), d <= tolerance else { return nil }
            return (e, d)
        }
        .sorted { $0.1 < $1.1 }
    }

    /// Parses "486.1, 656.3 nm" / "4861 6563" style input; returns values converted to nm.
    static func parse(_ text: String, angstrom: Bool) -> [Double] {
        let seps = CharacterSet(charactersIn: ",;\n\t ")
        return text.components(separatedBy: seps)
            .compactMap { Double($0.replacingOccurrences(of: "nm", with: "").replacingOccurrences(of: "Å", with: "")) }
            .map { angstrom ? $0 / 10 : $0 }
    }
}

enum MatcherSelfTest {
    static func run() {
        func top(_ obs: [Double], tol: Double = 1.0) -> [String] { SpectrumMatcher.rank(observed: obs, tolerance: tol).prefix(3).map(\.element.symbol) }
        let h = top([486.13, 656.28])
        SelfTest.check(h.first == "H", "hydrogen Balmer lines identify H", "\(h)")
        let he = top([587.56, 667.82, 706.52, 501.57])
        SelfTest.check(he.first == "He", "helium visible lines identify He", "\(he)")
        let na = top([589.0, 589.6])
        SelfTest.check(na.first == "Na", "sodium D doublet identifies Na", "\(na)")
        let mix = SpectrumMatcher.rank(observed: [486.13, 656.28, 587.56, 667.82], tolerance: 1.0).prefix(4).map(\.element.symbol)
        SelfTest.check(mix.contains("H") && mix.contains("He"), "H + He mixture lists both", "\(mix)")
        SelfTest.check(SpectrumMatcher.rank(observed: [], tolerance: 1).isEmpty, "empty input gives no candidates")
        SelfTest.check(SpectrumMatcher.rank(observed: [123.0], tolerance: 0.05).isEmpty, "no match outside tolerance")
        SelfTest.check(SpectrumMatcher.parse("4861, 6563", angstrom: true) == [486.1, 656.3], "parse ångström input")
        let wide = SpectrumMatcher.rank(observed: [486.13], tolerance: 0.2).first?.element.symbol
        SelfTest.check(wide != nil, "single line still ranks something", "\(String(describing: wide))")
    }
}
