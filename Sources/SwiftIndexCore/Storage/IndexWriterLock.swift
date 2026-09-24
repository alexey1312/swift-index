// MARK: - IndexWriterLock

import Foundation
import os

/// An exclusive, advisory lock that makes one process the writer of an index.
///
/// Every agent starts its own `swiftindex serve`. SQLite accepts several writers,
/// but each process keeps the USearch vector index in memory and saves it whole,
/// so two writers would overwrite each other's vectors. The process that holds
/// this lock indexes, watches and embeds; the others only read.
///
/// The lock is `flock(2)` on `writer.lock` in the index directory. The kernel
/// releases it when the holder exits, also after a crash, so a lock is never stale.
public final class IndexWriterLock: Sendable {
    public static let fileName = "writer.lock"

    /// An I/O failure other than a lock that another process holds.
    public enum AcquireError: Error, CustomStringConvertible {
        case io(path: String, errno: Int32)

        public var description: String {
            switch self {
            case let .io(path, code):
                "Cannot open the index writer lock at \(path): \(String(cString: strerror(code)))"
            }
        }
    }

    private let descriptor: Int32
    private let released = OSAllocatedUnfairLock(initialState: false)

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    deinit {
        release()
    }

    /// Takes the lock without waiting.
    ///
    /// - Returns: The lock, or nil when another process holds it.
    /// - Throws: `AcquireError` when the lock file cannot be created, opened or locked.
    public static func acquire(indexDirectory: String) throws -> IndexWriterLock? {
        do {
            try FileManager.default.createDirectory(atPath: indexDirectory, withIntermediateDirectories: true)
        } catch {
            let code = ((error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError)?.code
            throw AcquireError.io(path: indexDirectory, errno: code.map { Int32($0) } ?? EIO)
        }
        let path = (indexDirectory as NSString).appendingPathComponent(fileName)
        let descriptor = open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else { throw AcquireError.io(path: path, errno: errno) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(descriptor)
            if code == EWOULDBLOCK {
                return nil
            }
            throw AcquireError.io(path: path, errno: code)
        }

        // The pid only feeds messages, so a failed write keeps the lock.
        let pid = Data("\(getpid())\n".utf8)
        if ftruncate(descriptor, 0) == 0 {
            _ = pid.withUnsafeBytes { pwrite(descriptor, $0.baseAddress, pid.count, 0) }
        }
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
        let wasReleased = released.withLock { value in
            defer { value = true }
            return value
        }
        guard !wasReleased else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
