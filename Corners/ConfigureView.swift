import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

struct ConfigureView: View {
    @Environment(ConfigStore.self) private var store
    @State private var isTrusted = AccessibilityPermission.isTrusted
    @State private var isConfirmingRestore = false
    @State private var recorder = KeyRecorder()

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            if let error = store.loadError {
                ErrorBanner(message: error)
            }
            if !isTrusted {
                AccessibilityBanner()
            }

            if store.shortcuts.isEmpty {
                ContentUnavailableView(
                    "No Shortcuts", systemImage: "keyboard",
                    description: Text("Click Add Shortcut to place your first window."))
            } else {
                List {
                    ForEach($store.shortcuts) { $shortcut in
                        ShortcutRow(
                            shortcut: $shortcut,
                            problem: store.problems[shortcut.id],
                            isRecording: recorder.recordingID == shortcut.id,
                            onRecord: { recorder.toggle(shortcut.id, in: store) },
                            onDelete: { store.shortcuts.removeAll { $0.id == shortcut.id } })
                    }
                    .onDelete { store.shortcuts.remove(atOffsets: $0) }
                    .onMove { store.shortcuts.move(fromOffsets: $0, toOffset: $1) }
                }
            }

            Divider()

            HStack {
                Button("Add Shortcut", systemImage: "plus") {
                    store.shortcuts.append(Shortcut())
                }
                Spacer()
                Button("Restore Defaults…") { isConfirmingRestore = true }
                LaunchAtLoginToggle()
                Button("Show Config File") {
                    NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
                }
            }
            .padding(12)
        }
        .frame(minWidth: 640, minHeight: 260)
        .onDisappear { recorder.stop() }
        .confirmationDialog("Restore the default shortcuts?", isPresented: $isConfirmingRestore) {
            Button("Restore Defaults", role: .destructive) { store.restoreDefaults() }
        } message: {
            Text("This replaces all of your shortcuts.")
        }
        // Permission is granted in System Settings, which sends no notification
        // to the app, so check while the window is open.
        .task {
            while !Task.isCancelled {
                isTrusted = AccessibilityPermission.isTrusted
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

/// Listens for the next key press for one row at a time, with Corners'
/// own hotkeys paused so combos like ⌃⌘← reach it instead of moving a window.
@MainActor @Observable
private final class KeyRecorder {
    private(set) var recordingID: Shortcut.ID?

    @ObservationIgnored private weak var store: ConfigStore?
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var resignObserver: (any NSObjectProtocol)?

    func toggle(_ id: Shortcut.ID, in store: ConfigStore) {
        if recordingID == id {
            stop()
        } else {
            start(id, in: store)
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        monitor = nil
        resignObserver = nil
        recordingID = nil
        store?.hotKeysSuspended = false
    }

    private func start(_ id: Shortcut.ID, in store: ConfigStore) {
        stop()
        self.store = store
        recordingID = id
        store.hotKeysSuspended = true
        // Local monitors run on the main thread, before the event reaches any view.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.record(event) }
            return nil
        }
        // Key presses in other apps never arrive here, so don't leave the
        // hotkeys paused if the user switches away.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    private func record(_ event: NSEvent) {
        let code = Int(event.keyCode)
        if code == kVK_Escape {
            stop()
            return
        }
        guard let key = KeyCodes.name(forCode: code) else {
            // A keypad key, or one that types nothing.
            NSSound.beep()
            return
        }
        if let store, let index = store.shortcuts.firstIndex(where: { $0.id == recordingID }) {
            store.shortcuts[index].key = key
            // Held modifiers become the combo; a bare key keeps the toggles as they are.
            let modifiers = Self.modifiers(event.modifierFlags)
            if !modifiers.isEmpty { store.shortcuts[index].modifiers = modifiers }
        }
        stop()
    }

    private static func modifiers(_ flags: NSEvent.ModifierFlags) -> Set<Modifier> {
        var modifiers = Set<Modifier>()
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        return modifiers
    }
}

private struct ShortcutRow: View {
    @Binding var shortcut: Shortcut
    let problem: ShortcutProblem?
    let isRecording: Bool
    let onRecord: () -> Void
    let onDelete: () -> Void

    private var keyIsInvalid: Bool {
        !shortcut.key.isEmpty && KeyCodes.code(for: shortcut.key) == nil
    }

    private var keyLabel: String {
        if isRecording { return "Press a key…" }
        if shortcut.key.isEmpty { return "Record Key" }
        return KeyCodes.displayName(for: shortcut.key)
    }

    var body: some View {
        HStack(spacing: 6) {
            // Rows drag from anywhere that isn't a control; the grip just shows that.
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .help("Drag to reorder")

            ForEach(Modifier.allCases, id: \.self) { modifier in
                Toggle(modifier.symbol, isOn: binding(for: modifier))
                    .toggleStyle(.button)
                    .help(modifier.name)
            }

            Button(action: onRecord) {
                Text(keyLabel)
                    .foregroundStyle(isRecording || shortcut.key.isEmpty ? .secondary : .primary)
                    .frame(width: 84)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isRecording ? Color.accentColor : .red, lineWidth: isRecording ? 2 : 1)
                    .opacity(isRecording || keyIsInvalid ? 1 : 0)
            }
            .help(isRecording
                  ? "Press the key for this shortcut, with modifiers if you like. Esc cancels."
                  : keyIsInvalid
                  ? "Unknown key “\(shortcut.key)” in config.toml. Click to record a new one."
                  : "Click, then press a key to use it")

            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)

            ActionPicker(action: $shortcut.action)

            if let problem {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help(problem.message)
                    .accessibilityLabel(problem.message)
            }

            Button("Delete", systemImage: "minus.circle", action: onDelete)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Delete this shortcut")
        }
        .padding(.vertical, 2)
    }

    private func binding(for modifier: Modifier) -> Binding<Bool> {
        Binding {
            shortcut.modifiers.contains(modifier)
        } set: { isOn in
            if isOn { shortcut.modifiers.insert(modifier) } else { shortcut.modifiers.remove(modifier) }
        }
    }
}

