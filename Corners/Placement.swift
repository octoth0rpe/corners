import AppKit

/// Where a window goes, as percentages of the screen's usable area (the
/// screen minus the menu bar and Dock), measured from its top-left corner.
///
/// Values are rounded to three decimals so thirds survive a round trip
/// through config.toml unchanged.
struct Placement: Hashable {
    private(set) var x: Double
    private(set) var y: Double
    private(set) var width: Double
    private(set) var height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = Self.round(x)
        self.y = Self.round(y)
        self.width = Self.round(width)
        self.height = Self.round(height)
    }

    /// True when the rectangle has a size and fits on the screen.
    var isValid: Bool {
        let tolerance = 0.001
        return x >= 0 && y >= 0 && width > 0 && height > 0
            && x + width <= 100 + tolerance && y + height <= 100 + tolerance
    }

    /// Pulled back onto the screen, at least 1% in each direction.
    var clamped: Placement {
        let x = min(max(x, 0), 99)
        let y = min(max(y, 0), 99)
        return Placement(x: x, y: y, width: min(max(width, 1), 100 - x), height: min(max(height, 1), 100 - y))
    }

    func with(x: Double? = nil, y: Double? = nil, width: Double? = nil, height: Double? = nil) -> Placement {
        Placement(x: x ?? self.x, y: y ?? self.y, width: width ?? self.width, height: height ?? self.height)
    }

    /// The target rectangle inside `area`, in AppKit coordinates (origin at the
    /// bottom left, y up). Edges are rounded rather than the size, so two
    /// halves always meet exactly.
    func rect(in area: NSRect) -> NSRect {
        let left = (area.minX + area.width * x / 100).rounded()
        let right = (area.minX + area.width * (x + width) / 100).rounded()
        let top = (area.maxY - area.height * y / 100).rounded()
        let bottom = (area.maxY - area.height * (y + height) / 100).rounded()
        return NSRect(x: left, y: bottom, width: right - left, height: top - bottom)
    }

    private static func round(_ value: Double) -> Double {
        (value * 1000).rounded() / 1000
    }
}

/// Named placements offered in the Configure window's pop-up.
struct Preset: Identifiable, Hashable {
    let name: String
    let placement: Placement
    var id: String { name }

    init(_ name: String, x: Double, y: Double, width: Double, height: Double) {
        self.name = name
        self.placement = Placement(x: x, y: y, width: width, height: height)
    }

    static let leftHalf = Preset("Left Half", x: 0, y: 0, width: 50, height: 100)
    static let rightHalf = Preset("Right Half", x: 50, y: 0, width: 50, height: 100)
    static let topHalf = Preset("Top Half", x: 0, y: 0, width: 100, height: 50)
    static let bottomHalf = Preset("Bottom Half", x: 0, y: 50, width: 100, height: 50)
    static let leftQuarter = Preset("Left Quarter", x: 0, y: 0, width: 25, height: 100)
    static let centerHalf = Preset("Center Half", x: 25, y: 0, width: 50, height: 100)
    static let rightQuarter = Preset("Right Quarter", x: 75, y: 0, width: 25, height: 100)
    static let maximize = Preset("Maximize", x: 0, y: 0, width: 100, height: 100)

    /// Shown in the pop-up in this order, a divider between groups.
    static let groups: [[Preset]] = [
        [maximize],
        [leftHalf, rightHalf, topHalf, bottomHalf],
        [leftQuarter, centerHalf, rightQuarter],
        [
            Preset("Left Third", x: 0, y: 0, width: 100.0 / 3, height: 100),
            Preset("Center Third", x: 100.0 / 3, y: 0, width: 100.0 / 3, height: 100),
            Preset("Right Third", x: 200.0 / 3, y: 0, width: 100.0 / 3, height: 100),
            Preset("Left Two Thirds", x: 0, y: 0, width: 200.0 / 3, height: 100),
            Preset("Right Two Thirds", x: 100.0 / 3, y: 0, width: 200.0 / 3, height: 100),
        ],
        [
            Preset("Top Left Corner", x: 0, y: 0, width: 50, height: 50),
            Preset("Top Right Corner", x: 50, y: 0, width: 50, height: 50),
            Preset("Bottom Left Corner", x: 0, y: 50, width: 50, height: 50),
            Preset("Bottom Right Corner", x: 50, y: 50, width: 50, height: 50),
        ],
    ]

    static let all = groups.flatMap { $0 }

    static func matching(_ placement: Placement) -> Preset? {
        all.first { $0.placement == placement }
    }
}
