import Testing
import Foundation
@testable import BunnyCore

struct WorkingDirectoryResolverTests {
    private let home = "/Users/n"
    private let bunny = "/Users/n/Library/Application Support/Bunny/Workspaces/Claude Code"

    private func resolve(choice: String? = nil, shelf: [AgentBrief.ShelfEntry] = [], defaultFolder: String? = nil,
                         exists: (String) -> Bool = { _ in true }) -> WorkingDirectoryResolver.Resolution {
        WorkingDirectoryResolver.resolve(choice: choice, shelf: shelf, defaultFolder: defaultFolder,
                                         bunnyFolder: bunny, home: home, exists: exists)
    }

    private func folder(_ path: String) -> AgentBrief.ShelfEntry { .init(path: path, isDirectory: true) }
    private func file(_ path: String) -> AgentBrief.ShelfEntry { .init(path: path, isDirectory: false) }

    // MARK: - Order

    @Test func theNotesChoiceWinsOverAttachmentsAndTheDefault() {
        let result = resolve(choice: "/Users/n/code/picked", shelf: [folder("/Users/n/code/app")], defaultFolder: "/Users/n/work")
        #expect(result.cwd == "/Users/n/code/picked")
        #expect(result.source == .chosen)
        #expect(!result.isBunnyFolder)
        #expect(result.extra == ["/Users/n/code/app"])
    }

    @Test func choosingTheBunnyFolderWinsOverAttachments() {
        let result = resolve(choice: WorkingDirectoryResolver.bunnyFolderChoice, shelf: [folder("/Users/n/code/app")])
        #expect(result.cwd == bunny)
        #expect(result.source == .chosen)
        #expect(result.isBunnyFolder)
    }

    @Test func anAttachedFolderWinsOverAnAttachedFile() {
        let result = resolve(shelf: [file("/Users/n/docs/notes.md"), folder("/Users/n/code/app")], defaultFolder: "/Users/n/work")
        #expect(result.cwd == "/Users/n/code/app")
        #expect(result.source == .attachedFolder)
        #expect(result.extra == ["/Users/n/docs"])
    }

    @Test func theFirstAttachedFilesFolderIsUsedWhenNoFolderIsAttached() {
        let result = resolve(shelf: [file("/Users/n/code/app/notes.md")])
        #expect(result.cwd == "/Users/n/code/app")
        #expect(result.source == .attachedFile)
        #expect(result.extra.isEmpty)
    }

    @Test func theSettingsFolderIsUsedWithNoAttachments() {
        let result = resolve(defaultFolder: "/Users/n/work")
        #expect(result.cwd == "/Users/n/work")
        #expect(result.source == .settings)
        #expect(!result.isBunnyFolder)
    }

    @Test func theBunnyFolderIsTheDefaultWhenSettingsHasNoFolder() {
        let result = resolve()
        #expect(result.cwd == bunny)
        #expect(result.source == .settings)
        #expect(result.isBunnyFolder)
    }

    // MARK: - Never the home folder

    @Test func theHomeFolderIsNeverUsed() {
        #expect(resolve(choice: "/Users/n").cwd == bunny)
        #expect(resolve(choice: "/Users/n/").cwd == bunny)
        #expect(resolve(defaultFolder: "/Users/n").cwd == bunny)
        #expect(resolve(shelf: [folder("/Users/n")]).cwd == bunny)
        // A file straight in the home folder: its parent is skipped, the next attachment is used.
        let result = resolve(shelf: [file("/Users/n/todo.txt"), file("/Users/n/code/a.md")])
        #expect(result.cwd == "/Users/n/code")
        #expect(result.extra.isEmpty)
    }

    @Test func theHomeFolderIsNeverAnExtraDirectory() {
        let result = resolve(shelf: [folder("/Users/n/code/app"), file("/Users/n/todo.txt"), folder("/Users/n")])
        #expect(result.cwd == "/Users/n/code/app")
        #expect(result.extra.isEmpty)
    }

    // MARK: - Missing folders

    @Test func aChosenFolderThatIsGoneFallsThrough() {
        let result = resolve(choice: "/Users/n/gone", shelf: [folder("/Users/n/code/app")]) { $0 != "/Users/n/gone" }
        #expect(result.cwd == "/Users/n/code/app")
        #expect(result.source == .attachedFolder)
        #expect(resolve(defaultFolder: "/Users/n/gone") { _ in false }.cwd == bunny)
    }

    // MARK: - Extra directories

    @Test func extraDirectoriesAreDedupedAndExcludeTheWorkingDirectory() {
        let shelf = [
            folder("/Users/n/code/app"),
            file("/Users/n/code/app/a.md"),
            file("/Users/n/code/app/b.md"),
            folder("/Users/n/other"),
            file("/Users/n/other/c.md"),
        ]
        let result = resolve(shelf: shelf)
        #expect(result.cwd == "/Users/n/code/app")
        #expect(result.extra == ["/Users/n/other"])
    }

    @Test func trailingSlashesAreIgnoredWhenComparing() {
        let result = resolve(shelf: [folder("/Users/n/code/app/"), folder("/Users/n/code/app")])
        #expect(result.cwd == "/Users/n/code/app/")
        #expect(result.extra.isEmpty)
    }

    // MARK: - Text

    @Test func folderNames() {
        #expect(WorkingDirectoryResolver.name(of: resolve()) == "Bunny folder")
        #expect(WorkingDirectoryResolver.name(of: resolve(choice: "/Users/n/code/app/")) == "app")
    }

    @Test func pathsUnderHomeAreAbbreviated() {
        #expect(WorkingDirectoryResolver.abbreviated("/Users/n/code/app", home: home) == "~/code/app")
        #expect(WorkingDirectoryResolver.abbreviated("/Users/n", home: home) == "~")
        #expect(WorkingDirectoryResolver.abbreviated("/Users/nikhil/code", home: home) == "/Users/nikhil/code")
        #expect(WorkingDirectoryResolver.abbreviated("/opt/work", home: home) == "/opt/work")
    }
}
