import AppKit
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
    /// `owned`: the files are Bunny's own stored copies (`storeImage`).
    @discardableResult
    static func add(_ urls: [URL], to taskID: UUID, in context: ModelContext, owned: Bool = false) -> Int {
        var existing = items(for: taskID, in: context)
        var added = 0
        for url in urls where url.isFileURL {
            guard !ShelfRules.isDuplicate(url, existingPaths: existing.map(\.lastKnownPath)),
                  let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            else { continue }
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let item = ShelfItem(taskID: taskID, bookmark: data, url: url, isDirectory: isDir,
                                 sortOrder: (existing.map(\.sortOrder).max() ?? -1) + 1, isOwned: owned)
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

    /// Removes the attachment. A stored copy's file goes with it; a linked file is never touched.
    static func remove(_ item: ShelfItem, in context: ModelContext) {
        if item.isOwned, AttachmentRules.isStored(path: item.lastKnownPath, applicationSupport: applicationSupport) {
            try? FileManager.default.removeItem(atPath: item.lastKnownPath)
            removeFolderIfEmpty(URL(fileURLWithPath: item.lastKnownPath).deletingLastPathComponent())
        }
        AttachmentThumbnails.drop(item.id)
        context.delete(item)
    }

    /// Removes note folders under Attachments that hold no files any more (housekeeping).
    static func removeEmptyFolders() {
        let root = AttachmentRules.root(applicationSupport: applicationSupport)
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for folder in folders { removeFolderIfEmpty(folder) }
    }

    /// Only a folder with nothing in it (a stray `.DS_Store` does not count as content).
    private static func removeFolderIfEmpty(_ folder: URL) {
        guard folder.hasDirectoryPath || (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
              let contents = try? FileManager.default.contentsOfDirectory(atPath: folder.path),
              contents.allSatisfy({ $0 == ".DS_Store" }) else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    /// Removes every attachment of a note that is being deleted for good, and its folder of stored files.
    static func removeAll(for taskID: UUID, in context: ModelContext) {
        for item in items(for: taskID, in: context) {
            AttachmentThumbnails.drop(item.id)
            context.delete(item)
        }
        try? FileManager.default.removeItem(at: AttachmentRules.folder(noteID: taskID, applicationSupport: applicationSupport))
    }

    // MARK: - Clipboard

    private static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// The general pasteboard's type names: enough to tell what it offers without reading its data.
    static var clipboardTypes: [String] { NSPasteboard.general.types?.map(\.rawValue) ?? [] }

    /// Attaches what is on the clipboard: copied files are linked like dropped ones; bare image data
    /// (a screenshot) is stored as a PNG in the note's folder. Returns how many were added.
    @discardableResult
    static func attachClipboard(to taskID: UUID, in context: ModelContext) -> Int {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            return add(urls, to: taskID, in: context)
        }
        guard let png = pasteboard.data(forType: .png) ?? pngData(NSImage(pasteboard: pasteboard)) else { return 0 }
        return storeImage(png, for: taskID, in: context)
    }

    private static func pngData(_ image: NSImage?) -> Data? {
        guard let tiff = image?.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    }

    /// Writes the PNG into the note's Attachments folder and attaches it as an owned item.
    private static func storeImage(_ png: Data, for taskID: UUID, in context: ModelContext) -> Int {
        let fileManager = FileManager.default
        let folder = AttachmentRules.folder(noteID: taskID, applicationSupport: applicationSupport)
        let existing = Set((try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? [])
        let url = folder.appendingPathComponent(AttachmentRules.pastedImageName(at: Date(), existing: existing))
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: url, options: .atomic)
        } catch {
            return 0
        }
        return add([url], to: taskID, in: context, owned: true)
    }
}
