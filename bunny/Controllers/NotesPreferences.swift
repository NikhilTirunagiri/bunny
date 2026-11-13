import Foundation

/// UserDefaults keys for the notes lifecycle (auto-archive, Trash). Settings UI comes later and reuses these.
enum NotesPreferences {
    /// "midnight" (default), "24h" or "never".
    static let autoArchiveKey = "notes.autoArchive"
    /// Days a note stays in Trash; 0 = never purged. Default 30.
    static let trashRetentionDaysKey = "trash.retentionDays"
    /// Ask before Delete Forever / Empty Trash. Default true.
    static let confirmDeleteForeverKey = "trash.confirmDeleteForever"

    static var autoArchive: TrashRules.AutoArchivePolicy {
        switch UserDefaults.standard.string(forKey: autoArchiveKey) {
        case "24h": return .after24Hours
        case "never": return .never
        default: return .atMidnight
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
