import Foundation

/// Pure rules for shelf items: identity (dedupe) and display strings.
enum ShelfRules {
    static func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    static func isDuplicate(_ url: URL, existingPaths: [String]) -> Bool {
        let path = normalizedPath(url)
        return existingPaths.contains(path)
    }

    static func displayName(for url: URL) -> String {
        url.standardizedFileURL.lastPathComponent
    }

    static func abbreviatedParentPath(of path: String, home: String = NSHomeDirectory()) -> String {
        let parent = (path as NSString).deletingLastPathComponent
        if parent == home { return "~" }
        if parent.hasPrefix(home + "/") { return "~" + parent.dropFirst(home.count) }
        return parent
    }
}
