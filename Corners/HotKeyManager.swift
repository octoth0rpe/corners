import Carbon.HIToolbox

/// Registers system-wide hotkeys with Carbon's RegisterEventHotKey.
///
/// Despite the Carbon name, this is still the supported way to get global
/// shortcuts: it needs no Accessibility or Input Monitoring permission and
/// works inside the App Sandbox. The alternative, a CGEventTap, needs both.
@MainActor
final class HotKeyManager {
    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: @MainActor () -> Void] = [:]
    private var handler: EventHandlerRef?

    private static let signature: OSType = 0x4352_4E52 // "CRNR"

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                guard status == noErr else { return status }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                // Carbon events are delivered on the main thread.
                MainActor.assumeIsolated { manager.actions[hotKeyID.id]?() }
                return noErr
            },
            1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    /// Replaces all registered hotkeys. Returns the IDs of shortcuts macOS
    /// refused, for example a combo another app already registered.
    @discardableResult
    func register(_ shortcuts: [Shortcut], action: @escaping @MainActor (Shortcut) -> Void) -> Set<Shortcut.ID> {
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        actions = [:]
        var refused = Set<Shortcut.ID>()

        for (index, shortcut) in shortcuts.enumerated() {
            guard let keyCode = KeyCodes.code(for: shortcut.key) else { continue }
            let id = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(keyCode), Self.carbonFlags(shortcut.modifiers),
                EventHotKeyID(signature: Self.signature, id: id),
                GetApplicationEventTarget(), 0, &ref)
            guard status == noErr, let ref else {
                refused.insert(shortcut.id)
                continue
            }
            refs.append(ref)
            actions[id] = { action(shortcut) }
        }
        return refused
    }

    /// Combos macOS itself uses (System Settings → Keyboard → Keyboard
    /// Shortcuts: Mission Control, Spaces, screenshots, input sources…), in
    /// `Shortcut.combo` form. These usually take priority over app hotkeys,
    /// and registering one doesn't fail, so this is the only way to tell.
    /// Not complete: Spotlight's ⌘Space, for one, isn't listed.
    static func systemCombos() -> Set<String> {
        var list: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&list) == noErr,
              let entries = list?.takeRetainedValue() as? [[String: Any]]
        else { return [] }

        let known = cmdKey | shiftKey | optionKey | controlKey
        var combos = Set<String>()
        for entry in entries {
            guard entry[kHISymbolicHotKeyEnabled as String] as? Bool == true,
                  let code = entry[kHISymbolicHotKeyCode as String] as? Int,
                  let flags = entry[kHISymbolicHotKeyModifiers as String] as? Int,
                  // Entries that also need Fn (window tiling's Fn⌃←) or other
                  // bits are different combos from the ones Shortcut can express.
                  flags & ~known == 0
            else { continue }
            var modifiers = Set<Modifier>()
            if flags & cmdKey != 0 { modifiers.insert(.command) }
            if flags & shiftKey != 0 { modifiers.insert(.shift) }
            if flags & optionKey != 0 { modifiers.insert(.option) }
            if flags & controlKey != 0 { modifiers.insert(.control) }
            combos.insert(Shortcut.combo(modifiers: modifiers, code: code))
        }
        return combos
    }

    private static func carbonFlags(_ modifiers: Set<Modifier>) -> UInt32 {
        var flags = 0
        if modifiers.contains(.command) { flags |= cmdKey }
        if modifiers.contains(.shift) { flags |= shiftKey }
        if modifiers.contains(.option) { flags |= optionKey }
        if modifiers.contains(.control) { flags |= controlKey }
        return UInt32(flags)
    }
}
