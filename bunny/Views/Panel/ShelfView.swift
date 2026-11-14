import SwiftUI
import SwiftData
import AppKit

/// The note's attachments: a wrapping strip of tiles (thumbnail or icon, name underneath) and a plus
/// that opens the file picker. Files are dropped on the note side as a whole (`TaskPanelView`), so
/// this is no drop target of its own.
struct ShelfView: View {
    let taskID: UUID
    @Environment(\.modelContext) private var modelContext
    @Environment(PanelCoordinator.self) private var coordinator
    @Query private var items: [ShelfItem]

    private static let columns = [GridItem(.adaptive(minimum: 66), spacing: 8, alignment: .top)]

    init(taskID: UUID) {
        self.taskID = taskID
        _items = Query(filter: #Predicate<ShelfItem> { $0.taskID == taskID },
                       sort: [SortDescriptor(\ShelfItem.sortOrder), SortDescriptor(\ShelfItem.addedAt)])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Text("Attachments").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(BunnyTheme.secondary)
                if !items.isEmpty {
                    Text("\(items.count)").font(.system(size: 11.5)).foregroundStyle(BunnyTheme.tertiary)
                }
                Spacer()
                Button {
                    let context = modelContext
                    coordinator.pickFiles { ShelfService.add($0, to: taskID, in: context) }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(BunnyTheme.secondary)
                }
                .buttonStyle(.bunnyRowIcon)
                .help("Attach files…")
            }
            if items.isEmpty {
                Label("Drop or paste a file to attach it", systemImage: "paperclip")
                    .font(.system(size: 12))
                    .foregroundStyle(BunnyTheme.tertiary)
            } else {
                LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 8) {
                    ForEach(items) { AttachmentTile(item: $0) }
                }
            }
        }
    }
}

/// One attachment: an image's thumbnail, else the file's (or folder's) icon, with the name under it.
/// A missing file is dimmed and marked. Hover shows a remove button; double-click opens; dragging it
/// out copies the file (`ShelfItemDragSource`).
private struct AttachmentTile: View {
    let item: ShelfItem
    @Environment(\.modelContext) private var modelContext
    #if DEBUG
    @Environment(\.snapshotHoveredID) private var snapshotHoveredID
    #endif
    @State private var isHoveredNow = false
    @State private var loaded: NSImage?

    private var isHovered: Bool {
        #if DEBUG
        if snapshotHoveredID == item.id { return true }
        #endif
        return isHoveredNow
    }

    var body: some View {
        let url = ShelfService.resolve(item)
        let context = modelContext
        VStack(spacing: 4) {
            // The preview is an overlay so an image filling the tile cannot widen it.
            Rectangle()
                .fill(BunnyTheme.surface(dark: .quaternary.opacity(0.5)))
                .frame(height: 50)
                .overlay { preview(url) }
                .clipShape(.rect(cornerRadius: 8, style: .continuous))
            Text(item.displayName)
                .font(.system(size: 10.5))
                .foregroundStyle(BunnyTheme.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .opacity(url == nil ? 0.55 : 1)
        .overlay(
            ShelfItemDragSource(
                url: url,
                toolTip: url == nil ? "Missing: \(item.lastKnownPath)" : item.lastKnownPath,
                onDragEnded: { op in
                    // A linked file dropped on another note moves there. A stored copy stays: its
                    // file belongs to this note. The tile may be gone by now (note side switched
                    // note): don't rely on its environment.
                    guard !op.isEmpty, !item.isDeleted, !item.isOwned else { return }
                    ShelfService.remove(item, in: item.modelContext ?? context)
                },
                onDoubleClick: { if let url { NSWorkspace.shared.open(url) } },
                onHover: { isHoveredNow = $0 }
            )
        )
        .appKitContextMenu {
            if let url {
                MenuEntry.item("Open") { NSWorkspace.shared.open(url) }
                MenuEntry.item("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                MenuEntry.item("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.path, forType: .string)
                }
                MenuEntry.separator
            }
            MenuEntry.item("Remove") { ShelfService.remove(item, in: context) }
        }
        .overlay(alignment: .topTrailing) {
            if isHovered {
                Button { ShelfService.remove(item, in: context) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(BunnyTheme.secondary)
                        .frame(width: 16, height: 16)
                        .background(BunnyTheme.background(), in: .circle)
                        .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
                }
                .buttonStyle(BunnyButtonStyle(kind: .icon(16)))
                .help("Remove")
                .padding(3)
            }
        }
        .task(id: url) {
            guard let url, !item.isDirectory, AttachmentThumbnails.isImage(url) else { return }
            loaded = await AttachmentThumbnails.load(item.id, url: url)
        }
    }

    @ViewBuilder
    private func preview(_ url: URL?) -> some View {
        if let url {
            if let thumbnail = loaded ?? AttachmentThumbnails.cached(item.id) {
                Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 32, height: 32)
            }
        } else {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 17))
                .foregroundStyle(.orange)
        }
    }
}
