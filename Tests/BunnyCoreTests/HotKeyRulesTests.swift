import Testing
@testable import BunnyCore

struct HotKeyRulesTests {
    private func chord(_ key: String, _ code: Int, _ modifiers: HotKeyRules.Modifiers) -> HotKeyRules.Chord {
        HotKeyRules.Chord(keyCode: code, modifiers: modifiers, key: key)
    }

    @Test func displayOrdersModifiersLikeTheSystem() {
        #expect(HotKeyRules.display(chord("b", 11, [.command, .shift, .option, .control])) == "⌃⌥⇧⌘B")
        #expect(HotKeyRules.display(chord("b", 11, [.option, .command])) == "⌥⌘B")
        #expect(HotKeyRules.display(chord(" ", 49, [.control, .option])) == "⌃⌥Space")
    }

    @Test func namedKeys() {
        #expect(HotKeyRules.keyName(keyCode: 36, key: "\r") == "↩")
        #expect(HotKeyRules.keyName(keyCode: 126, key: "") == "↑")
        #expect(HotKeyRules.keyName(keyCode: 122, key: "") == "F1")
        #expect(HotKeyRules.keyName(keyCode: 111, key: "") == "F12")
        #expect(HotKeyRules.keyName(keyCode: 0, key: "a") == "A")
        #expect(HotKeyRules.keyName(keyCode: 200, key: "") == "Key 200")
    }

    @Test func needsCommandOptionOrControl() {
        #expect(HotKeyRules.rejection(for: chord("b", 11, [])) == .needsModifier)
        #expect(HotKeyRules.rejection(for: chord("b", 11, [.shift])) == .needsModifier)
        #expect(HotKeyRules.rejection(for: chord("b", 11, [.option])) == nil)
        #expect(HotKeyRules.rejection(for: chord("b", 11, [.control, .shift])) == nil)
    }

    @Test func rejectsWhatTheSystemReserves() {
        #expect(HotKeyRules.rejection(for: chord("q", 12, [.command])) == .reserved)
        #expect(HotKeyRules.rejection(for: chord("Q", 12, [.command])) == .reserved)
        #expect(HotKeyRules.rejection(for: chord("w", 13, [.command])) == .reserved)
        #expect(HotKeyRules.rejection(for: chord("\t", 48, [.command])) == .reserved)
        #expect(HotKeyRules.rejection(for: chord(" ", 49, [.command])) == .reserved)
        #expect(HotKeyRules.rejection(for: chord("\t", 48, [.command, .shift])) == .reserved)
        // The same keys with more modifiers are free.
        #expect(HotKeyRules.rejection(for: chord("q", 12, [.command, .option])) == nil)
        #expect(HotKeyRules.rejection(for: chord(" ", 49, [.control, .option])) == nil)
    }

    @Test func rejectionsHaveAOneLineMessage() {
        #expect(!HotKeyRules.Rejection.needsModifier.message.contains("\n"))
        #expect(HotKeyRules.rejection(for: chord("q", 12, [.command]))?.message.isEmpty == false)
    }
}
