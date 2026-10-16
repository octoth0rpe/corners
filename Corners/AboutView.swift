import SwiftUI

struct AboutView: View {
    private let info = Bundle.main.infoDictionary ?? [:]

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
            Text("Corners")
                .font(.title.bold())
            Text("Version \(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Press a shortcut, put a window in its place.")
                .padding(.top, 4)
            if let copyright = info["NSHumanReadableCopyright"] as? String {
                Text(copyright)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 56)
        .padding(.vertical, 28)
        .fixedSize()
    }
}
