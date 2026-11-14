import Foundation

/// Pure rules for attachments: where Bunny keeps the files it stores itself (pasted images), how it
/// names them, and what the clipboard has to offer, judged from its type names alone.
enum AttachmentRules {
    // MARK: - Stored files

    /// `<applicationSupport>/Bunny/Attachments`.
    static func root(applicationSupport: URL) -> URL {
        applicationSupport
            .appendingPathComponent("Bunny", isDirectory: true)
            .appendingPathComponent("Attachments", isDirectory: true)
    }

    /// `<applicationSupport>/Bunny/Attachments/<note id>`: every file Bunny stores for one note.
    static func folder(noteID: UUID, applicationSupport: URL) -> URL {
        root(applicationSupport: applicationSupport).appendingPathComponent(noteID.uuidString, isDirectory: true)
    }

    /// The path lies inside the Attachments folder. Only such files are ever deleted with their attachment.
    static func isStored(path: String, applicationSupport: URL) -> Bool {
        path.hasPrefix(root(applicationSupport: applicationSupport).path + "/")
    }

    /// "Pasted image 2026-11-13 at 14.05.09.png"; " 2", " 3"… before the extension when the name is taken.
    static func pastedImageName(at date: Date, existing: Set<String>, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let base = "Pasted image \(formatter.string(from: date))"
        var name = "\(base).png"
        var number = 2
        while existing.contains(name) {
            name = "\(base) \(number).png"
            number += 1
        }
        return name
    }

    // MARK: - Clipboard

    enum ClipboardKind: Equatable { case file, image }

    private static let fileTypes: Set<String> = ["public.file-url"]
    private static let imageTypes: Set<String> = ["public.png", "public.tiff", "public.jpeg", "public.heic"]
    private static let textTypes: Set<String> = [
        "public.utf8-plain-text", "public.utf16-external-plain-text", "public.utf16-plain-text",
        "NSStringPboardType", "public.rtf", "public.html",
    ]

    /// What could be attached from a pasteboard with these types: a file wins over the icon or
    /// preview image that comes with it.
    static func clipboardKind(types: [String]) -> ClipboardKind? {
        if !fileTypes.isDisjoint(with: types) { return .file }
        if !imageTypes.isDisjoint(with: types) { return .image }
        return nil
    }

    /// ⌘V in the details editor attaches instead of pasting text: for a copied file (its text is
    /// only the file's name), and for an image that comes with no text at all.
    static func attachesInEditor(types: [String]) -> Bool {
        switch clipboardKind(types: types) {
        case .file: return true
        case .image: return textTypes.isDisjoint(with: types)
        case nil: return false
        }
    }

    /// The quick-capture strip's wording.
    static func offerLabel(_ kind: ClipboardKind) -> String {
        switch kind {
        case .image: return "Attach the copied screenshot"
        case .file: return "Attach the copied file"
        }
    }
}
