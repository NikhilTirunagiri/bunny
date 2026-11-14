import SwiftUI

/// The one button style of the main window (spec §11.16): a soft wash on hover, a stronger one while
/// pressed, a slight press-in, dimmed when disabled. Only `lively` buttons (Hand off) also grow on
/// hover. No motion under Reduce Motion. No glass.
struct BunnyButtonStyle: ButtonStyle {
    enum Kind {
        /// A round icon button of the given diameter; the label brings its own symbol and color.
        case icon(CGFloat)
        /// A small text button with a resting fill.
        case text
        /// A full-width, left-aligned row (list headers, read-only result rows): wash only, no scale.
        case row
    }

    var kind: Kind = .text
    /// Text buttons only: the label in the system red (never a red fill).
    var destructive = false
    /// Text buttons only: the surface's one primary action, filled with the accent color.
    var prominent = false
    /// Icon buttons only: the button's view is the one showing, so it rests on an accent wash.
    var selected = false
    /// Grows slightly on hover. Only the Hand off buttons; every other button stays calm.
    var lively = false

    /// The same style, growing slightly on hover (the Hand off buttons).
    func lively(_ on: Bool = true) -> BunnyButtonStyle {
        var style = self
        style.lively = on
        return style
    }

    func makeBody(configuration: Configuration) -> some View {
        Content(kind: kind, destructive: destructive, prominent: prominent, selected: selected,
                lively: lively, configuration: configuration)
    }

    private struct Content: View {
        let kind: Kind
        let destructive: Bool
        let prominent: Bool
        let selected: Bool
        let lively: Bool
        let configuration: Configuration

        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var isHovered = false

        private var wash: Double {
            let resting: Double = if case .text = kind { 0.06 } else { 0 }
            guard isEnabled else { return resting }
            if configuration.isPressed { return resting + 0.12 }
            return isHovered ? resting + 0.06 : resting
        }

        private var scale: CGFloat {
            if case .row = kind { return 1 }
            guard isEnabled, !reduceMotion else { return 1 }
            if configuration.isPressed { return 0.95 }
            return lively && isHovered ? 1.04 : 1
        }

        var body: some View {
            label
                .opacity(isEnabled ? 1 : 0.4)
                .scaleEffect(scale)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
                .onHover { isHovered = $0 }
        }

        @ViewBuilder
        private var label: some View {
            let fill = Color.primary.opacity(wash)
            switch kind {
            case .icon(let diameter):
                configuration.label
                    .frame(width: diameter, height: diameter)
                    .background(fill, in: .circle)
                    .background(selected ? Color.accentColor.opacity(0.2) : .clear, in: .circle)
                    .contentShape(.circle)
            case .text:
                configuration.label
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(prominent ? Color.white : destructive ? Color.red : Color.primary)
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    // Prominent: the wash darkens the accent fill instead of tinting a clear one.
                    .background(prominent ? Color.black.opacity(wash - 0.06) : fill,
                                in: .rect(cornerRadius: 7, style: .continuous))
                    .background(prominent ? Color.accentColor : .clear, in: .rect(cornerRadius: 7, style: .continuous))
                    .contentShape(.rect(cornerRadius: 7, style: .continuous))
            case .row:
                configuration.label
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(fill, in: RowMetrics.highlight)
                    .contentShape(.rect)
            }
        }
    }
}

extension ButtonStyle where Self == BunnyButtonStyle {
    /// Text button.
    static var bunny: BunnyButtonStyle { BunnyButtonStyle() }
    /// Text button for destructive actions: red label.
    static var bunnyDestructive: BunnyButtonStyle { BunnyButtonStyle(destructive: true) }
    /// Text button for the one primary action: accent fill.
    static var bunnyProminent: BunnyButtonStyle { BunnyButtonStyle(prominent: true) }
    /// Round icon button, 28 pt (bars and fields).
    static var bunnyIcon: BunnyButtonStyle { BunnyButtonStyle(kind: .icon(28)) }
    /// Round icon button, 20 pt (inside rows).
    static var bunnyRowIcon: BunnyButtonStyle { BunnyButtonStyle(kind: .icon(20)) }
    /// Full-width row.
    static var bunnyRow: BunnyButtonStyle { BunnyButtonStyle(kind: .row) }
}
