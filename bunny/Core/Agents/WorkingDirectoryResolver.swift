import Foundation

/// Picks the agent's working directory and extra readable/writable directories from a task's shelf. Pure, Foundation-only.
enum WorkingDirectoryResolver {
    static func resolve(shelf: [AgentBrief.ShelfEntry], defaultWorkspace: String) -> (cwd: String, extra: [String]) {
        let firstDirectory = shelf.first(where: { $0.isDirectory })
        let firstFile = shelf.first(where: { !$0.isDirectory })

        let cwd: String
        let usedFirstDirectory: Bool
        if let firstDirectory {
            cwd = firstDirectory.path
            usedFirstDirectory = true
        } else if let firstFile {
            cwd = parentDirectory(of: firstFile.path)
            usedFirstDirectory = false
        } else {
            cwd = defaultWorkspace
            usedFirstDirectory = false
        }

        var seen: Set<String> = [trimTrailingSlash(cwd)]
        var extra: [String] = []
        var skippedUsedFile = false

        for entry in shelf {
            if usedFirstDirectory, let firstDirectory, entry == firstDirectory {
                continue
            }
            if !usedFirstDirectory, !skippedUsedFile, let firstFile, entry == firstFile {
                skippedUsedFile = true
                continue
            }

            let candidate = entry.isDirectory ? entry.path : parentDirectory(of: entry.path)
            let key = trimTrailingSlash(candidate)
            if seen.contains(key) { continue }
            seen.insert(key)
            extra.append(candidate)
        }

        return (cwd, extra)
    }

    private static func parentDirectory(of path: String) -> String {
        (path as NSString).deletingLastPathComponent
    }

    private static func trimTrailingSlash(_ path: String) -> String {
        path.hasSuffix("/") && path.count > 1 ? String(path.dropLast()) : path
    }
}
