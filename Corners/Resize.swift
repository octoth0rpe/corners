import AppKit

/// Grows or shrinks a window by a step of the screen's size, keeping any edge
/// that's flush with the screen where it is.
///
/// Each axis is handled on its own:
/// - One edge flush with the screen: that edge stays, the other moves.
/// - Neither edge flush: the window grows or shrinks evenly around its center.
/// - Growing stops at the screen's edges. Once an edge reaches one, it's flush
///   and anchors from then on.
/// - Windows never shrink below `minimumFraction` of the screen (or their
///   current size, if they're already smaller).
///
/// The open question is shrinking an axis whose edges are *both* flush, such
/// as the height of a left half or both axes of a maximized window. The
/// options considered (2026-10-15):
///
/// 1. A full axis never shrinks. A left half only gets narrower; a maximized
///    window doesn't change at all. Simple, but Shrink seems broken on a
///    maximized window.
/// 2. A full axis never shrinks, unless both axes are full. A left half only
///    gets narrower; a maximized window shrinks evenly to 90% × 90%, centered.
///    Grow then undoes it exactly.
/// 3. A full axis shrinks evenly from both ends. A left half becomes 40% × 90%,
///    left edge kept, centered vertically. The most uniform rule (grow and
///    shrink are exact mirrors), but halves lose their full height.
/// 4. A full axis shrinks from its far end (the right or top edge moves). A
///    left half becomes 40% × 90% in the top left. Stays in a corner, but
///    which corner is arbitrary and Grow doesn't undo it exactly.
///
/// Chosen: option 2, in `shrinksFullAxes(horizontal:vertical:)`. Revisit after
/// living with it for a while.
enum Resize: String, CaseIterable, Hashable {
    case grow
    case shrink

    /// How much one press changes each side, as a fraction of the screen.
    static let step: CGFloat = 0.10
    static let minimumFraction: CGFloat = 0.10
    /// How far from a screen edge still counts as flush. Terminals size
    /// themselves in whole character cells and can stop a line short of an
    /// edge they were sent to.
    static let flushTolerance: CGFloat = 20

    var name: String {
        switch self {
        case .grow: "Grow 10%"
        case .shrink: "Shrink 10%"
        }
    }

    var systemImage: String {
        switch self {
        case .grow: "arrow.up.left.and.arrow.down.right"
        case .shrink: "arrow.down.right.and.arrow.up.left"
        }
    }

    /// Where an axis is pinned, so the window can be realigned if the app
    /// doesn't take the exact size asked for (a minimum size, or terminal cells).
    enum Anchor {
        case start, end, center
    }

    struct Plan {
        var frame: NSRect
        var horizontal: Anchor
        var vertical: Anchor
        let area: NSRect

        /// `frame` moved so its anchored edges (or center) stay put for a
        /// window that ended up `size` instead.
        func aligned(to size: NSSize) -> NSRect {
            func align(_ start: CGFloat, _ length: CGFloat, _ actual: CGFloat, _ anchor: Anchor,
                       _ areaStart: CGFloat, _ areaLength: CGFloat) -> CGFloat {
                let aligned = switch anchor {
                case .start: start
                case .end: start + length - actual
                case .center: start + (length - actual) / 2
                }
                // Keep it on screen if it fits.
                guard actual <= areaLength else { return areaStart }
                return min(max(aligned, areaStart), areaStart + areaLength - actual).rounded()
            }
            return NSRect(
                x: align(frame.minX, frame.width, size.width, horizontal, area.minX, area.width),
                y: align(frame.minY, frame.height, size.height, vertical, area.minY, area.height),
                width: size.width, height: size.height)
        }
    }

    /// The new frame for `window` on a screen whose usable area is `area`.
    /// Both are in AppKit coordinates; only the direction of y differs from
    /// the Accessibility API's, and nothing here depends on it.
    func plan(for window: NSRect, in area: NSRect) -> Plan {
        let tolerance = Self.flushTolerance
        let fullX = window.minX <= area.minX + tolerance && window.maxX >= area.maxX - tolerance
        let fullY = window.minY <= area.minY + tolerance && window.maxY >= area.maxY - tolerance
        let lockFull = self == .shrink && !Self.shrinksFullAxes(horizontal: fullX, vertical: fullY)

        let x = axis(start: window.minX - area.minX, length: window.width, area: area.width, lockFull: lockFull)
        let y = axis(start: window.minY - area.minY, length: window.height, area: area.height, lockFull: lockFull)
        return Plan(
            frame: NSRect(x: area.minX + x.start, y: area.minY + y.start, width: x.length, height: y.length),
            horizontal: x.anchor, vertical: y.anchor, area: area)
    }

    /// Option 2 above: a full axis shrinks only when the other one is full too.
    private static func shrinksFullAxes(horizontal: Bool, vertical: Bool) -> Bool {
        horizontal && vertical
    }

    /// One axis, in points from the start of the usable area.
    private func axis(start: CGFloat, length: CGFloat, area: CGFloat, lockFull: Bool)
        -> (start: CGFloat, length: CGFloat, anchor: Anchor)
    {
        let tolerance = Self.flushTolerance
        let flushStart = start <= tolerance
        let flushEnd = start + length >= area - tolerance
        if flushStart && flushEnd && lockFull {
            return (0, area, .start)
        }

        let delta = area * Self.step * (self == .grow ? 1 : -1)
        let floor = min(length, area * Self.minimumFraction)
        let newLength = min(max(length + delta, floor), area)

        let anchor: Anchor = switch (flushStart, flushEnd) {
        case (true, false): .start
        case (false, true): .end
        default: .center
        }
        var newStart: CGFloat = switch anchor {
        case .start: 0
        case .end: area - newLength
        case .center: start + (length - newLength) / 2
        }
        newStart = min(max(newStart, 0), area - newLength)

        // Round the edges, not the length, so flush edges land exactly.
        let left = newStart.rounded()
        let right = (newStart + newLength).rounded()
        return (left, right - left, anchor)
    }
}
