import OSLog
import SwiftUI

@main
struct CornersApp: App {
    @State private var store = ConfigStore()

    init() {
        // Without Accessibility permission no shortcut can move a window, so
        // ask right away rather than on the first press.
        if !AccessibilityPermission.isTrusted {
            AccessibilityPermission.prompt()
        }
    }

    var body: some Scene {
        MenuBarExtra("Corners", image: "MenuBarIcon") {
            MenuContent()
        }

        Window("About Corners", id: WindowID.about) {
            AboutView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Window("Configure Shortcuts", id: WindowID.configure) {
            ConfigureView()
                .environment(store)
        }
        .defaultSize(width: 640, height: 420)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}

enum WindowID {
    static let about = "about"
    static let configure = "configure"
}

private struct MenuContent: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("About Corners") { show(WindowID.about) }
        Button("Configure Shortcuts…") { show(WindowID.configure) }
        Divider()
        Button("Quit Corners") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// Menu bar apps aren't active by default, and openWindow doesn't raise a
    /// window that's already open. So once the menu has closed (closing it
    /// can undo an earlier activation), activate the app and raise the window.
    private func show(_ id: String) {
        openWindow(id: id)
        DispatchQueue.main.async {
            let frontmost = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
            NSApp.activate()
            // SwiftUI names scene windows "<scene id>-AppWindow-<n>".
            guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix(id) == true }) else {
                log.error("show \(id, privacy: .public): no window found")
                return
            }
            window.makeKeyAndOrderFront(nil)
            // activate() is only a request, and macOS can decline it while another
            // app is frontmost. This raises the window above that app regardless.
            window.orderFrontRegardless()

            // Activation is asynchronous, so check how it went a moment later.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                log.notice("""
                    show \(id, privacy: .public): frontmost before=\(frontmost, privacy: .public) \
                    active=\(NSApp.isActive) key=\(window.isKeyWindow) visible=\(window.isVisible)
                    """)
            }
        }
    }
}

private let log = Logger(subsystem: "com.octoth0rpe.corners", category: "windows")
