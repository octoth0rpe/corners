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

    /// Replaces all registered hotkeys. Combos macOS refuses (for example,
    /// one already taken by another app) are skipped.
    func register(_ shortcuts: [Shortcut], action: @escaping @MainActor (Shortcut) -> Void) {
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        actions = [:]

        for (index, shortcut) in shortcuts.enumerated() {
            guard let keyCode = KeyCodes.code(for: shortcut.key) else { continue }
            let id = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(keyCode), Self.carbonFlags(shortcut.modifiers),
                EventHotKeyID(signature: Self.signature, id: id),
                GetApplicationEventTarget(), 0, &ref)
            guard status == noErr, let ref else { continue }
            refs.append(ref)
            actions[id] = { action(shortcut) }
        }
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
