import AppKit
import SwiftUI

/// One entry of an `appKitContextMenu`.
enum MenuEntry {
    case item(String, image: String? = nil, destructive: Bool = false, action: () -> Void)
    case separator
}

@resultBuilder
enum MenuBuilder {
    static func buildExpression(_ entry: MenuEntry) -> [MenuEntry] { [entry] }
    static func buildExpression(_ entries: [MenuEntry]) -> [MenuEntry] { entries }
    static func buildBlock(_ parts: [MenuEntry]...) -> [MenuEntry] { parts.flatMap { $0 } }
    static func buildOptional(_ part: [MenuEntry]?) -> [MenuEntry] { part ?? [] }
    static func buildEither(first part: [MenuEntry]) -> [MenuEntry] { part }
    static func buildEither(second part: [MenuEntry]) -> [MenuEntry] { part }
}

extension View {
    /// A right-click (or control-click) menu built by AppKit when it opens, instead of SwiftUI's
    /// `.contextMenu`: SwiftUI re-renders (the 1 s timer tick) can't rebuild it while it shows, and
    /// destructive items are red, which a SwiftUI context menu in this panel doesn't do.
    func appKitContextMenu(@MenuBuilder _ entries: @escaping () -> [MenuEntry]) -> some View {
        overlay { ContextMenuArea(entries: entries) }
    }
}

private struct ContextMenuArea: NSViewRepresentable {
    let entries: () -> [MenuEntry]

    func makeNSView(context: Context) -> ContextMenuView { ContextMenuView() }
    func updateNSView(_ view: ContextMenuView, context: Context) { view.entries = entries }
}

/// Claims only right-clicks and control-clicks; every other event (clicks, drags, scrolling) goes to
/// the SwiftUI content underneath.
private final class ContextMenuView: NSView {
    var entries: () -> [MenuEntry] = { [] }
    /// Set while asking SwiftUI for its own menu, which hit-tests these views again.
    private static var askingSwiftUI = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !Self.askingSwiftUI, let event = NSApp.currentEvent else { return nil }
        let menuClick = event.type == .rightMouseDown
            || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
        guard menuClick else { return nil }
        // A SwiftUI `.contextMenu` inside the row (the agent button's) keeps its own menu.
        Self.askingSwiftUI = true
        defer { Self.askingSwiftUI = false }
        if window?.contentView?.menu(for: event) != nil { return nil }
        return super.hitTest(point)
    }

    override func rightMouseDown(with event: NSEvent) { popUp(event) }
    /// Only control-clicks get here (`hitTest`).
    override func mouseDown(with event: NSEvent) { popUp(event) }

    private func popUp(_ event: NSEvent) {
        let menu = NSMenu()
        // Titles flush left: no state column, and icons go at the right end of the title, not in
        // `NSMenuItem.image` (which would indent every item).
        menu.showsStateColumn = false
        let style = MenuStyle(entries: entries())
        for entry in style.entries {
            switch entry {
            case .separator:
                menu.addItem(.separator())
            case let .item(title, image, destructive, action):
                let target = MenuAction(title: title, image: image, destructive: destructive, action: action)
                let item = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: "")
                item.target = target
                item.representedObject = target  // `target` is weak
                style.apply(to: item, highlighted: false)
                menu.addItem(item)
            }
        }
        menu.delegate = style
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

/// Lays out icon items as "title <tab> icon" with a right tab stop shared by the whole menu, so the
/// icons line up at its right edge. An attributed title keeps its colors when highlighted, so the
/// highlighted icon item is redrawn in the selected-item text color and restored when left.
private final class MenuStyle: NSObject, NSMenuDelegate {
    let entries: [MenuEntry]
    private let font = NSFont.menuFont(ofSize: 0)
    private let tabStop: CGFloat
    private weak var highlighted: NSMenuItem?

    init(entries: [MenuEntry]) {
        self.entries = entries
        let titles = entries.compactMap { entry -> String? in
            if case let .item(title, _, _, _) = entry { return title }
            return nil
        }
        let font = font
        let widest = titles.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        tabStop = ceil(widest) + 20 + font.pointSize
    }

    func apply(to item: NSMenuItem, highlighted: Bool) {
        guard let info = item.representedObject as? MenuAction, info.image != nil || info.destructive else { return }
        let color: NSColor = highlighted ? .selectedMenuItemTextColor : (info.destructive ? .systemRed : .labelColor)
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: tabStop)]
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        let title = NSMutableAttributedString(string: info.title, attributes: attributes)
        if let name = info.image,
           let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
               .withSymbolConfiguration(.init(pointSize: font.pointSize, weight: .regular)
                   .applying(.init(paletteColors: [color]))) {
            let attachment = NSTextAttachment()
            attachment.image = symbol
            attachment.bounds = CGRect(x: 0, y: (font.capHeight - symbol.size.height) / 2,
                                       width: symbol.size.width, height: symbol.size.height)
            title.append(NSAttributedString(string: "\t", attributes: attributes))
            title.append(NSAttributedString(attachment: attachment, attributes: attributes))
        }
        item.attributedTitle = title
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        if let highlighted { apply(to: highlighted, highlighted: false) }
        if let item { apply(to: item, highlighted: true) }
        highlighted = item
    }
}

private final class MenuAction: NSObject {
    let title: String
    let image: String?
    let destructive: Bool
    let action: () -> Void
    init(title: String, image: String?, destructive: Bool, action: @escaping () -> Void) {
        self.title = title
        self.image = image
        self.destructive = destructive
        self.action = action
    }
    @objc func run() { action() }
}
