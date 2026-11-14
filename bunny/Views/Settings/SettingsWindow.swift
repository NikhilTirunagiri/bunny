import AppKit

/// The Settings window. A text field has focus only when the user put it there: a click in it, Tab,
/// or ⌘F for the search field.
///
/// Left alone, the window gives its first text field (the sidebar's search) focus when it becomes
/// key, and a click on a row, a control or empty space takes no focus away, so everything typed
/// went into the search.
final class SettingsWindow: NSWindow {
    /// Nothing had focus when the window opened or became key: until the user's first click or key,
    /// nothing takes it.
    private var awaitsUserInput = false

    func dropFocus() {
        makeFirstResponder(nil)
        awaitsUserInput = true
    }

    override func becomeKey() {
        if firstResponder === self { awaitsUserInput = true }
        super.becomeKey()
    }

    @discardableResult
    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        if awaitsUserInput, let responder, responder !== self { return false }
        return super.makeFirstResponder(responder)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            awaitsUserInput = false
            if isClickOutsideEditedField(event) { makeFirstResponder(nil) }
        } else if event.type == .keyDown {
            awaitsUserInput = false
        }
        super.sendEvent(event)
    }

    /// ⌘F arrives here, not through `sendEvent`.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        awaitsUserInput = false
        return super.performKeyEquivalent(with: event)
    }
}
