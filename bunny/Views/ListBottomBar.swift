import SwiftUI

/// The list column's bottom bar, the same in every view: Trash on the left, Settings on the right.
/// In the Trash view the Trash button is drawn active and leads back to the notes list. Everything
/// contextual is in the `ActionStrip` above it.
struct ListBottomBar: View {
    @Environment(PanelCoordinator.self) private var coordinator

    /// Quieter than the red of destructive buttons, still clearly not Settings' gray.
    private static let trashTint = Color.red.mix(with: Color(nsColor: .secondaryLabelColor), by: 0.35)

    var body: some View {
        let inTrash = coordinator.showingTrash
        HStack(spacing: 4) {
            Button {
                if inTrash { coordinator.leaveTrash() } else { coordinator.showTrash() }
            } label: {
                icon("trash", tint: inTrash ? Color.accentColor : Self.trashTint)
            }
            .buttonStyle(BunnyButtonStyle(kind: .icon(28), selected: inTrash))
            .help(inTrash ? "Back to notes" : "Trash")
            Spacer()
            Button { WindowManager.shared.showSettings() } label: { icon("gearshape", tint: .secondary) }
                .buttonStyle(.bunnyIcon)
                .help("Settings (⌘,)")
        }
        // The icons sit in the checkbox column on the left and under the search button on the right.
        .padding(.leading, 20)
        .padding(.trailing, 14)
        .frame(height: 44)
        .overlay(alignment: .top) { Divider().opacity(0.6) }
    }

    /// Fitted into one square, so a tall symbol (the trash can) and a round one (the gear) come out
    /// the same optical size on the same centre line.
    private func icon(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .resizable()
            .scaledToFit()
            .fontWeight(.regular)
            .frame(width: 15, height: 15)
            .foregroundStyle(tint)
    }
}

/// The slim strip directly above the bottom bar, where everything contextual goes. One line at a
/// time, in this order: the selection's actions (`selected` > 0), the Undo offer or a brief notice
/// ("Copied 2 notes"), the view's standing line (`standing`). Nothing to show: no strip. It fades in
/// with a short slide; instantly under Reduce Motion.
struct ActionStrip<SelectionActions: View, StandingActions: View>: View {
    /// How many notes the selection's actions apply to; 0 when they do not apply.
    let selected: Int
    var standing: String? = nil
    @ViewBuilder let selectionActions: SelectionActions
    @ViewBuilder let standingActions: StandingActions

    @Environment(PanelCoordinator.self) private var coordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let undo = coordinator.undo
        let shown = selected > 0 || undo != nil || standing != nil
        VStack(spacing: 0) {
            if shown {
                Group {
                    if selected > 0 {
                        // A notice takes the count's place: copying leaves the selection as it is.
                        line(undo.flatMap { $0.restore == nil ? $0.message : nil } ?? "\(selected) selected") {
                            selectionActions
                        }
                    } else if let undo {
                        line(undo.message) {
                            if undo.restore != nil { undoButton }
                        }
                    } else if let standing {
                        line(standing) { standingActions }
                    }
                }
                .transition(.opacity.combined(with: .offset(y: 8)))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: shown)
    }

    private func line(_ caption: String, @ViewBuilder actions: () -> some View) -> some View {
        HStack(spacing: 6) {
            Text(caption)
                .font(.system(size: 12))
                .foregroundStyle(BunnyTheme.secondary)
                .lineLimit(1)
                // Three buttons leave "Copied 2 notes" just enough room: never truncate it.
                .fixedSize()
            Spacer(minLength: 0)
            actions()
        }
        .buttonStyle(.bunny)
        // Same columns as the bottom bar.
        .padding(.leading, 20)
        .padding(.trailing, 14)
        .frame(height: 36)
        .overlay(alignment: .top) { Divider().opacity(0.6) }
    }

    private var undoButton: some View {
        Button { coordinator.performUndo() } label: {
            HStack(spacing: 5) {
                Text("Undo")
                Text("⌘Z").foregroundStyle(BunnyTheme.tertiary)
            }
        }
    }
}

extension ActionStrip where StandingActions == EmptyView {
    /// A view with no standing line (the notes list).
    init(selected: Int, @ViewBuilder selectionActions: () -> SelectionActions) {
        self.init(selected: selected, selectionActions: selectionActions) { EmptyView() }
    }
}
