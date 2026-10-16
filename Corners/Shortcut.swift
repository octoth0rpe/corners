import Foundation

enum Modifier: String, CaseIterable, Hashable {
    // Declared in the order macOS displays them: ⌃⌥⇧⌘
    case control = "ctrl"
    case option = "opt"
    case shift
    case command = "cmd"

    var symbol: String {
        switch self {
        case .control: "⌃"
        case .option: "⌥"
        case .shift: "⇧"
        case .command: "⌘"
        }
    }

    var name: String {
        switch self {
        case .control: "Control"
        case .option: "Option"
        case .shift: "Shift"
        case .command: "Command"
        }
    }

    /// Accepts the canonical name plus common aliases and symbols.
    init?(token: String) {
        switch token.lowercased() {
        case "cmd", "command", "⌘": self = .command
        case "shift", "⇧": self = .shift
        case "opt", "option", "alt", "⌥": self = .option
        case "ctrl", "control", "⌃": self = .control
        default: return nil
        }
    }
}

struct Shortcut: Identifiable {
    var id = UUID()
    var modifiers: Set<Modifier> = [.control, .command]
    var key = ""
    /// Where the frontmost window goes when the shortcut is pressed.
    var placement = Preset.maximize.placement

    /// True when the shortcut can actually be registered.
    @MainActor var isComplete: Bool {
        KeyCodes.code(for: key) != nil
    }

    /// Rewrites a shifted character as Shift plus its base key:
    /// "cmd+|" becomes "cmd+shift+\" on a US layout.
    @MainActor var normalized: Shortcut {
        guard let base = KeyCodes.unshifted(key) else { return self }
        var copy = self
        copy.key = base
        copy.modifiers.insert(.shift)
        return copy
    }

    /// The `keys` string used in the config file, e.g. "cmd+shift+k".
    var keys: String {
        (Modifier.allCases.filter(modifiers.contains).map(\.rawValue) + [key])
            .joined(separator: "+")
    }

    init() {}

    init(keys: String, placement: Placement) throws {
        var parts = keys.split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        // A trailing "++" means the plus key itself, e.g. "cmd++".
        if parts.count >= 2, parts[parts.count - 1].isEmpty, parts[parts.count - 2].isEmpty {
            parts.removeLast(2)
            parts.append("+")
        }
        self.key = parts.popLast() ?? ""
        self.modifiers = []
        for token in parts {
            guard let modifier = Modifier(token: token) else {
                throw ConfigError.unknownModifier(token, in: keys)
            }
            modifiers.insert(modifier)
        }
        self.placement = placement
    }

    private init(_ keys: String, _ preset: Preset) {
        // The defaults are known to parse.
        try! self.init(keys: keys, placement: preset.placement)
    }

    /// Written to config.toml on first launch, and by Restore Defaults.
    /// Each call makes new row IDs.
    static var defaults: [Shortcut] {
        [
            Shortcut("ctrl+cmd+left", .leftHalf),
            Shortcut("ctrl+cmd+right", .rightHalf),
            Shortcut("ctrl+cmd+up", .topHalf),
            Shortcut("ctrl+cmd+down", .bottomHalf),
            Shortcut("ctrl+opt+shift+cmd+1", .leftQuarter),
            Shortcut("ctrl+opt+shift+cmd+2", .centerHalf),
            Shortcut("ctrl+opt+shift+cmd+3", .rightQuarter),
            Shortcut("cmd+return", .maximize),
        ]
    }
}

extension Shortcut: Equatable {
    /// Compares content only, so reloading an unchanged file doesn't
    /// replace rows (and their identities) in the UI.
    static func == (a: Shortcut, b: Shortcut) -> Bool {
        a.modifiers == b.modifiers && a.key == b.key && a.placement == b.placement
    }
}
