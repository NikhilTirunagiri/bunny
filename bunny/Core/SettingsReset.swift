import Foundation

/// Settings → Data → Reset settings: which stored preferences go.
enum SettingsReset {
    /// The keys of `stored` (the app's own preferences domain) to remove: all of them except `keeping`.
    /// Nothing is listed by name, so a setting added later is reset too. Sorted, for a stable order.
    static func keysToRemove(from stored: [String: Any], keeping: Set<String>) -> [String] {
        stored.keys.filter { !keeping.contains($0) }.sorted()
    }
}
