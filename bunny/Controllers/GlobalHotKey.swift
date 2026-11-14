import AppKit
import Carbon.HIToolbox

/// The user-chosen system-wide shortcut that opens Bunny (Settings → General). Registered with
/// Carbon's `RegisterEventHotKey`, which needs no privacy permission. Unset by default; the chord
/// lives in UserDefaults (`hotkey.*`). What may be a chord is `HotKeyRules`.
@MainActor
final class GlobalHotKey {
    static let shared = GlobalHotKey()
    private init() {}

    private enum Key {
        static let keyCode = "hotkey.keyCode"
        static let modifiers = "hotkey.modifiers"
        static let key = "hotkey.key"
    }

    /// Runs on the main thread each time the shortcut is pressed.
    var onPress: (() -> Void)?
    private var hotKey: EventHotKeyRef?
    private var handlerInstalled = false

    /// The stored chord, or nil when no shortcut is set.
    static var chord: HotKeyRules.Chord? {
        let defaults = UserDefaults.standard
        guard let keyCode = defaults.object(forKey: Key.keyCode) as? Int else { return nil }
        return HotKeyRules.Chord(keyCode: keyCode,
                                 modifiers: HotKeyRules.Modifiers(rawValue: defaults.integer(forKey: Key.modifiers)),
                                 key: defaults.string(forKey: Key.key) ?? "")
    }

    /// Registers `chord` and stores it; nil removes the shortcut. False when the system refuses the
    /// chord (another app holds it): the previous shortcut then stays as it was.
    @discardableResult
    func set(_ chord: HotKeyRules.Chord?) -> Bool {
        let defaults = UserDefaults.standard
        guard let chord else {
            unregister()
            for key in [Key.keyCode, Key.modifiers, Key.key] { defaults.removeObject(forKey: key) }
            return true
        }
        guard register(chord) else {
            registerStored()
            return false
        }
        defaults.set(chord.keyCode, forKey: Key.keyCode)
        defaults.set(chord.modifiers.rawValue, forKey: Key.modifiers)
        defaults.set(chord.key, forKey: Key.key)
        return true
    }

    /// At launch, and after a recording that changed nothing.
    func registerStored() {
        guard let chord = Self.chord else {
            unregister()
            return
        }
        register(chord)
    }

    /// While a new shortcut is being recorded the old one must not fire.
    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }

    @discardableResult
    private func register(_ chord: HotKeyRules.Chord) -> Bool {
        unregister()
        guard HotKeyRules.rejection(for: chord) == nil else { return false }
        installHandler()
        var modifiers: UInt32 = 0
        if chord.modifiers.contains(.command) { modifiers |= UInt32(cmdKey) }
        if chord.modifiers.contains(.option) { modifiers |= UInt32(optionKey) }
        if chord.modifiers.contains(.control) { modifiers |= UInt32(controlKey) }
        if chord.modifiers.contains(.shift) { modifiers |= UInt32(shiftKey) }
        let id = EventHotKeyID(signature: 0x424E_4E59 /* "BNNY" */, id: 1)
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(chord.keyCode), modifiers, id, GetApplicationEventTarget(), 0, &reference)
        guard status == noErr else { return false }
        hotKey = reference
        return true
    }

    /// One handler for the app's lifetime; Bunny registers a single hot key, so every hot-key event is it.
    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { GlobalHotKey.shared.onPress?() }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
