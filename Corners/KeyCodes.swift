import Carbon.HIToolbox

/// Maps key names from the config ("k", "'", "space", "f5") to the virtual
/// key codes RegisterEventHotKey expects.
///
/// Key codes are physical positions, so characters are looked up in the
/// current keyboard layout: "'" is a different key on US and German layouts.
@MainActor
enum KeyCodes {
    static func code(for key: String) -> Int? {
        let key = key.lowercased()
        if let code = named[key] { return code }
        guard key.count == 1 else { return nil }
        return layoutMap(shift: false)[key]
    }

    /// For a character that's typed with Shift, such as "|" or "!", the character
    /// on the same key without Shift ("\\", "1" on a US layout). Nil for anything
    /// else, including letters, which are case-insensitive.
    static func unshifted(_ key: String) -> String? {
        guard key.count == 1, code(for: key) == nil,
              let code = layoutMap(shift: true)[key]
        else { return nil }
        return layoutMap(shift: false).first { $0.value == code }?.key
    }

    /// The config name for a key code: a name like "left" or "f5", or the
    /// character the key types on the current layout. Nil for keypad keys and
    /// keys that type nothing.
    static func name(forCode code: Int) -> String? {
        if let name = canonicalNames[code] { return name }
        guard !keypad.contains(code) else { return nil }
        return layoutMap(shift: false).first { $0.value == code }?.key
    }

    /// How a key is shown in the Configure window: symbols for named keys
    /// ("←", "↩", "⌫"), "F5", "Space", and characters uppercased.
    static func displayName(for key: String) -> String {
        let key = key.lowercased()
        guard let code = named[key], let name = canonicalNames[code] else { return key.uppercased() }
        return symbols[name] ?? name.uppercased()
    }

    /// One name per named key, used when writing a key back out.
    private static let canonicalNames: [Int: String] = {
        var map = [
            kVK_Space: "space", kVK_Return: "return", kVK_Tab: "tab", kVK_Escape: "escape",
            kVK_Delete: "delete", kVK_ForwardDelete: "forwarddelete",
            kVK_UpArrow: "up", kVK_DownArrow: "down", kVK_LeftArrow: "left", kVK_RightArrow: "right",
            kVK_Home: "home", kVK_End: "end", kVK_PageUp: "pageup", kVK_PageDown: "pagedown",
        ]
        let functionKeys = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
        ]
        for (i, code) in functionKeys.enumerated() { map[code] = "f\(i + 1)" }
        return map
    }()

    /// Canonical names plus aliases accepted in the config file.
    private static let named: [String: Int] = {
        var map = Dictionary(uniqueKeysWithValues: canonicalNames.map { ($1, $0) })
        map["enter"] = kVK_Return
        map["esc"] = kVK_Escape
        map["backspace"] = kVK_Delete
        return map
    }()

    private static let symbols: [String: String] = [
        "space": "Space", "return": "↩", "tab": "⇥", "escape": "⎋",
        "delete": "⌫", "forwarddelete": "⌦",
        "up": "↑", "down": "↓", "left": "←", "right": "→",
        "home": "↖", "end": "↘", "pageup": "⇞", "pagedown": "⇟",
    ]

    /// Keypad keys type the same characters as main-keyboard keys ("+", "1"),
    /// so they're left out of the lookup to keep shortcuts on the main keyboard.
    private static let keypad: Set<Int> = [
        kVK_ANSI_KeypadDecimal, kVK_ANSI_KeypadMultiply, kVK_ANSI_KeypadPlus, kVK_ANSI_KeypadClear,
        kVK_ANSI_KeypadDivide, kVK_ANSI_KeypadEnter, kVK_ANSI_KeypadMinus, kVK_ANSI_KeypadEquals,
        kVK_ANSI_Keypad0, kVK_ANSI_Keypad1, kVK_ANSI_Keypad2, kVK_ANSI_Keypad3, kVK_ANSI_Keypad4,
        kVK_ANSI_Keypad5, kVK_ANSI_Keypad6, kVK_ANSI_Keypad7, kVK_ANSI_Keypad8, kVK_ANSI_Keypad9,
    ]

    /// Character → key code for the current layout, built by asking the
    /// layout what each key types with no modifiers (or only Shift) held.
    private static func layoutMap(shift: Bool) -> [String: Int] {
        // UCKeyTranslate takes the Carbon modifier flags shifted down a byte.
        let modifierState = shift ? UInt32(shiftKey >> 8) & 0xFF : 0
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return [:] }
        let data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data

        var map: [String: Int] = [:]
        data.withUnsafeBytes { raw in
            let layout = raw.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self)
            for code in 0..<128 where !keypad.contains(code) {
                var deadKeyState: UInt32 = 0
                var chars = [UniChar](repeating: 0, count: 4)
                var length = 0
                let status = UCKeyTranslate(
                    layout, UInt16(code), UInt16(kUCKeyActionDown), modifierState, UInt32(LMGetKbdType()),
                    OptionBits(1 << kUCKeyTranslateNoDeadKeysBit), &deadKeyState,
                    chars.count, &length, &chars)
                guard status == noErr, length > 0 else { continue }
                var string = String(utf16CodeUnits: chars, count: length)
                if !shift { string = string.lowercased() }
                if map[string] == nil, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    map[string] = code
                }
            }
        }
        return map
    }
}
