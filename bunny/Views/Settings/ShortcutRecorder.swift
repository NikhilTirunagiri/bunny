import AppKit
import SwiftUI

/// The global shortcut's control: shows the chord; a click records the next key chord (Esc cancels);
/// the x removes the shortcut. Why a chord was refused is reported through `message`.
struct ShortcutRecorder: View {
    @Binding var message: String?

    @State private var chord = GlobalHotKey.chord
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 4) {
            Button(recording ? "Type shortcut…" : chord.map { HotKeyRules.display($0) } ?? "Record Shortcut") {
                if recording { stop() } else { start() }
            }
            .buttonStyle(recording ? .bunnyProminent : .bunny)
            if chord != nil && !recording {
                Button {
                    GlobalHotKey.shared.set(nil)
                    chord = nil
                    message = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(BunnyTheme.secondary)
                }
                .buttonStyle(.bunnyRowIcon)
                .help("Remove the shortcut")
            }
        }
        .onDisappear(perform: stop)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in stop() }
    }

    private func start() {
        message = nil
        recording = true
        // The current shortcut must not fire (and be swallowed) while a new one is typed.
        GlobalHotKey.shared.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { record(event) }
            return nil
        }
    }

    private func stop() {
        guard recording else { return }
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        GlobalHotKey.shared.registerStored()
    }

    private func record(_ event: NSEvent) {
        var modifiers: HotKeyRules.Modifiers = []
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if event.keyCode == 53 && modifiers.isEmpty {
            stop()
            return
        }
        let typed = HotKeyRules.Chord(keyCode: Int(event.keyCode), modifiers: modifiers,
                                      key: event.characters(byApplyingModifiers: []) ?? "")
        if let rejection = HotKeyRules.rejection(for: typed) {
            message = rejection.message
        } else if GlobalHotKey.shared.set(typed) {
            chord = typed
            message = nil
            stop()
        } else {
            message = "Another app uses that shortcut. Pick another."
        }
    }
}
