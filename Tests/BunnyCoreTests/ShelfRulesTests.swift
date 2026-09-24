import Testing
import Foundation
@testable import BunnyCore

struct ShelfRulesTests {
    @Test func duplicateSamePath() {
        let url = URL(fileURLWithPath: "/tmp/x/../x/file.txt")
        #expect(ShelfRules.isDuplicate(url, existingPaths: [ShelfRules.normalizedPath(URL(fileURLWithPath: "/tmp/x/file.txt"))]))
    }

    @Test func duplicateViaSymlink() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let real = dir.appendingPathComponent("real.txt")
        try "x".write(to: real, atomically: true, encoding: .utf8)
        let link = dir.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        #expect(ShelfRules.isDuplicate(link, existingPaths: [ShelfRules.normalizedPath(real)]))
    }

    @Test func differentFileIsNotDuplicate() {
        #expect(!ShelfRules.isDuplicate(URL(fileURLWithPath: "/tmp/a"), existingPaths: ["/tmp/b"]))
    }

    @Test func displayNameIsLastComponent() {
        #expect(ShelfRules.displayName(for: URL(fileURLWithPath: "/Users/n/Code/bunny/")) == "bunny")
    }

    @Test func abbreviatesHome() {
        #expect(ShelfRules.abbreviatedParentPath(of: "/Users/n/Code/bunny/README.md", home: "/Users/n") == "~/Code/bunny")
        #expect(ShelfRules.abbreviatedParentPath(of: "/Volumes/X/a.txt", home: "/Users/n") == "/Volumes/X")
        #expect(ShelfRules.abbreviatedParentPath(of: "/Users/n/a.txt", home: "/Users/n") == "~")
    }
}
