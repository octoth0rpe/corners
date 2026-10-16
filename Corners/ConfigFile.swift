import Foundation
import TOMLKit

enum ConfigError: LocalizedError {
    case unknownModifier(String, in: String)
    case invalidFrame(in: String)

    var errorDescription: String? {
        switch self {
        case let .unknownModifier(token, keys):
            "Unknown modifier “\(token)” in “\(keys)”. Use cmd, shift, opt or ctrl."
        case let .invalidFrame(keys):
            "The frame for “\(keys)” doesn't fit on the screen. x + width and y + height "
                + "can be at most 100, and width and height must be more than 0."
        }
    }
}

/// Reads and writes config.toml.
///
///     [[shortcut]]
///     keys  = "ctrl+cmd+left"
///     frame = { x = 0, y = 0, width = 50, height = 100 }
enum ConfigFile {
    private struct File: Decodable {
        var shortcut: [Entry]?
    }

    private struct Entry: Decodable {
        var keys: String
        var frame: Frame
    }

    private struct Frame: Decodable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double

        private enum CodingKeys: String, CodingKey { case x, y, width, height }

        /// TOML keeps integers and floats apart, and TOMLKit won't read `50`
        /// as a Double, so accept either.
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func number(_ key: CodingKeys) throws -> Double {
                if let int = try? c.decode(Int.self, forKey: key) { return Double(int) }
                return try c.decode(Double.self, forKey: key)
            }
            x = try number(.x)
            y = try number(.y)
            width = try number(.width)
            height = try number(.height)
        }
    }

    static func parse(_ text: String) throws -> [Shortcut] {
        let file = try TOMLDecoder().decode(File.self, from: text)
        return try (file.shortcut ?? []).map { entry in
            let f = entry.frame
            let placement = Placement(x: f.x, y: f.y, width: f.width, height: f.height)
            guard placement.isValid else { throw ConfigError.invalidFrame(in: entry.keys) }
            return try Shortcut(keys: entry.keys, placement: placement)
        }
    }

    /// Written by hand rather than with TOMLEncoder to keep the file
    /// readable: a header, `[[shortcut]]` tables, and preset-name comments.
    static func render(_ shortcuts: [Shortcut]) -> String {
        var out = """
            # Corners shortcuts. Corners reloads this file whenever it changes.
            #
            # keys:  modifiers and a key joined with "+". Modifiers are cmd, shift,
            #        opt and ctrl. Keys are a single character (a, 1, ', /) or a name:
            #        space, return, tab, escape, delete, up, down, left, right,
            #        home, end, pageup, pagedown, f1–f20. Shifted characters
            #        work too: "cmd+|" means "cmd+shift+\" on a US layout.
            # frame: where the frontmost window goes, in percent of the usable area
            #        of the screen it's on (not counting the menu bar and Dock).
            #        x and y are measured from the top-left corner.
            #
            # [[shortcut]]
            # keys  = "ctrl+cmd+left"
            # frame = { x = 0, y = 0, width = 50, height = 100 }

            """
        for shortcut in shortcuts {
            let p = shortcut.placement
            out += "\n"
            if let preset = Preset.matching(p) {
                out += "# \(preset.name)\n"
            }
            out += """
                [[shortcut]]
                keys  = \(quote(shortcut.keys))
                frame = { x = \(number(p.x)), y = \(number(p.y)), width = \(number(p.width)), height = \(number(p.height)) }

                """
        }
        return out
    }

    /// Whole numbers without a decimal point, others to three places: 50, 33.333.
    private static func number(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        var s = String(format: "%.3f", value)
        while s.hasSuffix("0") { s.removeLast() }
        return s
    }

    /// A TOML basic string.
    private static func quote(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case _ where scalar.value < 0x20 || scalar.value == 0x7F:
                out += String(format: "\\u%04X", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }
}
