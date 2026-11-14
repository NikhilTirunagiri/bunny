import Foundation
import Testing
@testable import BunnyCore

struct NoteExportTests {
    private let utc = TimeZone(identifier: "UTC")!
    private let created = Date(timeIntervalSince1970: 1_700_000_000)   // 2023-11-14 22:13 UTC

    // MARK: - File names

    @Test func sanitisedNames() {
        #expect(NoteExport.sanitisedFileName("Draft the report") == "Draft the report")
        #expect(NoteExport.sanitisedFileName("a/b:c\\d") == "a b c d")
        #expect(NoteExport.sanitisedFileName("  line one\nline two\t ") == "line one line two")
        #expect(NoteExport.sanitisedFileName("...hidden") == "hidden")
        #expect(NoteExport.sanitisedFileName("") == "Untitled")
        #expect(NoteExport.sanitisedFileName(" / : ") == "Untitled")
        #expect(NoteExport.sanitisedFileName("Thème été") == "Thème été")
    }

    @Test func longNamesAreCut() {
        let name = NoteExport.sanitisedFileName(String(repeating: "word ", count: 60))
        #expect(name.count <= 80)
        #expect(!name.hasSuffix(" "))
    }

    @Test func duplicatesAreNumbered() {
        #expect(NoteExport.uniqueNames(["Note", "note", "Other", "Note"]) == ["Note", "note 2", "Other", "Note 3"])
        // A number that is already taken is skipped.
        #expect(NoteExport.uniqueNames(["A", "A 2", "A"]) == ["A", "A 2", "A 3"])
    }

    @Test func duplicateFileNamesKeepTheirExtension() {
        #expect(NoteExport.uniqueNames(["a.png", "a.png", "A.PNG", "b"]) == ["a.png", "a 2.png", "A 3.PNG", "b"])
    }

    @Test func folderName() {
        #expect(NoteExport.folderName(at: created, timeZone: utc) == "Bunny export 2023-11-14 2213")
    }

    // MARK: - Markdown

    @Test func minimalNote() {
        let planned = NoteExport.plan([.init(title: "Buy milk", createdAt: created)], timeZone: utc)
        #expect(planned.count == 1)
        #expect(planned[0].fileName == "Buy milk")
        #expect(planned[0].copies.isEmpty)
        #expect(planned[0].markdown == """
            # Buy milk

            Created 2023-11-14 22:13 · open

            """)
    }

    @Test func fullNote() {
        let note = NoteExport.Note(
            title: "Plan: launch/2", details: "Keep it short.\nTwo pages.", createdAt: created, isCompleted: true,
            subtasks: [.init(title: "Pick a date", done: true), .init(title: "Write it", done: false)],
            attachments: [
                .init(name: "photo (1).png", path: "/files/photo (1).png", kind: .file),
                .init(name: "Charts", path: "/files/Charts", kind: .folder),
                .init(name: "gone.xlsx", path: "/files/gone.xlsx", kind: .missing),
                .init(name: "photo (1).png", path: "/other/photo (1).png", kind: .file),
            ])
        let planned = NoteExport.plan([note], timeZone: utc)[0]
        #expect(planned.fileName == "Plan launch 2")
        #expect(planned.copies == [
            .init(from: "/files/photo (1).png", to: "attachments/Plan launch 2/photo (1).png"),
            .init(from: "/other/photo (1).png", to: "attachments/Plan launch 2/photo (1) 2.png"),
        ])
        #expect(planned.markdown == """
            # Plan: launch/2

            Created 2023-11-14 22:13 · completed

            Keep it short.
            Two pages.

            ## Subtasks

            - [x] Pick a date
            - [ ] Write it

            ## Attachments

            - [photo (1).png](attachments/Plan%20launch%202/photo%20%281%29.png)
            - Charts (folder): /files/Charts
            - gone.xlsx (missing): /files/gone.xlsx
            - [photo (1).png](attachments/Plan%20launch%202/photo%20%281%29%202.png)

            """)
    }

    @Test func notesWithTheSameTitleGetTheirOwnFilesAndFolders() {
        let notes = [
            NoteExport.Note(title: "Idea", createdAt: created, attachments: [.init(name: "a.txt", path: "/1/a.txt", kind: .file)]),
            NoteExport.Note(title: "Idea", createdAt: created, attachments: [.init(name: "a.txt", path: "/2/a.txt", kind: .file)]),
            NoteExport.Note(title: "", createdAt: created),
        ]
        let planned = NoteExport.plan(notes, timeZone: utc)
        #expect(planned.map(\.fileName) == ["Idea", "Idea 2", "Untitled"])
        #expect(planned[1].copies == [.init(from: "/2/a.txt", to: "attachments/Idea 2/a.txt")])
        #expect(planned[2].markdown.hasPrefix("# Untitled\n"))
    }

    @Test func headingIsOneLine() {
        let planned = NoteExport.plan([.init(title: "one\ntwo", createdAt: created)], timeZone: utc)
        #expect(planned[0].markdown.hasPrefix("# one two\n"))
    }
}
