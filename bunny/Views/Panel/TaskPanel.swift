import AppKit

/// Borderless glass panel that sits beside the popover. Can become key so its text fields work.
final class TaskPanel: NSPanel {
    init(content: NSView) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: PanelPlacement.defaultWidth, height: 480),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        isMovable = false
        collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]

        let glass = NSGlassEffectView()
        glass.cornerRadius = 16
        content.translatesAutoresizingMaskIntoConstraints = false
        glass.contentView = content
        // Pin the content to the glass explicitly so it always fills the panel
        // (guarded: constraints need a common ancestor or AppKit throws).
        if content.isDescendant(of: glass) {
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
                content.topAnchor.constraint(equalTo: glass.topAnchor),
                content.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
            ])
        }
        contentView = glass
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
