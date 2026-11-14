import Foundation

/// "Export all notes": what gets written where. One Markdown file per note, with the note's regular
/// files copied next to it. Pure; the writing and copying is `NoteExporter`.
enum NoteExport {
    struct Subtask: Equatable, Sendable {
        var title: String
        var done: Bool
    }

    struct Attachment: Equatable, Sendable {
        enum Kind: Equatable, Sendable { case file, folder, missing }
        var name: String
        /// Absolute path.
        var path: String
        var kind: Kind
    }

    struct Note: Equatable, Sendable {
        var title: String
        var details: String = ""
        var createdAt: Date
        var isCompleted = false
        var subtasks: [Subtask] = []
        var attachments: [Attachment] = []
    }

    struct Copy: Equatable, Sendable {
        /// Absolute path of the attached file.
        var from: String
        /// Path inside the export folder.
        var to: String
    }

    struct Planned: Equatable, Sendable {
        /// The note's file name without ".md"; also its folder under `attachments/`.
        var fileName: String
        var markdown: String
        var copies: [Copy]
    }

    static let attachmentsFolder = "attachments"
    private static let maxNameLength = 80

    /// "Bunny export 2026-11-13 1405".
    static func folderName(at date: Date, timeZone: TimeZone = .current) -> String {
        "Bunny export \(format(date, "yyyy-MM-dd HHmm", timeZone))"
    }

    /// A title as a file name: no path separators, colons or line breaks, no leading dots, at most
    /// 80 characters; "Untitled" when nothing is left.
    static func sanitisedFileName(_ title: String) -> String {
        let cleaned = String(title.map { character -> Character in
            character == "/" || character == ":" || character == "\\" || character.isNewline
                || character.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) ? " " : character
        })
        var name = cleaned.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        name = String(name.drop { $0 == "." || $0 == " " })
        name = String(name.prefix(maxNameLength)).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Untitled" : name
    }

    /// The names with repeats numbered " 2", " 3"… (before the extension, if any). Names that differ
    /// only in case count as the same: the disk usually does not tell them apart.
    static func uniqueNames(_ names: [String]) -> [String] {
        var taken = Set<String>()
        return names.map { name in
            let ext = (name as NSString).pathExtension
            let base = ext.isEmpty ? name : (name as NSString).deletingPathExtension
            var candidate = name
            var number = 2
            while taken.contains(candidate.lowercased()) {
                candidate = ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)"
                number += 1
            }
            taken.insert(candidate.lowercased())
            return candidate
        }
    }

    /// Every note's file name, text and file copies. Regular files are copied to
    /// `attachments/<note file name>/` and linked relatively; folders and missing files are listed
    /// with their absolute path.
    static func plan(_ notes: [Note], timeZone: TimeZone = .current) -> [Planned] {
        let fileNames = uniqueNames(notes.map { sanitisedFileName($0.title) })
        return zip(notes, fileNames).map { note, fileName in
            let files = note.attachments.filter { $0.kind == .file }
            var copyNames = uniqueNames(files.map { sanitisedFileName($0.name) })[...]
            var copies: [Copy] = []
            let lines = note.attachments.map { attachment -> String in
                switch attachment.kind {
                case .folder: return "- \(attachment.name) (folder): \(attachment.path)"
                case .missing: return "- \(attachment.name) (missing): \(attachment.path)"
                case .file:
                    let path = "\(attachmentsFolder)/\(fileName)/\(copyNames.removeFirst())"
                    copies.append(Copy(from: attachment.path, to: path))
                    return "- [\(attachment.name)](\(linkEncoded(path)))"
                }
            }

            let heading = note.title.split(whereSeparator: \.isNewline).joined(separator: " ")
            var parts = [
                "# \(heading.isEmpty ? "Untitled" : heading)",
                "Created \(format(note.createdAt, "yyyy-MM-dd HH:mm", timeZone)) · \(note.isCompleted ? "completed" : "open")",
            ]
            if !note.details.isEmpty { parts.append(note.details) }
            if !note.subtasks.isEmpty {
                parts.append("## Subtasks")
                parts.append(note.subtasks.map { "- [\($0.done ? "x" : " ")] \($0.title)" }.joined(separator: "\n"))
            }
            if !lines.isEmpty {
                parts.append("## Attachments")
                parts.append(lines.joined(separator: "\n"))
            }
            return Planned(fileName: fileName, markdown: parts.joined(separator: "\n\n") + "\n", copies: copies)
        }
    }

    /// Percent-encoded for a Markdown link: spaces and parentheses would end the link early.
    private static func linkEncoded(_ path: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "()")
        return path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
    }

    private static func format(_ date: Date, _ pattern: String, _ timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
