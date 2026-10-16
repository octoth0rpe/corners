import Carbon.HIToolbox
import Testing

/// Character keys depend on the current keyboard layout, so these stick to
/// named keys and round trips, which hold on any layout.
@MainActor
struct KeyCodesTests {
    @Test func namedKeysHaveCanonicalNames() {
        #expect(KeyCodes.name(forCode: kVK_LeftArrow) == "left")
        #expect(KeyCodes.name(forCode: kVK_Return) == "return")
        #expect(KeyCodes.name(forCode: kVK_F5) == "f5")
    }

    @Test func keypadKeysHaveNoName() {
        #expect(KeyCodes.name(forCode: kVK_ANSI_Keypad1) == nil)
        #expect(KeyCodes.name(forCode: kVK_ANSI_KeypadEnter) == nil)
    }

    @Test func aliasesDisplayLikeTheirCanonicalKey() {
        #expect(KeyCodes.displayName(for: "left") == "←")
        #expect(KeyCodes.displayName(for: "enter") == "↩")
        #expect(KeyCodes.displayName(for: "return") == "↩")
        #expect(KeyCodes.displayName(for: "backspace") == "⌫")
        #expect(KeyCodes.displayName(for: "f5") == "F5")
        #expect(KeyCodes.displayName(for: "space") == "Space")
        #expect(KeyCodes.displayName(for: "k") == "K")
    }

    /// What the key recorder writes must read back as the same physical key.
    @Test func recordedKeysReadBackAsTheSameKey() {
        for code in 0..<128 {
            guard let name = KeyCodes.name(forCode: code) else { continue }
            #expect(KeyCodes.code(for: name) == code, "key code \(code) recorded as \"\(name)\"")
        }
    }
}
