import SwiftUI
import SwiftData

/// Replaces the notes list: a back button and two tabs, Archive and Trash. Each tab brings its own
/// selection and bottom bar.
struct ArchiveView: View {
    let onBack: () -> Void

    @Environment(PanelCoordinator.self) private var coordinator
    @State private var tab: Tab = .archive

    private enum Tab: Hashable { case archive, trash }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Back to notes")

                Picker("", selection: $tab) {
                    Text("Archive").tag(Tab.archive)
                    Text("Trash").tag(Tab.trash)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 6)

            switch tab {
            case .archive: ArchiveTabView()
            case .trash: TrashTabView()
            }
        }
        .overlay {
            if let confirmation = coordinator.deleteConfirmation {
                DeleteConfirmationView(confirmation: confirmation)
            }
        }
    }
}

// MARK: - Shared pieces

/// Selection handling for the Archive and Trash lists (same rules as the notes list).
struct ListSelection {
    var selection = SelectionModel.Selection()

    var ids: Set<UUID> { selection.ids }

    mutating func click(_ id: UUID, visible: [UUID]) {
        selection = SelectionModel.apply(PanelCoordinator.clickInput(id), to: selection, visible: visible)
    }

    /// Drops ids that left the list.
    mutating func prune(visible: [UUID]) {
        let gone = selection.ids.subtracting(visible)
        if !gone.isEmpty { selection = SelectionModel.apply(.removed(gone), to: selection, visible: visible) }
    }

    /// A context menu on a row inside a multi-selection acts on the selection, otherwise on the row.
    func targets(for id: UUID) -> Set<UUID> {
        ids.count > 1 && ids.contains(id) ? ids : [id]
    }
}

/// Bottom bar of the Archive and Trash tabs: a caption on the left, actions on the right.
struct ArchiveBottomBar<Actions: View>: View {
    let caption: String
    @ViewBuilder let actions: Actions

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 6) {
                Text(caption)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                actions
            }
            .buttonStyle(.glass)
            .padding(.horizontal, 14)
        }
        .frame(height: 44)
    }
}

/// Row background shared by the Archive and Trash lists: selection (accent tint), then hover.
func archiveRowBackground(selected: Bool, hovered: Bool) -> AnyShapeStyle {
    if selected { return AnyShapeStyle(Color.accentColor.opacity(0.2)) }
    if hovered { return AnyShapeStyle(.quaternary.opacity(0.7)) }
    return AnyShapeStyle(.clear)
}

/// Empty state of the Archive and Trash lists.
struct ArchiveEmptyState: View {
    let systemImage: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: systemImage)
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
