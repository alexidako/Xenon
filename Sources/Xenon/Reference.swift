import SwiftUI

struct GlossaryEntry: Decodable, Identifiable, Hashable {
    let name: String
    let desc: String
    let refs: [String]
    var id: String { name }
}

struct LabTool: Decodable, Identifiable, Hashable {
    let picture: String
    let name: String
    let desc: String
    var id: String { name }
}

struct GreekLetter: Decodable, Identifiable { let upper, lower, name: String; var id: String { name } }
struct NumberRow: Decodable, Identifiable { let number, prefix, roman: String; var id: String { number } }

struct ReferenceData: Decodable {
    let uses: [String: String]
    let rphrases: [String: String]
    let sphrases: [String: String]
    let greek: [GreekLetter]
    let numbers: [NumberRow]
    let glossary: [GlossaryEntry]
    let tools: [LabTool]
}

enum ReferenceStore {
    static let data: ReferenceData? = {
        guard let url = Bundle.module.url(forResource: "reference", withExtension: "json"),
              let d = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ReferenceData.self, from: d)
    }()

    static func image(_ name: String, in folder: String) -> NSImage? {
        // Resources are flattened by SwiftPM's .process, so look in both places.
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        let url = Bundle.module.url(forResource: base, withExtension: ext, subdirectory: folder)
            ?? Bundle.module.url(forResource: base, withExtension: ext)
        return url.flatMap(NSImage.init(contentsOf:))
    }
}
