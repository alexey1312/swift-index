// MARK: - IndexWriterLock

import Foundation

/// An exclusive, advisory lock that makes one process the writer of an index.
///
/// Every agent starts its own `swiftindex serve`. SQLite accepts several writers,
/// but each process keeps the USearch vector index in memory and saves it whole,
/// so two writers would overwrite each other's vectors. The process that holds
/// this lock indexes, watches and embeds; the others only read.
///
/// The lock is `flock(2)` on `writer.lock` in the index directory. The kernel
/// releases it when the holder exits, also after a crash, so a lock is never stale.
public final class IndexWriterLock: @unchecked Sendable {
    public static let fileName = "writer.lock"

    private let descriptor: Int32
    private let lock = NSLock()
    private var released = false

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    deinit {
        release()
    }

    /// Takes the lock without waiting.
    ///
    /// - Returns: The lock, or nil when another open lock holds it.
    public static func acquire(indexDirectory: String) -> IndexWriterLock? {
        try? FileManager.default.createDirectory(atPath: indexDirectory, withIntermediateDirectories: true)
        let path = (indexDirectory as NSString).appendingPathComponent(fileName)
        let descriptor = open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else { return nil }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }

        let pid = Data("\(getpid())\n".utf8)
        ftruncate(descriptor, 0)
        _ = pid.withUnsafeBytes { pwrite(descriptor, $0.baseAddress, pid.count, 0) }
        return IndexWriterLock(descriptor: descriptor)
    }

    /// Process id that last took the lock, for messages. It may have exited.
    public static func recordedHolder(indexDirectory: String) -> Int32? {
        let path = (indexDirectory as NSString).appendingPathComponent(fileName)
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return Int32(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Releases the lock. Calling it again has no effect.
    public func release() {
        lock.lock()
        defer { lock.unlock() }
        guard !released else { return }
        released = true
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
