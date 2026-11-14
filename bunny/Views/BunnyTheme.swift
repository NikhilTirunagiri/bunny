import AppKit
import SwiftUI

/// The colors of the main window and the Settings window.
///
/// Dark is the system's own look: every style takes the dark value it had before this palette
/// existed and hands it back unchanged. Light trades pure white and cool grays for warm neutrals
/// (ivory surfaces, warm near-black text). The accent is always the user's own; in light it only
/// tints.
enum BunnyTheme {
    // MARK: - Surfaces

    /// The window itself: the main window's card, the Settings window, a card floating over them.
    static func background(dark: some ShapeStyle = Color(nsColor: .windowBackgroundColor)) -> some ShapeStyle {
        Adaptive(light: Color(hex: 0xFAF9F5), dark: dark)
    }

    /// What sits on the background: fields, cards, tiles, the sidebar, a hovered row.
    static func surface(dark: some ShapeStyle) -> some ShapeStyle {
        Adaptive(light: Color(hex: 0xF0EEE6), dark: dark)
    }

    /// What sits on a surface: a field in the sidebar or in a card, a badge.
    static func deepSurface(dark: some ShapeStyle) -> some ShapeStyle {
        Adaptive(light: Color(hex: 0xE8E6DC), dark: dark)
    }

    /// A selected row: the accent as a tint under dark text, softer in light.
    static func selection(dark opacity: Double) -> some ShapeStyle {
        Adaptive(light: Color.accentColor.opacity(0.14), dark: Color.accentColor.opacity(opacity))
    }

    /// The tick of a note the user completed: blue, toned down in light.
    static var done: some ShapeStyle { Adaptive(light: Color(hex: 0x4A7FC1), dark: Color.blue) }

    // MARK: - Text

    // Primary text is the system's label color: translucent, so on the ivory it is already a warm
    // near-black (#262524).
    static var secondary: some ShapeStyle { Adaptive(light: Color(hex: 0x5C5B56), dark: .secondary) }
    static var tertiary: some ShapeStyle { Adaptive(light: Color(nsColor: placeholder), dark: .tertiary) }

    // For AppKit text (the details editor).
    static let placeholder = dynamic(light: 0x676661, dark: .tertiaryLabelColor)
    static let link = dynamic(light: 0x2F6FB7, dark: .linkColor)

    private static func dynamic(light: UInt32, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : NSColor(Color(hex: light))
        }
    }

    private struct Adaptive<Light: ShapeStyle, Dark: ShapeStyle>: ShapeStyle {
        let light: Light
        let dark: Dark

        func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
            environment.colorScheme == .dark ? AnyShapeStyle(dark) : AnyShapeStyle(light)
        }
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
