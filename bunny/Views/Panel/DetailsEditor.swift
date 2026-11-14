import AppKit
import SwiftUI

/// The note's details: plain text that is as tall as its content (the note side scrolls, not the
/// editor), with links shown and clickable. An `NSTextView`, because SwiftUI's `TextEditor` cannot
/// size to its content or show links.
///
/// The text is written to the binding on every change. `updateNSView` touches the view only when the
/// binding differs from what is shown (a change from outside, e.g. an agent), so re-renders never
/// move the caret.
struct DetailsEditor: NSViewRepresentable {
    @Binding var text: String
    let handle: Handle
    /// ⌘V with a file or a bare image on the clipboard: attach it instead of pasting text.
    var onAttachPaste: () -> Void

    /// Lets the note side put the caret in the editor (a click on the empty space below the text).
    @MainActor
    final class Handle {
        fileprivate weak var textView: DetailsTextView?

        func focusAtEnd() {
            guard let textView else { return }
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> DetailsTextView {
        let view = DetailsTextView(usingTextLayoutManager: false)
        view.delegate = context.coordinator
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = false
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.string = text
        view.restyle()
        view.onAttachPaste = onAttachPaste
        handle.textView = view
        return view
    }

    func updateNSView(_ view: DetailsTextView, context: Context) {
        context.coordinator.parent = self
        view.onAttachPaste = onAttachPaste
        handle.textView = view
        if view.string != text, !view.hasMarkedText() {
            view.string = text
            view.restyle()
            view.invalidateIntrinsicContentSize()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: DetailsTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        return CGSize(width: width, height: nsView.height(forWidth: width))
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: DetailsEditor
        init(_ parent: DetailsEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? DetailsTextView else { return }
            parent.text = view.string
            // Mid-composition (IME) text keeps its marked-text look until it is committed.
            if !view.hasMarkedText() { view.restyle() }
            view.invalidateIntrinsicContentSize()
            view.needsDisplay = true
        }
    }
}

final class DetailsTextView: NSTextView {
    static let detailsFont = NSFont.systemFont(ofSize: 13.5)
    private static let placeholder = "Add details…"

    var onAttachPaste: (() -> Void)?
    private var links: [(range: NSRange, url: URL)] = []
    private var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: Self.detailsFont, .foregroundColor: NSColor.labelColor]
    }

    // MARK: - Size

    func height(forWidth width: CGFloat) -> CGFloat {
        guard let textContainer, let layoutManager else { return 0 }
        textContainer.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        let line = layoutManager.defaultLineHeight(for: Self.detailsFont)
        return ceil(max(layoutManager.usedRect(for: textContainer).height, line))
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: height(forWidth: max(bounds.width, 1)))
    }

    // MARK: - Hint