/// A pop-up of presets and resizes plus a thumbnail of the screen. Choosing
/// Custom… or clicking the thumbnail opens an editor for any rectangle.
private struct ActionPicker: View {
    @Binding var action: Action
    @State private var isEditing = false

    /// Pop-up tags: a preset's ID, "resize.grow" or "resize.shrink", or nil
    /// (Custom…) for any other placement.
    private var selection: Binding<String?> {
        Binding {
            switch action {
            case let .place(placement): Preset.matching(placement)?.id
            case let .resize(resize): Self.tag(for: resize)
            }
        } set: { tag in
            if let preset = Preset.all.first(where: { $0.id == tag }) {
                action = .place(preset.placement)
            } else if let resize = Resize.allCases.first(where: { Self.tag(for: $0) == tag }) {
                action = .resize(resize)
            } else {
                isEditing = true
            }
        }
    }

    /// The placement being edited. A resize has none, so Custom… starts from
    /// the whole screen.
    private var placement: Binding<Placement> {
        Binding {
            if case let .place(placement) = action { placement } else { Preset.maximize.placement }
        } set: {
            action = .place($0)
        }
    }

    private static func tag(for resize: Resize) -> String {
        "resize.\(resize.rawValue)"
    }

    var body: some View {
        HStack(spacing: 8) {
            Picker("Action", selection: selection) {
                ForEach(Preset.groups, id: \.self) { group in
                    Section {
                        ForEach(group) { preset in
                            Label {
                                Text(preset.name)
                            } icon: {
                                Image(nsImage: PresetIcon.image(for: preset))
                            }
                            .tag(Optional(preset.id))
                        }
                    }
                }
                Section {
                    ForEach(Resize.allCases, id: \.self) { resize in
                        Label(resize.name, systemImage: resize.systemImage)
                            .tag(Optional(Self.tag(for: resize)))
                    }
                }
                Section {
                    Text("Custom…").tag(String?.none)
                }
            }
            .labelsHidden()
            // Fill the row, so every pop-up is the same width whatever it shows.
            .frame(maxWidth: .infinity)

            Group {
                if case let .resize(resize) = action {
                    ResizeThumbnail(resize: resize)
                        .help("Edges flush with the screen stay in place")
                } else {
                    Button {
                        isEditing = true
                    } label: {
                        PlacementThumbnail(placement: placement.wrappedValue)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Edit the position")
                }
            }
            .frame(width: 44, height: 28)
            .popover(isPresented: $isEditing, arrowEdge: .bottom) {
                PlacementEditor(placement: placement)
            }
        }
    }
}

/// The screen thumbnail for Grow and Shrink: the resize symbol on a screen.
private struct ResizeThumbnail: View {
    let resize: Resize

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.tileSecondary)
            .overlay {
                Image(systemName: resize.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.tilePrimary)
            }
            .accessibilityLabel(resize.name)
    }
}

