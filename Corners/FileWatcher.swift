import Foundation

/// Calls `onChange` when a file is modified, replaced or recreated.
///
/// Watches the file itself (in-place writes) and its parent directory
/// (editors that save by writing a temp file and renaming it over the
/// original, which leaves a watch on the old file pointing nowhere).
/// Events are kernel notifications (kqueue), so this costs nothing while idle.
@MainActor
final class FileWatcher {
    private let url: URL
    private let onChange: @MainActor () -> Void
    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var debounce: Task<Void, Never>?

    init(url: URL, onChange: @escaping @MainActor () -> Void) {
        self.url = url
        self.onChange = onChange
        directorySource = makeSource(path: url.deletingLastPathComponent().path, events: .write)
        watchFile()
    }

    private func watchFile() {
        fileSource?.cancel()
        fileSource = makeSource(path: url.path, events: [.write, .extend, .delete, .rename])
    }

    private func changed() {
        // The file may have been replaced; re-attach to whatever is there now.
        watchFile()
        // Saves often arrive as a burst of events; react once they settle.
        debounce?.cancel()
        debounce = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            onChange()
        }
    }

    private func makeSource(path: String, events: DispatchSource.FileSystemEvent) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: events, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.changed() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }
}
