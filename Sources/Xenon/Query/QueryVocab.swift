import Foundation

/// The question box is parsed in English. For other languages the question is first rewritten into the English phrasing the
/// parser knows, using the same rules as the web app (Resources/queryvocab.json, exported by web/tools/export-query-vocab.mjs).
enum QueryVocab {
    private static let rules: [String: [(NSRegularExpression, String)]] = {
        guard let url = Bundle.module.url(forResource: "queryvocab", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: [[String]]] else { return [:] }
        var out: [String: [(NSRegularExpression, String)]] = [:]
        for (lang, list) in json {
            out[lang] = list.compactMap { pair in
                guard pair.count == 2 else { return nil }
                let p = pair[0]
                let noBoundary = lang == "zh" || p.hasPrefix("(\\d") || p.hasPrefix("°") || p.hasPrefix("\\s") || p.hasPrefix(" ")
                let src = (noBoundary ? "" : "(?<![\\p{L}\\p{N}])") + p
                guard let re = try? NSRegularExpression(pattern: src, options: [.caseInsensitive]) else { return nil }
                return (re, pair[1])
            }
        }
        return out
    }()

    /// "zh-Hans" -> "zh"; the language the interface is shown in.
    static var language: String {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        return String(code.split(separator: "-").first ?? "en")
    }

    static func normalize(_ raw: String, language lang: String = QueryVocab.language) -> String {
        guard lang != "en", let list = rules[lang] else { return raw }
        var s = " " + raw.lowercased().replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "ʼ", with: "'") + " "
        if lang != "zh" {
            s = s.replacingOccurrences(of: "(\\d),(\\d)", with: "$1.$2", options: .regularExpression)
        }
        for (re, rep) in list {
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: rep)
            s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        }
        return s.trimmingCharacters(in: .whitespaces)
    }
}
