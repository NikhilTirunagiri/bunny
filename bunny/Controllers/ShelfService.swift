import Foundation
import SwiftData

@MainActor
enum ShelfService {
    static func items(for taskID: UUID, in context: ModelContext) -> [ShelfItem] {
        let descriptor = FetchDescriptor<ShelfItem>(
            predicate: #Predicate { $0.taskID == taskID },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.addedAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    static func containsPath(_ url: URL, taskID: UUID, in context: ModelContext) -> Bool {
        ShelfRules.isDuplicate(url, existingPaths: items(for: taskID, in: context).map(\.lastKnownPath))
    }

    /// Links each file URL to the task. Skips duplicates and URLs that can't be bookmarked. Returns how many were added.
    @discardableResult
    static func add(_ urls: [URL], to taskID: UUID, in context: ModelContext) -> Int {
        var existing = items(for: taskID, in: context)
        var added = 0
        for url in urls where url.isFileURL {
            guard !ShelfRules.isDuplicate(url, existingPaths: existing.map(\.lastKnownPath)),
                  let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            else { continue }
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let item = ShelfItem(taskID: taskID, bookmark: data, url: url, isDirectory: isDir,
                                 sortOrder: (existing.map(\.sortOrder).max() ?? -1) + 1)
            context.insert(item)
            existing.append(item)
            added += 1
        }
        return added
    }

    /// Resolves the bookmark. Returns nil when the file is gone. Refreshes stale bookmarks and cached path/name.
    static func resolve(_ item: ShelfItem) -> URL? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: item.bookmark, options: [.withoutUI, .withoutMounting],
                                 relativeTo: nil, bookmarkDataIsStale: &stale),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        let path = ShelfRules.normalizedPath(url)
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            item.bookmark = fresh
        }
        if item.lastKnownPath != path {
            item.lastKnownPath = path
            item.displayName = ShelfRules.displayName(for: url)
        }
        return url
    }

    static func remove(_ item: ShelfItem, in context: ModelContext) {
        context.delete(item)
    }

    static func removeAll(for taskID: UUID, in context: ModelContext) {
        for item in items(for: taskID, in: context) { context.delete(item) }
    }
}
