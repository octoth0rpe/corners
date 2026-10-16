import AppKit
import ApplicationServices
import OSLog

/// Moves and resizes the frontmost window through the Accessibility API.
///
/// The Accessibility API uses global coordinates with the origin at the top
/// left of the primary screen and y pointing down. AppKit's NSScreen uses the
/// bottom left of the primary screen with y pointing up. Everything here is
/// converted to AppKit coordinates to pick the screen and the target, then
/// back to set the frame.
@MainActor
enum WindowMover {
    static func move(to placement: Placement) {
        guard let front = FrontWindow.current() else { return }
        front.setFrame(placement.rect(in: front.screen.visibleFrame))
    }

    static func resize(_ resize: Resize) {
        guard let front = FrontWindow.current() else { return }
        let plan = resize.plan(for: front.frame, in: front.screen.visibleFrame)
        guard let actual = front.setFrame(plan.frame), actual.size != plan.frame.size else { return }
        // The app settled on another size (a minimum size, or terminal cells).
        // Move it so the anchored edges are where they should be.
        front.setFrame(plan.aligned(to: actual.size))
    }

    /// The frontmost app's focused window, its frame in AppKit coordinates,
    /// and the screen it's on.
    @MainActor
    private struct FrontWindow {
        let app: NSRunningApplication
        let appElement: AXUIElement
        let window: AXUIElement
        let frame: NSRect
        let screen: NSScreen

        static func current() -> FrontWindow? {
            guard AccessibilityPermission.isTrusted else {
                AccessibilityPermission.prompt()
                return nil
            }
            guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            guard let window = WindowMover.frontWindow(of: appElement) else {
                log.notice("No window to move in \(app.localizedName ?? "?", privacy: .public)")
                return nil
            }
            if let fullScreen: Bool = window.value(of: "AXFullScreen"), fullScreen {
                log.notice("\(app.localizedName ?? "?", privacy: .public): window is full screen")
                return nil
            }
            guard let frame = frame(of: window), let screen = WindowMover.screen(for: frame) else {
                log.notice("\(app.localizedName ?? "?", privacy: .public): can't read the window's frame")
                return nil
            }
            return FrontWindow(app: app, appElement: appElement, window: window, frame: frame, screen: screen)
        }

        /// Sets the window's frame (AppKit coordinates) and returns the frame it
        /// actually ended up with.
        @discardableResult
        func setFrame(_ target: NSRect) -> NSRect? {
            guard let flipY = NSScreen.screens.first?.frame.maxY else { return nil }
            let origin = CGPoint(x: target.minX, y: flipY - target.maxY)

            // With AXEnhancedUserInterface on (set by assistive apps, and by some
            // apps on themselves), apps such as Chrome and Electron apps animate
            // each change and drop some. Turn it off while moving.
            let enhanced: Bool = appElement.value(of: "AXEnhancedUserInterface") ?? false
            if enhanced { appElement.set("AXEnhancedUserInterface", to: false as CFBoolean) }
            defer { if enhanced { appElement.set("AXEnhancedUserInterface", to: true as CFBoolean) } }

            // Size, move, then size again: an app can refuse a size that doesn't
            // fit at the old position (near a screen edge, or on a smaller screen),
            // so the second call applies it once the window is in place.
            let results = [
                window.set(kAXSizeAttribute, to: target.size),
                window.set(kAXPositionAttribute, to: origin),
                window.set(kAXSizeAttribute, to: target.size),
            ]

            let actual = Self.frame(of: window)
            // Debug level isn't stored; stream it with
            // `log stream --level debug --predicate 'subsystem == "com.octoth0rpe.corners"'`.
            log.debug("""
                \(app.localizedName ?? "?", privacy: .public) (\(app.bundleIdentifier ?? "?", privacy: .public)): \
                from \(String(describing: frame), privacy: .public) \
                to \(String(describing: target), privacy: .public) \
                → \(String(describing: actual), privacy: .public) \
                results \(results.map(\.rawValue), privacy: .public) enhanced=\(enhanced) \
                screen=\(screen.localizedName, privacy: .public)
                """)
            return actual
        }

