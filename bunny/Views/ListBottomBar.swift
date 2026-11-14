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
                pillLabel("trash", "Trash", iconTint: inTrash ? Color.accentColor : Self.trashTint,
                          textTint: inTrash ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(BunnyTheme.secondary))
            }
            .buttonStyle(BarPillStyle(selected: inTrash))
            .help(inTrash ? "Back to notes" : "Trash")
            Spacer()
            Button { WindowManager.shared.showSettings() } label: {
                pillLabel("gearshape", "Settings", iconTint: nil, textTint: AnyShapeStyle(BunnyTheme.secondary))
            }
            .buttonStyle(BarPillStyle())
            .help("Settings (⌘,)")
        }
        // The two pills mirror each other: the same inset from each edge of the list column.
        .padding(.horizontal, 14)
        .frame(height: 44)
        .overlay(alignment: .top) { Divider().opacity(0.6) }
    }

    /// Icon + word, both the same in the two pills. The icon is fitted into one square, so a tall
    /// symbol (the trash can) and a round one (the gear) come out the same optical size.
    private func pillLabel(_ symbol: String, _ title: String, iconTint: Color?, textTint: AnyShapeStyle) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .resizable()
                .scaledToFit()
                .fontWeight(.medium)
                .frame(width: 13, height: 13)
                .foregroundStyle(iconTint.map(AnyShapeStyle.init) ?? textTint)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(textTint)
        }
    }
}

/// The bottom bar's buttons (Trash, Settings): a quiet pill, a surface fill with a hairline border. A faint
/// wash on hover, a stronger one and a slight press-in while pressed (none under Reduce Motion).
private struct BarPillStyle: ButtonStyle {
    /// The view this button leads to is showing (Trash): an accent-tinted fill and border.
    var selected = false

    func makeBody(configuration: Configuration) -> some View { Content(configuration: configuration, selected: selected) }

    private struct Content: View {
        let configuration: Configuration
        let selected: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var isHovered = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
            let wash = configuration.isPressed ? 0.10 : isHovered ? 0.05 : 0
            configuration.label
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Color.primary.opacity(wash), in: shape)
                .background(selected ? AnyShapeStyle(Color.accentColor.opacity(0.16))
                                     : AnyShapeStyle(BunnyTheme.surface(dark: Color.primary.opacity(0.06))), in: shape)
                .overlay(shape.strokeBorder(selected ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.1), lineWidth: 0.5))
                .contentShape(shape)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
                .onHover { isHovered = $0 }
        }
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
