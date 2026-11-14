import AppKit
import SwiftUI

/// The app's pop-up button: the current value at the left, a chevron at the right, and a native menu
/// on click. With a `width` the button is exactly that wide whatever the value (a system pop-up
/// button draws at its own width), so a column of them lines up. Under `popUpMenusDropDown` (the
/// Settings window) the menu drops down just below the button, and clicking the button again while it
/// is open closes it; elsewhere it opens at the pointer.
struct PopUpButton: View {
    let value: String
    var logo: AgentHarness?
    var width: CGFloat?
    let menu: () -> [PopUpMenu.Item?]

    @Environment(\.popUpMenusDropDown) private var dropDown
    @State private var anchor = PopUpMenu.Anchor()

    /// `BunnyButtonStyle`'s text padding, each side.
    private static let padding: CGFloat = 9

    var body: some View {
        Button {
            if dropDown { PopUpMenu.show(menu(), below: anchor) } else { PopUpMenu.show(menu()) }
        } label: {
            HStack(spacing: 5) {
                if let logo { AgentLogo(harness: logo, size: 12) }
                Text(value)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if width != nil { Spacer(minLength: 0) }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(BunnyTheme.secondary)
            }
            .frame(width: width.map { $0 - 2 * Self.padding })
        }
        .buttonStyle(.bunny)
        .background { if dropDown { PopUpMenu.AnchorView(anchor: anchor) } }
    }
}

extension EnvironmentValues {
    /// `PopUpButton`s drop their menu down below themselves instead of opening it at the pointer.
    @Entry var popUpMenusDropDown = false
}

extension PopUpButton {
    /// One choice of a selection; `nil` in the list is a separator.
    struct Option<Value> {
        var value: Value
        var title: String
        var enabled = true
        /// An agent's logo, shown beside the title in the button and in the menu.
        var logo: AgentHarness?
    }

    /// A picker: shows the selected option's title, ticks it in the menu, and writes a pick to `selection`.
    init<Value: Equatable>(selection: Binding<Value>, options: [Option<Value>?], width: CGFloat? = nil) {
        let current = selection.wrappedValue
        let selected = options.compactMap { $0 }.first { $0.value == current }
        self.init(value: selected?.title ?? "", logo: selected?.logo, width: width) {
            options.map { option in
                option.map { option in
                    var item = PopUpMenu.Item(title: option.title, checked: option.value == current, enabled: option.enabled) {
                        selection.wrappedValue = option.value
                    }
                    item.logo = option.logo
                    return item
                }
            }
        }
    }
}

/// A native menu built when it opens (it can't be rebuilt underneath by a SwiftUI re-render), shown
/// below its button's anchor or else at the pointer. `nil` entries are separators.
@MainActor
enum PopUpMenu {
    struct Item {
        var title: String
        var subtitle: String?
        var checked = false
        var enabled = true
        var logo: AgentHarness?
        var action: (() -> Void)?

        init(title: String, subtitle: String? = nil, checked: Bool = false, enabled: Bool = true,
             action: (() -> Void)? = nil) {
            self.title = title
            self.subtitle = subtitle
            self.checked = checked
            self.enabled = enabled
            self.action = action
        }
    }

    /// The AppKit view behind a `PopUpButton`, and when its menu last closed.
    final class Anchor {
        weak var view: NSView?
        /// System uptime when this button's menu last closed.
        var closedAt: TimeInterval = 0
        /// The mouse-up of the click that closed the menu, when that click began on the button.
        var closingMouseUp: Int?
    }

    struct AnchorView: NSViewRepresentable {
        let anchor: Anchor
        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            anchor.view = view
            return view
        }
        func updateNSView(_ view: NSView, context: Context) { anchor.view = view }
    }

    /// Gap between the button's bottom edge and the menu's top.
    private static let dropGap: CGFloat = 3
    /// A click that closed the menu must not open it again: `NSMenu.popUp` tracks modally, so a click
    /// on the button ends the tracking, and if AppKit passes that click on, the button fires right after.
    private static let reopenGuard: TimeInterval = 0.25

    /// Drops the menu down below the anchor's button, left edges aligned and at least as wide; with no
    /// anchor view, at the pointer. A call that comes from the click which just closed this button's
    /// menu is ignored, so a second click on the button closes the menu and leaves it closed.
    static func show(_ items: [Item?], below anchor: Anchor) {
        if let up = anchor.closingMouseUp, let event = NSApp.currentEvent, event.type == .leftMouseUp,
           event.eventNumber == up {
            anchor.closingMouseUp = nil
            return
        }
        anchor.closingMouseUp = nil
        guard ProcessInfo.processInfo.systemUptime - anchor.closedAt > reopenGuard else { return }
        guard let view = anchor.view, view.window != nil else {
            show(items)
            return
        }
        let menu = makeMenu(items)
        menu.minimumWidth = view.bounds.width
        let y = view.isFlipped ? view.bounds.maxY + dropGap : view.bounds.minY - dropGap
        menu.popUp(positioning: nil, at: NSPoint(x: view.bounds.minX, y: y), in: view)
        anchor.closedAt = ProcessInfo.processInfo.systemUptime
        // Still held: this press closed the menu. Remember its mouse-up so the button ignores it.
        if NSEvent.pressedMouseButtons & 1 != 0 {
            var monitor: Any?
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { event in
                anchor.closingMouseUp = event.eventNumber
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
                return event
            }
        }
    }

    static func show(_ items: [Item?]) {
        makeMenu(items).popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private static func makeMenu(_ items: [Item?]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for entry in items {
            guard let entry else {
                menu.addItem(.separator())
                continue
            }
            let target = Target(entry.action ?? {})
            let item = NSMenuItem(title: entry.title, action: #selector(Target.run), keyEquivalent: "")
            item.target = target
            item.representedObject = target  // `target` is weak
            item.subtitle = entry.subtitle
            if let logo = entry.logo, let image = NSImage(named: logo == .claudeCode ? "ClaudeLogo" : "CodexLogo") {
                let sized = image.copy() as? NSImage ?? image
                sized.size = NSSize(width: 14, height: 14)
                item.image = sized
            }
            item.state = entry.checked ? .on : .off
            item.isEnabled = entry.enabled && entry.action != nil
            menu.addItem(item)
        }
        return menu
    }

    private final class Target: NSObject {
        let action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func run() { action() }
    }
}
