import AppKit

/// Borderless transparent panel under the status item that holds the list and the note side; the
/// visible glass card and its shadow are drawn by SwiftUI (`MainWindowView`). Non-activating, but can
/// become key so its text fields work. Reports losing key so the controller can close it (Maccy-style).
///
/// Clicks on fully transparent pixels never reach the window: the window server sends them to whatever
/// is underneath (`ignoresMouseEvents` is left unset for that), so Bunny loses key and closes. A click on
/// the card's faint shadow does reach it; that counts as an outside click too.
final class MainPanel: NSPanel {
    var onResignKey: (() -> Void)?
    var onOutsideClick: (() -> Void)?
    /// The visible card in window coordinates.
    var cardRect: NSRect = .zero

    init(content: NSView) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: WindowPlacement.listWidth, height: 480),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .statusBar
        hasShadow = false
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        collectionBehavior = [.moveToActiveSpace, .transient, .ignoresCycle, .fullScreenAuxiliary]
        contentView = content
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    override func sendEvent(_ event: NSEvent) {
        if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type),
           !cardRect.contains(event.locationInWindow) {
            onOutsideClick?()
            return
        }
        super.sendEvent(event)
    }
}
