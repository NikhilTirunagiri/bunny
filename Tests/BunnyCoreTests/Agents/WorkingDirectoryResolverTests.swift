import Testing
import Foundation
@testable import BunnyCore

struct WorkingDirectoryResolverTests {
    @Test func resolverPrefersFolder() {
        let shelf = [
            AgentBrief.ShelfEntry(path: "/Users/n/notes.md", isDirectory: false),
            AgentBrief.ShelfEntry(path: "/Users/n/code/app", isDirectory: true),
        ]
        let result = WorkingDirectoryResolver.resolve(shelf: shelf, defaultWorkspace: "~")
        #expect(result.cwd == "/Users/n/code/app")
    }

    @Test func resolverFallsBackToFileParent() {
        let shelf = [
            AgentBrief.ShelfEntry(path: "/Users/n/code/app/notes.md", isDirectory: false),
        ]
        let result = WorkingDirectoryResolver.resolve(shelf: shelf, defaultWorkspace: "~")
        #expect(result.cwd == "/Users/n/code/app")
        #expect(result.extra.isEmpty)
    }

    @Test func resolverFallsBackToDefault() {
        let result = WorkingDirectoryResolver.resolve(shelf: [], defaultWorkspace: "~")
        #expect(result.cwd == "~")
        #expect(result.extra.isEmpty)
    }

    @Test func resolverExtraDirsDedupedAndExcludeCwd() {
        let shelf = [
            AgentBrief.ShelfEntry(path: "/Users/n/code/app", isDirectory: true),
            AgentBrief.ShelfEntry(path: "/Users/n/code/app/a.md", isDirectory: false),
            AgentBrief.ShelfEntry(path: "/Users/n/code/app/b.md", isDirectory: false),
            AgentBrief.ShelfEntry(path: "/Users/n/other", isDirectory: true),
        ]
        let result = WorkingDirectoryResolver.resolve(shelf: shelf, defaultWorkspace: "~")
        #expect(result.cwd == "/Users/n/code/app")
        #expect(result.extra == ["/Users/n/other"])
    }

    @Test func resolverTrimsTrailingSlashWhenComparing() {
        let shelf = [
            AgentBrief.ShelfEntry(path: "/Users/n/code/app/", isDirectory: true),
            AgentBrief.ShelfEntry(path: "/Users/n/code/app", isDirectory: true),
        ]
        let result = WorkingDirectoryResolver.resolve(shelf: shelf, defaultWorkspace: "~")
        #expect(result.cwd == "/Users/n/code/app/")
        #expect(result.extra.isEmpty)
    }
}
