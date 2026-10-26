import Foundation
import Testing
@testable import ZoomDNZ

@Suite final class StorageTests {
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zoomdnz-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func savedFileIsOwnerOnly() throws {
        let url = try Storage.savePNG(Data([1, 2, 3]), in: directory)
        let perms = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(perms == 0o600)
    }

    @Test func twoSavesInTheSameSecondNeverOverwrite() throws {
        let first = try Storage.savePNG(Data([1]), in: directory)
        let second = try Storage.savePNG(Data([2]), in: directory)
        #expect(first != second)
        #expect(try Data(contentsOf: first) == Data([1]))
        #expect(try Data(contentsOf: second) == Data([2]))
    }

    @Test func saveToMissingDirectoryThrowsInsteadOfFailingSilently() {
        let missing = directory.appendingPathComponent("does-not-exist", isDirectory: true)
        #expect(throws: (any Error).self) { try Storage.savePNG(Data([1]), in: missing) }
    }
}
