import Foundation

/// Pure rules for the global shortcut: which key chords are allowed, and how one is written
/// ("⌃⌥B"). Registering it with the system is `GlobalHotKey`.
enum HotKeyRules {
    struct Modifiers: OptionSet, Equatable, Sendable {
        let rawValue: Int
        static let control = Modifiers(rawValue: 1)
        static let option = Modifiers(rawValue: 2)
        static let shift = Modifiers(rawValue: 4)
        static let command = Modifiers(rawValue: 8)
    }

    struct Chord: Equatable, Sendable {
        /// The hardware key code (what the system registers).
        var keyCode: Int
        var modifiers: Modifiers
        /// What the key types without modifiers on the keyboard layout it was recorded with ("b").
        var key: String
    }

    enum Rejection: Equatable {
        case needsModifier, reserved

        var message: String {
            switch self {
            case .needsModifier: return "Include ⌘, ⌥ or ⌃ in the shortcut."
            case .reserved: return "macOS uses that shortcut. Pick another."
            }
        }
    }

    private static let tab = 48
    private static let space = 49

    /// Why the chord can't be the global shortcut, or nil when it can. It needs ⌘, ⌥ or ⌃, and must
    /// not be one the system plainly owns: ⌘Q, ⌘W, ⌘Space, ⌘Tab (and ⇧⌘Tab).
    static func rejection(for chord: Chord) -> Rejection? {
        guard !chord.modifiers.isDisjoint(with: [.command, .option, .control]) else { return .needsModifier }
        if chord.modifiers == .command {
            if ["q", "w"].contains(chord.key.lowercased()) || chord.keyCode == space { return .reserved }
        }
        if chord.keyCode == tab, chord.modifiers.subtracting(.shift) == .command { return .reserved }
        return nil
    }

    /// "⌃⌥⇧⌘B": modifiers in the system's order, then the key.
    static func display(_ chord: Chord) -> String {
        var text = ""
        if chord.modifiers.contains(.control) { text += "⌃" }
        if chord.modifiers.contains(.option) { text += "⌥" }
        if chord.modifiers.contains(.shift) { text += "⇧" }
        if chord.modifiers.contains(.command) { text += "⌘" }
        return text + keyName(keyCode: chord.keyCode, key: chord.key)
    }

    private static let namedKeys: [Int: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 76: "⌅", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    /// The key's label: a symbol or name for keys that type nothing visible, else its character.
    static func keyName(keyCode: Int, key: String) -> String {
        if let name = namedKeys[keyCode] { return name }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Key \(keyCode)" : trimmed.uppercased()
    }
}
