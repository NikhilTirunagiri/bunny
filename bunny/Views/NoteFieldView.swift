import SwiftUI

/// The field at the top of the list. New note: a plus, the text, and a round search button; Return
/// adds the note.
/// Search (the button or ⌘F): the button grows leftward into a search field; Esc returns.
/// Quick capture: while a new note is being typed and the clipboard holds a file or an image, a strip
/// under the field offers to attach it; Tab accepts, Return alone adds the note without it.
struct NoteFieldView: View {
    /// Called with the raw text when Return is pressed in the New note field; `attachClipboard` when
    /// the quick-capture offer was accepted (Tab).
    let onAdd: (_ text: String, _ attachClipboard: Bool) -> Void

    @Environment(PanelCoordinator.self) private var coordinator
    #if DEBUG
    @Environment(\.snapshotClipboardOffer) private var snapshotClipboardOffer
    #endif
    @State private var newText = ""
    /// What the clipboard offers, from its type names only; refreshed while the field has focus.
    @State private var clipboardKind: AttachmentRules.ClipboardKind?
    /// The pasteboard change that was already attached to a note: not offered a second time.
    @State private var usedChangeCount: Int?
    @FocusState private var focus: Field?

    private enum Field: Hashable { case newNote, search }

    private static let radius: CGFloat = 10
    private static let buttonSize: CGFloat = 26
    private var fieldFill: some ShapeStyle { .quaternary.opacity(0.6) }

    /// The quick-capture offer: only while a new note is being typed, never in search.
    private var offer: AttachmentRules.ClipboardKind? {
        guard !coordinator.searching, !newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        #if DEBUG
        if let snapshotClipboardOffer { return snapshotClipboardOffer }
        #endif
        return focus == .newNote ? clipboardKind : nil
    }

    var body: some View {
        let offer = offer
        VStack(spacing: 0) {
            field
            if let offer {
                captureStrip(offer)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 6)
        // Tab (the window's key monitor) accepts the offer while the strip shows.
        .onChange(of: offer != nil, initial: true) { _, shown in
            coordinator.quickCaptureAccept = shown ? { add(attachClipboard: true) } : nil
        }
        // The clipboard is looked at only while the field has focus, which it never has in a closed window.
        .task(id: focus == .newNote) {
            guard focus == .newNote else { return }
            var seen: Int?
            while !Task.isCancelled {
                let count = NSPasteboard.general.changeCount
                if count != seen {
                    seen = count
                    clipboardKind = count == usedChangeCount ? nil : AttachmentRules.clipboardKind(types: ShelfService.clipboardTypes)
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func add(attachClipboard: Bool) {
        if attachClipboard {
            usedChangeCount = NSPasteboard.general.changeCount
            clipboardKind = nil
        }
        onAdd(newText, attachClipboard)
        newText = ""
    }

    private var field: some View {
        let searching = coordinator.searching
        return newNoteField
            .opacity(searching ? 0 : 1)
            .allowsHitTesting(!searching)
            .overlay(alignment: .trailing) {
                // The round button's background; it grows into the search field's.
                RoundedRectangle(cornerRadius: searching ? Self.radius : Self.buttonSize / 2, style: .continuous)
                    .fill(fieldFill)
                    .frame(maxWidth: searching ? .infinity : Self.buttonSize,
                           maxHeight: searching ? .infinity : Self.buttonSize)
                    .padding(.trailing, searching ? 0 : 5)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .trailing) {
                if searching {
                    searchField.transition(.opacity)
                } else {
                    Button { coordinator.startSearch() } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(BunnyButtonStyle(kind: .icon(Self.buttonSize)))
                    .help("Search notes (⌘F)")
                    .padding(.trailing, 5)
                    .transition(.opacity)
                }
            }
            // Every open starts with focus in the New note field.
            .onChange(of: coordinator.windowOpenCount) { focus = .newNote }
            // Async: coming from the Trash view or from search, the field only exists after this update.
            .onChange(of: coordinator.newNoteFocusRequests) { DispatchQueue.main.async { focus = .newNote } }
            .onChange(of: coordinator.searchFocusRequests) { DispatchQueue.main.async { focus = .search } }
            .onChange(of: focus) { _, field in
                coordinator.newNoteFieldFocused = field == .newNote
                coordinator.searchFieldFocused = field == .search
            }
    }

    /// The offer under the field: what would be attached (told from the clipboard's type names; its
    /// data is not read before Tab) and the key that accepts it. A click accepts too.
    private func captureStrip(_ kind: AttachmentRules.ClipboardKind) -> some View {
        Button { add(attachClipboard: true) } label: {
            HStack(spacing: RowMetrics.spacing) {
                Image(systemName: kind == .image ? "photo" : "doc")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: RowMetrics.checkbox, height: RowMetrics.checkbox)
                    .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 5, style: .continuous))
                Text(AttachmentRules.offerLabel(kind))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                keyHint("tab")
            }
            .padding(.leading, RowMetrics.gutter)
            .padding(.trailing, 10)
            .padding(.vertical, 5)
        }
        .buttonStyle(.bunnyRow)
        .padding(.top, 4)
    }

    private func keyHint(_ key: String) -> some View {
        Text(key)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(.quaternary))
    }

    /// Vertical axis so pasted multi-line text is kept and shown (up to four lines); Return still submits.
    /// While searching it stays in place, hidden, as the search field's frame: one line then, however
    /// long the draft it keeps.
    private var newNoteField: some View {
        HStack(alignment: .firstTextBaseline, spacing: RowMetrics.spacing) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: RowMetrics.checkbox)
            TextField("New note", text: $newText, axis: .vertical)
                .lineLimit(coordinator.searching ? 1...1 : 1...4)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($focus, equals: .newNote)
                .onSubmit { add(attachClipboard: false) }
        }
        .padding(.leading, RowMetrics.gutter)
        // Room for the search button.
        .padding(.trailing, Self.buttonSize + 10)
        .padding(.vertical, 9)
        .background(fieldFill, in: .rect(cornerRadius: Self.radius, style: .continuous))
    }

    private var searchField: some View {
        @Bindable var coordinator = coordinator
        return HStack(spacing: RowMetrics.spacing) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: RowMetrics.checkbox)
            TextField("Search notes", text: $coordinator.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($focus, equals: .search)
            keyHint("esc")
        }
        .padding(.leading, RowMetrics.gutter)
        .padding(.trailing, 10)
    }
}
