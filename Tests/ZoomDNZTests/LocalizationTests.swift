import Foundation
import Testing

@Suite struct LocalizationTests {
    private static let languages = ["en", "tr", "de"]
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func strings(_ lang: String) throws -> [String: String] {
        let url = Self.root.appendingPathComponent("Resources/\(lang).lproj/Localizable.strings")
        return try #require(NSDictionary(contentsOf: url) as? [String: String], "Cannot parse \(url.path)")
    }

    @Test(arguments: ["tr", "de"])
    func languageDefinesTheSameKeysAsEnglish(lang: String) throws {
        #expect(Set(try strings(lang).keys) == Set(try strings("en").keys))
    }

    @Test func everyKeyUsedInSourceIsTranslated() throws {
        let sources = Self.root.appendingPathComponent("Sources/ZoomDNZ")
        let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        let regex = try NSRegularExpression(pattern: #"\bL\("((?:[^"\\]|\\.)*)"\)"#)
        var used = Set<String>()
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let r = Range(match.range(at: 1), in: text) { used.insert(String(text[r])) }
            }
        }
        #expect(!used.isEmpty)
        let missing = used.subtracting(Set(try strings("en").keys))
        #expect(missing.isEmpty, "Missing translations: \(missing)")
    }

    @Test(arguments: ["tr", "de"])
    func formatPlaceholdersMatchEnglish(lang: String) throws {
        let en = try strings("en")
        let other = try strings(lang)
        for (key, value) in en {
            #expect(value.components(separatedBy: "%").count == other[key]?.components(separatedBy: "%").count,
                    "Placeholder mismatch for '\(key)' in \(lang)")
        }
    }
}
