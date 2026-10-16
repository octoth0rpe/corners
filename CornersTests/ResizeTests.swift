import AppKit
import Testing

/// Grow/Shrink on a 2000×1000 usable area at the origin. Frames are AppKit
/// coordinates (y up), so "top" is maxY = 1000. A step is 10% of the screen:
/// 200 points wide, 100 tall.
struct ResizeTests {
    let area = NSRect(x: 0, y: 0, width: 2000, height: 1000)

    let leftHalf = NSRect(x: 0, y: 0, width: 1000, height: 1000)
    let rightHalf = NSRect(x: 1000, y: 0, width: 1000, height: 1000)
    let topLeftCorner = NSRect(x: 0, y: 500, width: 1000, height: 500)
    let floating = NSRect(x: 600, y: 300, width: 800, height: 400)

    private func frame(_ resize: Resize, _ window: NSRect) -> NSRect {
        resize.plan(for: window, in: area).frame
    }

    // MARK: Flush edges stay put

    @Test func leftHalfGrowsRight() {
        #expect(frame(.grow, leftHalf) == NSRect(x: 0, y: 0, width: 1200, height: 1000))
    }

    @Test func rightHalfGrowsLeft() {
        #expect(frame(.grow, rightHalf) == NSRect(x: 800, y: 0, width: 1200, height: 1000))
    }

    @Test func rightHalfShrinksTowardRightEdge() {
        #expect(frame(.shrink, rightHalf) == NSRect(x: 1200, y: 0, width: 800, height: 1000))
    }

    @Test func cornerGrowsAndShrinksInItsCorner() {
        #expect(frame(.grow, topLeftCorner) == NSRect(x: 0, y: 400, width: 1200, height: 600))
        #expect(frame(.shrink, topLeftCorner) == NSRect(x: 0, y: 600, width: 800, height: 400))
    }

    @Test func floatingWindowResizesAroundItsCenter() {
        #expect(frame(.grow, floating) == NSRect(x: 500, y: 250, width: 1000, height: 500))
        #expect(frame(.shrink, floating) == NSRect(x: 700, y: 350, width: 600, height: 300))
    }

    // MARK: Full axes (option 2 in Resize.swift)

    @Test func fullHeightDoesNotShrink() {
        #expect(frame(.shrink, leftHalf) == NSRect(x: 0, y: 0, width: 800, height: 1000))
    }

    @Test func maximizedShrinksEvenlyAndGrowUndoesIt() {
        let shrunk = frame(.shrink, area)
        #expect(shrunk == NSRect(x: 100, y: 50, width: 1800, height: 900))
        #expect(frame(.grow, shrunk) == area)
    }

    @Test func maximizedGrowIsUnchanged() {
        #expect(frame(.grow, area) == area)
    }

    // MARK: Limits

    @Test func growStopsAtTheScreenEdge() {
        let wide = NSRect(x: 0, y: 0, width: 1900, height: 1000)
        #expect(frame(.grow, wide) == area)
    }

    @Test func growNearAnEdgeIsPushedBackOnScreen() {
        // 50 points from the right edge: not flush, so it grows around its
        // center, then moves left to stay on screen.
        let nearEdge = NSRect(x: 1500, y: 300, width: 450, height: 400)
        #expect(frame(.grow, nearEdge) == NSRect(x: 1350, y: 250, width: 650, height: 500))
    }

    @Test func shrinkStopsAtTenPercent() {
        let narrow = NSRect(x: 0, y: 0, width: 250, height: 1000)
        #expect(frame(.shrink, narrow) == NSRect(x: 0, y: 0, width: 200, height: 1000))
    }

    @Test func windowSmallerThanTheFloorDoesNotGrowOnShrink() {
        let tiny = NSRect(x: 900, y: 450, width: 150, height: 80)
        #expect(frame(.shrink, tiny) == tiny)
    }

    // MARK: Slack and round trips

    @Test func nearlyFlushCountsAsFlush() {
        // A terminal 10 points short of the right edge and 15 short of the
        // bottom: still anchored there, and snapped exactly to the edges.
        let terminal = NSRect(x: 1000, y: 15, width: 990, height: 985)
        #expect(frame(.grow, terminal) == NSRect(x: 810, y: 0, width: 1190, height: 1000))
    }

    @Test func growThenShrinkReturnsToTheStart() {
        var window = leftHalf
        for _ in 0..<3 { window = frame(.grow, window) }
        for _ in 0..<3 { window = frame(.shrink, window) }
        #expect(window == leftHalf)
    }

    // MARK: Realigning when the app picks its own size

    @Test func realignKeepsTheAnchoredEdgeFlush() {
        // The app won't go narrower than 900, so the right edge is kept.
        let plan = Resize.shrink.plan(for: rightHalf, in: area)
        #expect(plan.aligned(to: NSSize(width: 900, height: 1000)) == NSRect(x: 1100, y: 0, width: 900, height: 1000))
    }

    @Test func realignKeepsACenteredWindowCentered() {
        let plan = Resize.shrink.plan(for: floating, in: area)
        #expect(plan.aligned(to: NSSize(width: 700, height: 300)) == NSRect(x: 650, y: 350, width: 700, height: 300))
    }
}
