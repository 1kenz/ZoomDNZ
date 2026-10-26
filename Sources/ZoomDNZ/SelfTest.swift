#if DEBUG
import AppKit

/// Dependency-free checks, run with `./test.sh` (debug builds only, never shipped in release).
/// XCTest and Swift Testing macros are unavailable with the Command Line Tools alone, so the
/// checks run in-process via `ZoomDNZ --self-test` and report through the exit code.
enum SelfTest {
    private static var failures: [String] = []
    private static var count = 0

    private static func check(_ ok: Bool, _ name: String) {
        count += 1
        if !ok { failures.append(name) }
        print(ok ? "  PASS  \(name)" : "  FAIL  \(name)")
    }

    static func run() -> Int32 {
        annotationChecks()
        storageChecks()
        localizationChecks()
        print("\n\(count - failures.count)/\(count) checks passed")
        return failures.isEmpty ? 0 : 1
    }

    // MARK: - Annotation

    private static func annotationChecks() {
        print("Annotation")
        let a = Annotation(tool: .rect, points: [CGPoint(x: 50, y: 80), CGPoint(x: 10, y: 20)],
                           color: .red, width: 2)
        check(a.rect == CGRect(x: 10, y: 20, width: 40, height: 60), "rect is normalized regardless of drag direction")

        var b = Annotation(tool: .pen, points: [CGPoint(x: 1, y: 2), CGPoint(x: 3, y: 4)], color: .red, width: 2)
        b.translate(by: CGPoint(x: 10, y: -1))
        check(b.points == [CGPoint(x: 11, y: 1), CGPoint(x: 13, y: 3)], "translate moves every point")

        check(Annotation(tool: .line, color: .red, width: 2).rect == .zero, "empty annotation has zero rect")
    }

    // MARK: - Storage

    private static func storageChecks() {
        print("Storage")
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zoomdnz-selftest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let first = try Storage.savePNG(Data([1]), in: dir)
            let perms = try FileManager.default.attributesOfItem(atPath: first.path)[.posixPermissions] as? Int
            check(perms == 0o600, "saved file is owner-only (0600)")

            let second = try Storage.savePNG(Data([2]), in: dir)
            check(first != second, "two saves in the same second use different names")
            check((try? Data(contentsOf: first)) == Data([1]) && (try? Data(contentsOf: second)) == Data([2]),
                  "second save does not overwrite the first")
        } catch {
            check(false, "storage setup/save failed: \(error.localizedDescription)")
        }
        let missing = dir.appendingPathComponent("does-not-exist", isDirectory: true)
        check((try? Storage.savePNG(Data([1]), in: missing)) == nil, "saving into a missing directory throws")
    }

    // MARK: - Localization

    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static func strings(_ lang: String) -> [String: String]? {
        NSDictionary(contentsOf: root.appendingPathComponent("Resources/\(lang).lproj/Localizable.strings"))
            as? [String: String]
    }

    private static func localizationChecks() {
        print("Localization")
        guard let en = strings("en") else { check(false, "en Localizable.strings is readable"); return }
        for lang in ["tr", "de"] {
            guard let other = strings(lang) else { check(false, "\(lang) Localizable.strings is readable"); continue }
            check(Set(other.keys) == Set(en.keys), "\(lang) defines the same keys as English")
            let mismatched = en.filter { $0.value.components(separatedBy: "%").count
                != other[$0.key]?.components(separatedBy: "%").count }.keys
            check(mismatched.isEmpty, "\(lang) format placeholders match English \(mismatched.sorted())")
        }

        let sources = root.appendingPathComponent("Sources/ZoomDNZ")
        let files = ((try? FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "swift" }
        var used = Set<String>()
        if let regex = try? NSRegularExpression(pattern: #"\bL\("((?:[^"\\]|\\.)*)"\)"#) {
            for file in files {
                guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
                for m in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                    if let r = Range(m.range(at: 1), in: text) { used.insert(String(text[r])) }
                }
            }
        }
        let missing = used.subtracting(Set(en.keys))
        check(!used.isEmpty && missing.isEmpty, "every L(\"…\") key used in source is translated \(missing.sorted())")
    }
}
#endif