        private static func frame(of window: AXUIElement) -> NSRect? {
            guard let position: CGPoint = window.value(of: kAXPositionAttribute),
                  let size: CGSize = window.value(of: kAXSizeAttribute),
                  let flipY = NSScreen.screens.first?.frame.maxY
            else { return nil }
            return NSRect(x: position.x, y: flipY - position.y - size.height, width: size.width, height: size.height)
        }
    }

    /// The focused window, or the main window when nothing has focus.
    private static func frontWindow(of app: AXUIElement) -> AXUIElement? {
        if let window: AXUIElement = app.value(of: kAXFocusedWindowAttribute) { return window }
        if let window: AXUIElement = app.value(of: kAXMainWindowAttribute) { return window }
        let systemWide = AXUIElementCreateSystemWide()
        if let focusedApp: AXUIElement = systemWide.value(of: kAXFocusedApplicationAttribute),
           let window: AXUIElement = focusedApp.value(of: kAXFocusedWindowAttribute) {
            return window
        }
        if let windows: [AXUIElement] = app.value(of: kAXWindowsAttribute), let first = windows.first {
            return first
        }
        log.notice("""
            No window: focused=\(app.error(of: kAXFocusedWindowAttribute)) \
            main=\(app.error(of: kAXMainWindowAttribute)) \
            windows=\(app.error(of: kAXWindowsAttribute)) \
            role=\(app.error(of: kAXRoleAttribute)) \
            systemWideApp=\(systemWide.error(of: kAXFocusedApplicationAttribute))
            """)
        return nil
    }

    /// The screen showing the most of `frame`, or the one under its center.
    private static func screen(for frame: NSRect) -> NSScreen? {
        let best = NSScreen.screens.max { area($0.frame.intersection(frame)) < area($1.frame.intersection(frame)) }
        if let best, area(best.frame.intersection(frame)) > 0 { return best }
        let center = NSPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
    }

    private static func area(_ rect: NSRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }
}

private extension AXUIElement {
    /// The raw AXError from reading an attribute, for logging.
    func error(of attribute: String) -> Int32 {
        var raw: CFTypeRef?
        return AXUIElementCopyAttributeValue(self, attribute as CFString, &raw).rawValue
    }

    func value<T>(of attribute: String) -> T? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &raw) == .success,
              let raw
        else { return nil }

        if CFGetTypeID(raw) == AXValueGetTypeID() {
            let axValue = raw as! AXValue
            switch T.self {
            case is CGPoint.Type:
                var point = CGPoint.zero
                return AXValueGetValue(axValue, .cgPoint, &point) ? point as? T : nil
            case is CGSize.Type:
                var size = CGSize.zero
                return AXValueGetValue(axValue, .cgSize, &size) ? size as? T : nil
            default:
                return nil
            }
        }
        return raw as? T
    }

    @discardableResult
    func set(_ attribute: String, to value: CGPoint) -> AXError {
        var value = value
        guard let axValue = AXValueCreate(.cgPoint, &value) else { return .failure }
        return AXUIElementSetAttributeValue(self, attribute as CFString, axValue)
    }

    @discardableResult
    func set(_ attribute: String, to value: CGSize) -> AXError {
        var value = value
        guard let axValue = AXValueCreate(.cgSize, &value) else { return .failure }
        return AXUIElementSetAttributeValue(self, attribute as CFString, axValue)
    }

    @discardableResult
    func set(_ attribute: String, to value: CFTypeRef) -> AXError {
        AXUIElementSetAttributeValue(self, attribute as CFString, value)
    }
}

/// Whether macOS lets Corners control other apps' windows
/// (System Settings → Privacy & Security → Accessibility).
@MainActor
enum AccessibilityPermission {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that offers to open System Settings, and adds
    /// Corners to the Accessibility list (switched off) so it's easy to find.
    static func prompt() {
        // The literal value of kAXTrustedCheckOptionPrompt, which Swift 6
        // won't read because it's a mutable global.
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func openSettings() {
        prompt()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

private let log = Logger(subsystem: "com.octoth0rpe.corners", category: "windows")
