import Foundation
@testable import SwiftIndexCore
import Testing

@Suite("IndexWriterLock Tests")
struct IndexWriterLockTests {
    private func makeDirectory() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("writer-lock-\(UUID().uuidString)").path
    }

    @Test("Only one holder at a time, and release lets the next one in")
    func exclusiveUntilReleased() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory) }

        let first = try #require(try IndexWriterLock.acquire(indexDirectory: directory))
        #expect(try IndexWriterLock.acquire(indexDirectory: directory) == nil)
        #expect(IndexWriterLock.recordedHolder(indexDirectory: directory) == getpid())

        first.release()
        let second = try IndexWriterLock.acquire(indexDirectory: directory)
        #expect(second != nil)
        second?.release()
    }

    @Test("A lock that another process holds returns nil until that process exits")
    func crossProcess() async throws {
        let directory = makeDirectory()
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let lockPath = (directory as NSString).appendingPathComponent(IndexWriterLock.fileName)
        let readyPath = (directory as NSString).appendingPathComponent("ready")

        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        child.arguments = [
            "-c",
            """
            import fcntl, sys, time
            f = open(sys.argv[1], "w")
            fcntl.flock(f, fcntl.LOCK_EX)
            open(sys.argv[2], "w").close()
            time.sleep(60)
            """,
            lockPath,
            readyPath,
        ]
        try child.run()
        defer {
            if child.isRunning {
                child.terminate()
            }
        }

        let deadline = Date().addingTimeInterval(20)
        while !FileManager.default.fileExists(atPath: readyPath), Date() < deadline, child.isRunning {
            try await Task.sleep(for: .milliseconds(50))
        }
        try #require(FileManager.default.fileExists(atPath: readyPath))

        #expect(try IndexWriterLock.acquire(indexDirectory: directory) == nil)

        child.terminate()
        child.waitUntilExit()

        let lock = try IndexWriterLock.acquire(indexDirectory: directory)
        #expect(lock != nil)
        lock?.release()
    }

    @Test("An unusable index directory throws an I/O error with the path")
    func throwsForUnwritableDirectory() throws {
        let file = makeDirectory()
        try Data().write(to: URL(fileURLWithPath: file))
        defer { try? FileManager.default.removeItem(atPath: file) }
        let directory = (file as NSString).appendingPathComponent("index")

        do {
            _ = try IndexWriterLock.acquire(indexDirectory: directory)
            Issue.record("acquire did not throw")
        } catch let error as IndexWriterLock.AcquireError {
            #expect(error.description.contains(directory))
        }
    }
}
