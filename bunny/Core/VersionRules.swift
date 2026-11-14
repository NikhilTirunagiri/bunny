import Foundation

/// Compares version numbers like "3.0.1" for the manual update check.
enum VersionRules {
    /// The tag without surrounding spaces and a leading "v": "v3.0.1" → "3.0.1".
    static func display(_ tag: String) -> String {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.first == "v" || trimmed.first == "V" ? String(trimmed.dropFirst()) : trimmed
    }

    /// The dot-separated numbers of a version, or nil when any part is not a plain number
    /// ("beta", "3.1.0-beta").
    static func components(_ version: String) -> [Int]? {
        let parts = display(version).split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { part in part.allSatisfy(\.isASCII) && part.allSatisfy(\.isNumber) ? Int(part) : nil }
        return numbers.count == parts.count && !numbers.isEmpty ? numbers : nil
    }

    /// `candidate` is a later version than `current`. Missing parts count as 0 ("3.0" = "3.0.0").
    /// A version that is not all numbers is never newer, and nothing is newer than one.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let new = components(candidate), let old = components(current) else { return false }
        for index in 0..<max(new.count, old.count) {
            let a = index < new.count ? new[index] : 0
            let b = index < old.count ? old[index] : 0
            if a != b { return a > b }
        }
        return false
    }
}
