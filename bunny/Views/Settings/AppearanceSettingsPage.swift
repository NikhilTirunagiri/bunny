import SwiftUI

struct AppearanceSettingsPage: View {
    @AppStorage("appearance") private var appearance = "system"

    var body: some View {
        SettingsCard {
            SettingsRow(.theme) {
                HStack(spacing: 12) {
                    ForEach(["system", "light", "dark"], id: \.self) { value in
                        Button {
                            appearance = value
                            WindowManager.applyAppearance(value)
                        } label: {
                            ThemeThumbnail(value: value, selected: appearance == value)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            SettingsRow(.backgroundImage, caption: "A soft, blurred picture behind your notes.", tag: "v3.1") {
                SettingsSwitch(isOn: .constant(false))
            }
            .disabled(true)
        }
    }
}

/// A small drawing of a Bunny list in one theme; "system" is light and dark split diagonally.
private struct ThemeThumbnail: View {
    let value: String
    let selected: Bool

    private static let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)

    var body: some View {
        VStack(spacing: 4) {
            art
                .frame(width: 58, height: 40)
                .clipShape(Self.shape)
                .overlay {
                    Self.shape.strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.18),
                                            lineWidth: selected ? 2 : 1)
                }
            Text(value.capitalized)
                .font(.caption)
                .foregroundStyle(selected ? AnyShapeStyle(Color.primary) : AnyShapeStyle(BunnyTheme.secondary))
        }
        .contentShape(.rect)
        .accessibilityLabel(value.capitalized)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var art: some View {
        switch value {
        case "light": list(dark: false)
        case "dark": list(dark: true)
        default:
            ZStack {
                list(dark: false)
                list(dark: true).mask(LowerRightHalf())
            }
        }
    }

    private func list(dark: Bool) -> some View {
        let ink = dark ? Color.white : Color.black
        return ZStack(alignment: .topLeading) {
            dark ? Color(white: 0.16) : Color(white: 0.97)
            VStack(alignment: .leading, spacing: 5) {
                ForEach([28, 20, 24], id: \.self) { width in
                    HStack(spacing: 4) {
                        Circle().strokeBorder(ink.opacity(0.45), lineWidth: 1).frame(width: 6, height: 6)
                        Capsule().fill(ink.opacity(0.55)).frame(width: CGFloat(width), height: 3)
                    }
                }
            }
            .padding(.leading, 8)
            .padding(.top, 8)
        }
    }
}

private struct LowerRightHalf: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