    /// Drawn at the text origin with the text's font, so the caret sits exactly where the hint starts.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !hasMarkedText() else { return }
        Self.placeholder.draw(at: textContainerOrigin, withAttributes: [
            .font: Self.detailsFont, .foregroundColor: BunnyTheme.placeholder,
        ])
    }

    // MARK: - Links

    /// Colors and underlines the links. Attribute changes made straight on the storage are not
    /// undoable steps and leave the selection alone.
    func restyle() {
        guard let textStorage else { return }
        links = NoteText.links(in: string)
        textStorage.beginEditing()
        textStorage.setAttributes(baseAttributes, range: NSRange(location: 0, length: textStorage.length))
        for link in links {
            textStorage.addAttributes([.foregroundColor: BunnyTheme.link,
                                       .underlineStyle: NSUnderlineStyle.single.rawValue], range: link.range)
        }
        textStorage.endEditing()
        typingAttributes = baseAttributes
    }

    /// Where the links are, in view coordinates: one rect per line a link is on, from its first to
    /// its last glyph there and as tall as the line. The cursor and the click both go by these.
    private func linkRects() -> [(rect: NSRect, url: URL)] {
        guard let layoutManager, let textContainer, let textStorage else { return [] }
        let origin = textContainerOrigin
        var rects: [(rect: NSRect, url: URL)] = []
        // `links` is one step behind the text while an IME composition is marked.
        for link in links where NSMaxRange(link.range) <= textStorage.length {
            let glyphs = layoutManager.glyphRange(forCharacterRange: link.range, actualCharacterRange: nil)
            layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { line, _, _, lineGlyphs, _ in
                let onLine = layoutManager.boundingRect(forGlyphRange: NSIntersectionRange(glyphs, lineGlyphs), in: textContainer)
                rects.append((NSRect(x: origin.x + onLine.minX, y: origin.y + line.minY, width: onLine.width, height: line.height),
                              link.url))
            }
        }
        return rects
    }

    private func link(at point: NSPoint) -> URL? {
        linkRects().first { $0.rect.contains(point) }?.url
    }

    /// The link a plain or ⌘ click opens. With shift, option or control the click is the text's.
    private func linkToOpen(_ event: NSEvent) -> URL? {
        guard event.modifierFlags.intersection([.shift, .option, .control]).isEmpty else { return nil }
        return link(at: convert(event.locationInWindow, from: nil))
    }

    /// The window gives a clicked view the focus before `mouseDown`. A click on a link opens it and
    /// nothing else, so it must not.
    override var acceptsFirstResponder: Bool {
        if let event = NSApp.currentEvent, event.type == .leftMouseDown, event.window === window,
           linkToOpen(event) != nil { return false }
        return super.acceptsFirstResponder
    }

    /// A click on a link opens it: no caret, no focus. A press that moves away is a drag and
    /// selects text as anywhere else.
    override func mouseDown(with event: NSEvent) {
        guard let url = linkToOpen(event), let window else { return super.mouseDown(with: event) }
        let down = convert(event.locationInWindow, from: nil)
        while let next = window.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
            if next.type == .leftMouseUp {
                NSWorkspace.shared.open(url)
                return
            }
            if !NoteText.isLinkClick(from: down, to: convert(next.locationInWindow, from: nil)) { break }
        }
        // The focus the window did not give on this press (`acceptsFirstResponder`).
        window.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    // MARK: - Cursor

    // The pointing hand over a link, the I-beam elsewhere, set here on every move. `NSTextView`'s own
    // cursor handling (its cursor rects, `mouseMoved`, `cursorUpdate`) knows only the I-beam and
    // would put it back while the pointer is on a link, so none of it runs. Not TextKit's `.link`
    // attribute either: that follows the link itself and places the caret.

    private var cursorTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let cursorTrackingArea { removeTrackingArea(cursorTrackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .cursorUpdate, .mouseEnteredAndExited,
                                                         .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        cursorTrackingArea = area
    }

    private func updateCursor() {
        guard let window else { return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard visibleRect.contains(point) else { return }
        (link(at: point) == nil ? NSCursor.iBeam : NSCursor.pointingHand).set()
    }

    override func resetCursorRects() {}

    override func mouseMoved(with event: NSEvent) { updateCursor() }

    override func cursorUpdate(with event: NSEvent) { updateCursor() }

    /// Without cursor rects nothing else gives the arrow back.
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        NSCursor.arrow.set()
    }

    /// The text moves under a pointer that stays where it is.
    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        DispatchQueue.main.async { [weak self] in self?.updateCursor() }
    }

    // MARK: - Paste and drops

    override func paste(_ sender: Any?) {
        if AttachmentRules.attachesInEditor(types: ShelfService.clipboardTypes) {
            onAttachPaste?()
        } else {
            super.paste(sender)
        }
    }

    /// A plain-text view disables Paste for an image-only clipboard; keep it on so `paste` can attach.
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(paste(_:)), AttachmentRules.attachesInEditor(types: ShelfService.clipboardTypes) {
            return true
        }
        return super.validateUserInterfaceItem(item)
    }

    /// No drops of its own: a file dragged over the details goes to the note side's drop target
    /// (attach) instead of inserting its path as text.
    override var acceptableDragTypes: [NSPasteboard.PasteboardType] { [] }
}
