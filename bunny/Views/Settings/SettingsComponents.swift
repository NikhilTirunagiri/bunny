import SwiftUI

enum SettingsMetrics {
    static let sidebarWidth: CGFloat = 210
    static let contentWidth: CGFloat = 580
    static let padding: CGFloat = 22
    static let cardRadius: CGFloat = 14
    static let tile: CGFloat = 26
    static let rowPadding: CGFloat = 14
    static let tileGap: CGFloat = 10
    /// Where a row's title starts, from the card's edge: hairlines and follow-up controls line up with it.
    static let textInset = rowPadding + tile + tileGap
}

/// A rounded group of rows, separated by hairlines that start at the titles.
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { subviews in
                ForEach(subviews) { subview in
                    if subview.id != subviews.first?.id {
                        Divider().padding(.leading, SettingsMetrics.textInset)
                    }
                    subview
                }
            }
        }
        .background(BunnyTheme.surface(dark: .quaternary.opacity(0.45)))
        .clipShape(.rect(cornerRadius: SettingsMetrics.cardRadius, style: .continuous))
    }
}

/// One setting: tinted icon tile, title, optional caption, the control at the trailing edge, and
/// optionally follow-up controls or notes underneath, lined up with the title. Title and icon come
/// from `SettingsCatalog`, the same list the sidebar search reads.
struct SettingsRow<Control: View, Detail: View>: View {
    @Environment(SettingsModel.self) private var model

    private let row: SettingsCatalog.Row
    private let caption: String?
    private let tag: String?
    private let control: Control
    private let detail: Detail

    init(_ id: SettingsCatalog.RowID, caption: String? = nil, tag: String? = nil,
         @ViewBuilder control: () -> Control, @ViewBuilder detail: () -> Detail) {
        row = SettingsCatalog.row(id)
        self.caption = caption
        self.tag = tag
        self.control = control()
        self.detail = detail()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: SettingsMetrics.tileGap) {
                Image(systemName: row.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: SettingsMetrics.tile, height: SettingsMetrics.tile)
                    .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(row.title)
                        if let tag {
                            Text(tag)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(BunnyTheme.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(BunnyTheme.deepSurface(dark: Color.primary.opacity(0.08)), in: .capsule)
                        }
                    }
                    if let caption {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(BunnyTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 12)
                control
            }
            detail
                .padding(.leading, SettingsMetrics.tile + SettingsMetrics.tileGap)
        }
        .padding(.horizontal, SettingsMetrics.rowPadding)
        .padding(.vertical, 10)
        .frame(minHeight: 48)
        .background(Color.accentColor.opacity(model.highlighted == row.id ? 0.16 : 0))
        .animation(.easeOut(duration: 0.3), value: model.highlighted)
        .id(row.id)
    }
}

extension SettingsRow where Detail == EmptyView {
    init(_ id: SettingsCatalog.RowID, caption: String? = nil, tag: String? = nil, @ViewBuilder control: () -> Control) {
        self.init(id, caption: caption, tag: tag, control: control, detail: { EmptyView() })
    }
}

/// A line of small print under a row's control: an explanation, a warning or an error.
struct SettingsNote: View {
    let text: String
    /// nil: secondary text.
    var color: Color?

    init(_ text: String, color: Color? = nil) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(BunnyTheme.secondary))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A small heading above a card.
struct SettingsHeading: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(BunnyTheme.secondary)
            .padding(.leading, SettingsMetrics.rowPadding)
            .padding(.top, 6)
            .padding(.bottom, -6)
    }
}

/// The trailing switch of a row.
struct SettingsSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
    }
}
