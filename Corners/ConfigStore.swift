import AppKit
import Observation
import OSLog

/// Owns the shortcut list: loads it from config.toml, saves edits made in
/// the UI, reloads when the file changes on disk, and keeps the registered
/// hotkeys in sync.
@MainActor @Observable
final class ConfigStore {
    var shortcuts: [Shortcut] = [] {
        didSet {
            guard shortcuts != oldValue else { return }
            registerHotKeys()
            if !isApplyingFile { save() }
        }
    }

    /// While true no hotkeys are registered, so the key recorder in the
    /// Configure window gets every combo, including ones Corners uses.
    var hotKeysSuspended = false {
        didSet {
            guard hotKeysSuspended != oldValue else { return }
            registerHotKeys()
        }
    }

    /// Set when config.toml can't be read or parsed. The last good shortcuts stay active.
    private(set) var loadError: String?

    let fileURL: URL

    @ObservationIgnored private let hotKeys = HotKeyManager()
    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored private var isApplyingFile = false

    init() {
        // ~/Library/Application Support/Corners. (Not sandboxed; see project.yml.)
        let dir = URL.applicationSupportDirectory.appending(path: "Corners", directoryHint: .isDirectory)
        fileURL = dir.appending(path: "config.toml")

        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: fileURL.path) {
            try? ConfigFile.render(Shortcut.defaults).write(to: fileURL, atomically: true, encoding: .utf8)
        }

        reload()
        watcher = FileWatcher(url: fileURL) { [weak self] in self?.reload() }
    }

    /// Shortcuts that aren't active, and why. Shown as warnings in the Configure window.
    private(set) var problems: [Shortcut.ID: ShortcutProblem] = [:]

    private func registerHotKeys() {
        guard !hotKeysSuspended else {
            // Keep the last problems; they still describe the list being edited.
            hotKeys.register([]) { _ in }
            return
        }

        // macOS registers a combo once per app, so the first row with it wins.
        var problems: [Shortcut.ID: ShortcutProblem] = [:]
        var seen = Set<String>()
        var unique: [Shortcut] = []
        let system = HotKeyManager.systemCombos()
        for shortcut in shortcuts where shortcut.isComplete {
            guard let combo = shortcut.combo else { continue }
            if seen.insert(combo).inserted {
                unique.append(shortcut)
                // Still registered: it starts working if the macOS shortcut is turned off.
                if system.contains(combo) { problems[shortcut.id] = .systemShortcut }
            } else {
                problems[shortcut.id] = .duplicate
            }
        }

        let refused = hotKeys.register(unique) { shortcut in
            switch shortcut.action {
            case let .place(placement): WindowMover.move(to: placement)
            case let .resize(resize): WindowMover.resize(resize)
            }
        }
        for id in refused { problems[id] = .refused }
        self.problems = problems
    }

    func restoreDefaults() {
        shortcuts = Shortcut.defaults
    }

    func reload() {
        do {
            let text = try String(contentsOf: fileURL, encoding: .utf8)
            let parsed = try ConfigFile.parse(text).map(\.normalized)
            loadError = nil
            // Our own saves come back through the watcher; this skips them.
            guard parsed != shortcuts else { return }
            isApplyingFile = true
            shortcuts = parsed
            isApplyingFile = false
            log.notice("Loaded \(parsed.count) shortcuts")
        } catch {
            // DecodingError's own description names the bad key; ours read better localized.
            loadError = error is ConfigError ? error.localizedDescription : String(describing: error)
            log.error("Couldn't load config.toml: \(String(describing: error), privacy: .public)")
        }
    }

    private func save() {
        do {
            try ConfigFile.render(shortcuts).write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            loadError = "Couldn't save: \(error.localizedDescription)"
        }
    }
}

private let log = Logger(subsystem: "com.octoth0rpe.corners", category: "config")

/// Why a shortcut in the list isn't active.
enum ShortcutProblem {
    case duplicate
    case systemShortcut
    case refused

    var message: String {
        switch self {
        case .duplicate:
            "A row above uses the same keys, so this one is off."
        case .systemShortcut:
            "macOS also uses these keys, and its shortcut usually wins. Change them here, or turn "
                + "off the macOS one in System Settings → Keyboard → Keyboard Shortcuts."
        case .refused:
            "macOS wouldn't register these keys. Another app or a system shortcut probably uses them."
        }
    }
}
