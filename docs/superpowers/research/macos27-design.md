# macOS 27 ("Golden Gate") design notes for Bunny

Research summary (2026-09-24). macOS 27 tunes macOS 26 Tahoe's Liquid Glass:
user transparency slider, standardized/reduced corner radii, darker glass edges +
brighter specular highlights, broader "glass bounce" on controls (use sparingly),
cleaner menus (fewer SF Symbols beside commands), SF Symbols 8.

## APIs (all macOS 26.0+ unless noted)
SwiftUI
- `glassEffect(_ glass: Glass = .regular, in shape: some Shape = DefaultGlassEffectShape())`
- `Glass`: `.regular`, `.clear`, `.identity`, `.tint(Color)`, `.interactive()`
- `GlassEffectContainer(spacing:) { }`, `.glassEffectID(_:in:)`
- `.buttonStyle(.glass)`, `.buttonStyle(.glassProminent)`
- `ConcentricRectangle`, `.rect(corners: .concentric)`, `.containerShape(_:)`
- `.backgroundExtensionEffect()`
- `.symbolEffect(.drawOn/.drawOff/.variableDraw/.wiggle/.breathe/.rotate/.bounce)`
AppKit
- `NSGlassEffectView` (`contentView`, `cornerRadius`, `style`, `tintColor`)
- `NSGlassEffectContainerView`
- macOS 27: `NSView.cornerConfiguration` / `NSViewCornerRadius.containerConcentric` (availability unverified — don't depend on it)

## Rules
- Glass is for chrome/controls, not content. Never glass on glass.
- NSPopover chrome is glass by default on 26+ — don't add another glass layer inside it.
- Let system controls (Toggle, segmented Picker, TextField) render natively.
- `Glass.interactive()` only on primary actions.
- No system text-shimmer API: build with a `LinearGradient` mask animated by
  `TimelineView(.animation)` (continuous) — see Spec B §7.

Sources: 9to5mac.com/2026/09/14/macos-27-golden-gate-now-available-here-is-everything-new/,
developer.apple.com/videos/play/wwdc2026/289/, developer.apple.com/documentation/swiftui/view/glasseffect(_:in:),
developer.apple.com/documentation/appkit/nsglasseffectview, developer.apple.com/videos/play/wwdc2025/356/
