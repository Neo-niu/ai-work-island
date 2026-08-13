import Darwin
import Foundation

@_silgen_name("flock")
private func systemFlock(_ fileDescriptor: Int32, _ operation: Int32) -> Int32

/// Holds an advisory file lock for the lifetime of the UI process.
///
/// PID ordering is not a valid way to identify the oldest process because
/// macOS eventually wraps process identifiers. A kernel-managed lock remains
/// correct across PID reuse and is released automatically when a process exits.
final class AppInstanceLock {
    private var fileDescriptor: Int32

    private init(fileDescriptor: Int32) {
        self.fileDescriptor = fileDescriptor
    }

    static func acquire(at fileURL: URL = defaultFileURL) -> AppInstanceLock? {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            return nil
        }

        let fileDescriptor = fileURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        }
        guard fileDescriptor >= 0 else { return nil }
        guard systemFlock(fileDescriptor, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(fileDescriptor)
            return nil
        }
        return AppInstanceLock(fileDescriptor: fileDescriptor)
    }

    func release() {
        guard fileDescriptor >= 0 else { return }
        _ = systemFlock(fileDescriptor, LOCK_UN)
        Darwin.close(fileDescriptor)
        fileDescriptor = -1
    }

    deinit {
        release()
    }

    private static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Codex Hermes Touch Bar", isDirectory: true)
            .appendingPathComponent("app-instance.lock")
    }
}