/// Draw a rectangle on a large preview, or type exact percentages.
private struct PlacementEditor: View {
    @Binding var placement: Placement

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PlacementCanvas(placement: $placement)
                .frame(width: 256, height: 160)

            Text("Drag to draw a rectangle, or enter percentages of the screen.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 256, alignment: .leading)

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    field("X", placement.x) { placement.with(x: $0) }
                    field("Width", placement.width) { placement.with(width: $0) }
                }
                GridRow {
                    field("Y", placement.y) { placement.with(y: $0) }
                    field("Height", placement.height) { placement.with(height: $0) }
                }
            }
        }
        .padding(16)
    }

    private func field(_ label: String, _ value: Double, apply: @escaping (Double) -> Placement) -> some View {
        let binding = Binding { value } set: { placement = apply($0).clamped }
        return Group {
            Text(label)
                .gridColumnAlignment(.trailing)
            HStack(spacing: 2) {
                TextField(label, value: binding, format: .number.precision(.fractionLength(0...3)))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                Text("%").foregroundStyle(.secondary)
                Stepper(label, value: binding, in: 0...100, step: 5)
                    .labelsHidden()
            }
        }
    }
}

/// The large preview in the editor. Dragging draws a new rectangle, snapped
/// to 5% steps.
private struct PlacementCanvas: View {
    @Binding var placement: Placement

    var body: some View {
        GeometryReader { geometry in
            PlacementThumbnail(placement: placement, showsGrid: true, cornerRadius: 8)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { drag in
                            draw(from: drag.startLocation, to: drag.location, in: geometry.size)
                        }
                )
        }
    }

    private func draw(from start: CGPoint, to end: CGPoint, in size: CGSize) {
        func snap(_ value: CGFloat, _ length: CGFloat) -> Double {
            min(max((value / length * 100 / 5).rounded() * 5, 0), 100)
        }
        let x0 = snap(start.x, size.width), x1 = snap(end.x, size.width)
        let y0 = snap(start.y, size.height), y1 = snap(end.y, size.height)
        guard x0 != x1, y0 != y1 else { return }
        placement = Placement(x: min(x0, x1), y: min(y0, y1), width: abs(x1 - x0), height: abs(y1 - y0))
    }
}

/// A screen with the placement filled in, in the app icon's colors.
struct PlacementThumbnail: View {
    let placement: Placement
    var showsGrid = false
    var cornerRadius: CGFloat = 4

