import Foundation

/// The folders hand-offs actually worked in, newest first: what the options card's Folder menu offers. Pure.
enum RecentFolders {
    static let limit = 5

    /// `list` with `path` at the front, without duplicates, at most `limit` long. A blank path, or one
    /// at or inside an `excluding` folder (Bunny's own folders), is not recorded.
    static func adding(_ path: String, to list: [String], excluding: [String] = []) -> [String] {
        let path = WorkingDirectoryResolver.key(path.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !path.isEmpty else { return list }
        for folder in excluding.map({ WorkingDirectoryResolver.key($0) }) where path == folder || path.hasPrefix(folder + "/") {
            return list
        }
        return Array(([path] + list.filter { WorkingDirectoryResolver.key($0) != path }).prefix(limit))
    }

    /// The folders that are still there.
    static func shown(_ list: [String], exists: (String) -> Bool) -> [String] {
        list.filter(exists)
    }
}
