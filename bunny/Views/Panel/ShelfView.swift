import SwiftUI
import SwiftData
import AppKit

struct ShelfView: View {
    let taskID: UUID
    /// False while the panel puts an agent question first: hides the placeholder, keeps items.
    var showsEmptyDropZone: Bool = true
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [ShelfItem]
    @State private var isTargeted = false
    @State private var hoveredID: UUID?

    init(taskID: UUID, showsEmptyDropZone: Bool = true) {
        self.taskID = taskID
        self.showsEmptyDropZone = showsEmptyDropZone
        _items = Query(filter: #Predicate<ShelfItem> { $0.taskID == taskID },
                       sort: [SortDescriptor(\ShelfItem.sortOrder), SortDescriptor(\ShelfItem.addedAt)])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Shelf").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                if !items.isEmpty {
                    Text("\(items.count)").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                Spacer()
            }
            if items.isEmpty {
                if showsEmptyDropZone { emptyZone }
            } else {
                // The panel's content already scrolls; no nested scroll view.
                VStack(spacing: 2) {
                    ForEach(items) { item in row(item) }
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isTargeted ? AnyShapeStyle(Color.accentColor.opacity(0.15)) : AnyShapeStyle(.clear)))
        .dropDestination(for: URL.self) { urls, _ in
            ShelfService.add(urls, to: taskID, in: modelContext) > 0
        } isTargeted: { isTargeted = $0 }
    }

    private var emptyZone: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray.and.arrow.down").font(.system(size: 18)).foregroundStyle(.tertiary)
            Text("Drop files or folders here").font(.system(size: 12)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 72)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .foregroundStyle(.quaternary))
    }

    private func row(_ item: ShelfItem) -> some View {
        let url = ShelfService.resolve(item)
        let context = modelContext
        return HStack(spacing: 8) {
            Group {
                if let url {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
                } else {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }
            .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName).font(.system(size: 12.5)).lineLimit(1).truncationMode(.middle)
                Text(url == nil ? "Missing" : ShelfRules.abbreviatedParentPath(of: item.lastKnownPath))
                    .font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
            Spacer(minLength: 0)
        }
        .opacity(url == nil ? 0.55 : 1)
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(hoveredID == item.id ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear)))
        .overlay(
            ShelfItemDragSource(
                url: url,
                toolTip: item.lastKnownPath,
                onDragEnded: { op in
                    // The row may be gone by now (panel switched task): don't rely on its environment.
                    guard !op.isEmpty, !item.isDeleted else { return }
                    ShelfService.remove(item, in: item.modelContext ?? context)
                },
                onDoubleClick: { if let url { NSWorkspace.shared.open(url) } },
                menu: { menu(for: item, url: url, context: context) },
                onHover: { hoveredID = $0 ? item.id : (hoveredID == item.id ? nil : hoveredID) }
            )
        )
    }

    private func menu(for item: ShelfItem, url: URL?, context: ModelContext) -> NSMenu {
        let menu = NSMenu()
        if let url {
            menu.addItem(ClosureMenuItem("Open") { NSWorkspace.shared.open(url) })
            menu.addItem(ClosureMenuItem("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) })
            menu.addItem(ClosureMenuItem("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.path, forType: .string)
            })
            menu.addItem(.separator())
        }
        menu.addItem(ClosureMenuItem("Remove from Shelf") { ShelfService.remove(item, in: context) })
        return menu
    }
}

/// NSMenuItem that runs a closure (keeps itself as target).
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func run() { handler() }
}
