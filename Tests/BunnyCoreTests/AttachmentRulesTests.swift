import Foundation
import Testing
@testable import BunnyCore

struct AttachmentRulesTests {
    private let support = URL(fileURLWithPath: "/Users/n/Library/Application Support", isDirectory: true)
    private let noteID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    // MARK: - Paths

    @Test func folderIsPerNoteUnderAttachments() {
        let folder = AttachmentRules.folder(noteID: noteID, applicationSupport: support)
        #expect(folder.path == "/Users/n/Library/Application Support/Bunny/Attachments/11111111-2222-3333-4444-555555555555")
    }

    @Test func onlyPathsInsideTheAttachmentsFolderAreStored() {
        let inside = AttachmentRules.folder(noteID: noteID, applicationSupport: support).appendingPathComponent("a.png").path
        #expect(AttachmentRules.isStored(path: inside, applicationSupport: support))
        #expect(!AttachmentRules.isStored(path: "/Users/n/Desktop/a.png", applicationSupport: support))
        #expect(!AttachmentRules.isStored(path: "/Users/n/Library/Application Support/Bunny/Attachments-old/a.png",
                                          applicationSupport: support))
        #expect(!AttachmentRules.isStored(path: "/Users/n/Library/Application Support/Bunny/Attachments",
                                          applicationSupport: support))
    }

    // MARK: - Names

    private var utc: TimeZone { TimeZone(identifier: "UTC")! }
    /// 2026-11-13 14:05:09 UTC.
    private var date: Date { Date(timeIntervalSince1970: 1_794_578_709) }

    @Test func pastedImageNameCarriesTheTime() {
        #expect(AttachmentRules.pastedImageName(at: date, existing: [], timeZone: utc)
                == "Pasted image 2026-11-13 at 14.05.09.png")
    }

    @Test func pastedImageNameAvoidsExistingNames() {
        let first = "Pasted image 2026-11-13 at 14.05.09.png"
        #expect(AttachmentRules.pastedImageName(at: date, existing: [first], timeZone: utc)
                == "Pasted image 2026-11-13 at 14.05.09 2.png")
        #expect(AttachmentRules.pastedImageName(at: date, existing: [first, "Pasted image 2026-11-13 at 14.05.09 2.png"],
                                                timeZone: utc)
                == "Pasted image 2026-11-13 at 14.05.09 3.png")
    }

    // MARK: - Clipboard

    @Test func fileURLOnTheClipboardIsAFile() {
        // What Finder puts there for a copied file: the URL, its name as text, and icons.
        let finder = ["public.file-url", "public.utf8-plain-text", "com.apple.icns", "public.tiff"]
        #expect(AttachmentRules.clipboardKind(types: finder) == .file)
    }

    @Test func imageDataOnTheClipboardIsAnImage() {
        #expect(AttachmentRules.clipboardKind(types: ["public.png"]) == .image)
        #expect(AttachmentRules.clipboardKind(types: ["public.tiff", "NeXT TIFF v4.0 pasteboard type"]) == .image)
    }

    @Test func textOnTheClipboardIsNothingToAttach() {
        #expect(AttachmentRules.clipboardKind(types: ["public.utf8-plain-text", "NSStringPboardType"]) == nil)
        #expect(AttachmentRules.clipboardKind(types: []) == nil)
    }

    @Test func editorAttachesFilesAndTextlessImagesOnly() {
        #expect(AttachmentRules.attachesInEditor(types: ["public.png", "public.tiff"]))
        // A copied file's text is only its name.
        #expect(AttachmentRules.attachesInEditor(types: ["public.file-url", "public.utf8-plain-text"]))
        // Text copied from a document that also offers a picture of itself: paste the text.
        #expect(!AttachmentRules.attachesInEditor(types: ["public.utf8-plain-text", "public.rtf", "public.tiff"]))
        #expect(!AttachmentRules.attachesInEditor(types: ["public.html", "public.png"]))
        #expect(!AttachmentRules.attachesInEditor(types: ["public.utf8-plain-text"]))
    }

    @Test func offerLabels() {
        #expect(AttachmentRules.offerLabel(.image) == "Attach the copied screenshot")
        #expect(AttachmentRules.offerLabel(.file) == "Attach the copied file")
    }
}
