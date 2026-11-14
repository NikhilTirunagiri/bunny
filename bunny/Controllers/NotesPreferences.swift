import Foundation

/// UserDefaults keys for the notes lifecycle (completed notes, Trash). Settings UI comes later and reuses these.
enum NotesPreferences {
    /// How long completed notes stay before they move to Trash: "24h" (default), "7d" or "never".
    static let completedRetentionKey = "notes.completedRetention"
    /// Days a note stays in Trash; 0 = never purged. Default 30.
    static let trashRetentionDaysKey = "trash.retentionDays"
    /// Ask before Delete Forever / Empty Trash. Default true.
    static let confirmDeleteForeverKey = "trash.confirmDeleteForever"

    static var completedRetention: TrashRules.CompletedRetention {
        switch UserDefaults.standard.string(forKey: completedRetentionKey) {
        case "7d": return .after7Days
        case "never": return .never
        default: return .after24Hours
        }
    }

    /// nil = "Never" (what `TrashRules` expects).
    static var trashRetentionDays: Int? {
        let days = UserDefaults.standard.object(forKey: trashRetentionDaysKey) as? Int ?? 30
        return days > 0 ? days : nil
    }

    static var confirmDeleteForever: Bool {
        get { UserDefaults.standard.object(forKey: confirmDeleteForeverKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: confirmDeleteForeverKey) }
    }
}
