import Testing
import Foundation
@testable import BunnyCore

struct RecentFoldersTests {
    private let workspaces = "/Users/n/Library/Application Support/Bunny/Workspaces"

    @Test func theNewestFolderComesFirst() {
        let list = RecentFolders.adding("/b", to: ["/a"])
        #expect(list == ["/b", "/a"])
    }

    @Test func aFolderUsedAgainMovesToTheFront() {
        #expect(RecentFolders.adding("/a", to: ["/c", "/b", "/a"]) == ["/a", "/c", "/b"])
        #expect(RecentFolders.adding("/a/", to: ["/b", "/a"]) == ["/a", "/b"])
    }

    @Test func theListIsCappedAtFive() {
        let list = RecentFolders.adding("/6", to: ["/5", "/4", "/3", "/2", "/1"])
        #expect(list == ["/6", "/5", "/4", "/3", "/2"])
    }

    @Test func bunnyFoldersAndBlankPathsAreNotRecorded() {
        #expect(RecentFolders.adding(workspaces + "/Codex", to: ["/a"], excluding: [workspaces]) == ["/a"])
        #expect(RecentFolders.adding(workspaces, to: ["/a"], excluding: [workspaces]) == ["/a"])
        #expect(RecentFolders.adding("  ", to: ["/a"]) == ["/a"])
        // Only a path prefix, not a string prefix.
        #expect(RecentFolders.adding(workspaces + "-old", to: [], excluding: [workspaces]) == [workspaces + "-old"])
    }

    @Test func onlyExistingFoldersAreShown() {
        #expect(RecentFolders.shown(["/a", "/gone", "/b"]) { $0 != "/gone" } == ["/a", "/b"])
    }
}
