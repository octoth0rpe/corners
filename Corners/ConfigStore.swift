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

    private func registerHotKeys() {
        hotKeys.register(hotKeysSuspended ? [] : shortcuts.filter(\.isComplete)) { shortcut in
            switch shortcut.action {
            case let .place(placement): WindowMover.move(to: placement)
            case let .resize(resize): WindowMover.resize(resize)
            }
        }
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
