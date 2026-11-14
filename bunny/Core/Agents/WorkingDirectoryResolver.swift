import Foundation

/// Picks the folder an agent works in, and the extra folders it may read and write. Pure, Foundation-only.
///
/// Order: the folder chosen for this note; else a folder attached to the note (the first attached
/// folder, else the folder of the first attached file); else Settings' default folder, which is the
/// Bunny folder unless the user chose one. The home folder is never used, as the working folder or as
/// an extra one: an agent there could read and change everything the user owns.
enum WorkingDirectoryResolver {
    /// A note's folder choice that means "the Bunny folder" (a real choice is an absolute path).
    static let bunnyFolderChoice = "bunny"

    enum Source: Equatable, Sendable {
        case chosen, attachedFolder, attachedFile, settings
    }

    struct Resolution: Equatable, Sendable {
        var cwd: String
        var extra: [String]
        var source: Source
        /// `cwd` is Bunny's own empty folder.
        var isBunnyFolder: Bool
    }

    /// - Parameters:
    ///   - choice: the note's own choice: a path, `bunnyFolderChoice`, or nil.
    ///   - defaultFolder: Settings' folder; nil = the Bunny folder.
    ///   - bunnyFolder: the agent's own empty folder.
    ///   - exists: whether a chosen or default folder is still there (attachments are checked by the caller).
    static func resolve(choice: String?, shelf: [AgentBrief.ShelfEntry], defaultFolder: String?, bunnyFolder: String,
                        home: String, exists: (String) -> Bool = { _ in true }) -> Resolution {
        let homeKey = key(home)
        func usable(_ path: String?) -> String? {
            guard let path, !path.isEmpty, key(path) != homeKey, exists(path) else { return nil }
            return path
        }
        let attachedFolder = shelf.first { $0.isDirectory && key($0.path) != homeKey }?.path
        let attachedFile = shelf.lazy.filter { !$0.isDirectory }.map { parentDirectory(of: $0.path) }
            .first { key($0) != homeKey }

        let cwd: String
        let source: Source
        if choice == bunnyFolderChoice {
            (cwd, source) = (bunnyFolder, .chosen)
        } else if let chosen = usable(choice) {
            (cwd, source) = (chosen, .chosen)
        } else if let attachedFolder {
            (cwd, source) = (attachedFolder, .attachedFolder)
        } else if let attachedFile {
            (cwd, source) = (attachedFile, .attachedFile)
        } else {
            (cwd, source) = (usable(defaultFolder) ?? bunnyFolder, .settings)
        }

        var seen: Set<String> = [key(cwd), homeKey]
        var extra: [String] = []
        for entry in shelf {
            let candidate = entry.isDirectory ? entry.path : parentDirectory(of: entry.path)
            if seen.insert(key(candidate)).inserted { extra.append(candidate) }
        }
        return Resolution(cwd: cwd, extra: extra, source: source, isBunnyFolder: key(cwd) == key(bunnyFolder))
    }

    // MARK: - Text

    /// What the app calls the folder: "Bunny folder", or the folder's own name.
    static func name(of resolution: Resolution) -> String {
        resolution.isBunnyFolder ? "Bunny folder" : name(ofPath: resolution.cwd)
    }

    static func name(ofPath path: String) -> String {
        (key(path) as NSString).lastPathComponent
    }

    /// `path` with the home folder written as "~".
    static func abbreviated(_ path: String, home: String) -> String {
        let path = key(path), home = key(home)
        if path == home { return "~" }
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    /// The path without a trailing slash, for comparing.
    static func key(_ path: String) -> String {
        path.hasSuffix("/") && path.count > 1 ? String(path.dropLast()) : path
    }

    private static func parentDirectory(of path: String) -> String {
        (path as NSString).deletingLastPathComponent
    }
}