    var body: some View {
        Canvas { context, size in
            let screen = CGRect(origin: .zero, size: size)
            context.fill(RoundedRectangle(cornerRadius: cornerRadius).path(in: screen),
                         with: .color(.tileSecondary))

            let inner = screen.insetBy(dx: 2, dy: 2)
            if showsGrid {
                var grid = Path()
                for step in stride(from: 0.25, to: 1, by: 0.25) {
                    grid.move(to: CGPoint(x: inner.minX + inner.width * step, y: inner.minY))
                    grid.addLine(to: CGPoint(x: inner.minX + inner.width * step, y: inner.maxY))
                    grid.move(to: CGPoint(x: inner.minX, y: inner.minY + inner.height * step))
                    grid.addLine(to: CGPoint(x: inner.maxX, y: inner.minY + inner.height * step))
                }
                context.stroke(grid, with: .color(.tilePrimary.opacity(0.25)), lineWidth: 1)
            }

            let window = CGRect(
                x: inner.minX + inner.width * placement.x / 100,
                y: inner.minY + inner.height * placement.y / 100,
                width: inner.width * placement.width / 100,
                height: inner.height * placement.height / 100)
            context.fill(RoundedRectangle(cornerRadius: max(cornerRadius - 2, 1)).path(in: window.insetBy(dx: 0.5, dy: 0.5)),
                         with: .color(.tilePrimary))
        }
        .accessibilityLabel(Preset.matching(placement)?.name ?? "Custom position")
    }
}

/// Small template images of each preset for the pop-up's menu items.
@MainActor
private enum PresetIcon {
    private static var cache: [String: NSImage] = [:]

    static func image(for preset: Preset) -> NSImage {
        if let image = cache[preset.id] { return image }
        let p = preset.placement
        let image = NSImage(size: NSSize(width: 18, height: 12), flipped: true) { rect in
            let screen = rect.insetBy(dx: 0.75, dy: 0.75)
            NSColor.black.setStroke()
            let outline = NSBezierPath(roundedRect: screen, xRadius: 2, yRadius: 2)
            outline.lineWidth = 1.5
            outline.stroke()
            let inner = screen.insetBy(dx: 2, dy: 2)
            NSColor.black.setFill()
            NSRect(x: inner.minX + inner.width * p.x / 100, y: inner.minY + inner.height * p.y / 100,
                   width: inner.width * p.width / 100, height: inner.height * p.height / 100).fill()
            return true
        }
        image.isTemplate = true
        cache[preset.id] = image
        return image
    }
}

extension Color {
    /// The lit tile in the app icon.
    static let tilePrimary = Color(nsColor: .dynamic(light: 0x138A68, dark: 0x3CC79C))
    /// The other tiles in the app icon.
    static let tileSecondary = Color(nsColor: .dynamic(light: 0xB5DCCB, dark: 0x24493D))
}

private extension NSColor {
    static func dynamic(light: Int, dark: Int) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
    }
}

private struct AccessibilityBanner: View {
    var body: some View {
        HStack {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(.blue)
            Text("Corners needs Accessibility permission to move windows.")
            Spacer()
            Button("Open System Settings…") {
                AccessibilityPermission.openSettings()
            }
        }
        .font(.callout)
        .padding(10)
        .background(.blue.opacity(0.1))
    }
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("config.toml has a problem, so Corners is still using the last working shortcuts.")
                    .bold()
                Text(message)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .font(.callout)
        .padding(10)
        .background(.yellow.opacity(0.12))
    }
}

private struct LaunchAtLoginToggle: View {
    @State private var isEnabled = SMAppService.mainApp.status == .enabled
    @State private var error: String?

    var body: some View {
        Toggle("Launch at login", isOn: Binding {
            isEnabled
        } set: { enable in
            do {
                if enable {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                self.error = error.localizedDescription
            }
            isEnabled = SMAppService.mainApp.status == .enabled
        })
        .onAppear { isEnabled = SMAppService.mainApp.status == .enabled }
        .alert("Couldn't change login item", isPresented: Binding {
            error != nil
        } set: { if !$0 { error = nil } }) {
            Button("Open Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }
}
