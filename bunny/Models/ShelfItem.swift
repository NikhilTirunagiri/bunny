import Foundation
import SwiftData

@Model
final class ShelfItem {
    var id: UUID = UUID()
    var taskID: UUID = UUID()
    var bookmark: Data = Data()
    var displayName: String = ""
    var lastKnownPath: String = ""
    var isDirectory: Bool = false
    var addedAt: Date = Date()
    var sortOrder: Int = 0

    init(taskID: UUID, bookmark: Data, url: URL, isDirectory: Bool, sortOrder: Int) {
        self.taskID = taskID
        self.bookmark = bookmark
        self.displayName = ShelfRules.displayName(for: url)
        self.lastKnownPath = ShelfRules.normalizedPath(url)
        self.isDirectory = isDirectory
        self.sortOrder = sortOrder
    }
}
