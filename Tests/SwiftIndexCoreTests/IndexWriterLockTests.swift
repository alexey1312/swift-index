import Foundation
@testable import SwiftIndexCore
import Testing

@Suite("IndexWriterLock Tests")
struct IndexWriterLockTests {
    @Test("Only one holder at a time, and release lets the next one in")
    func exclusiveUntilReleased() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("writer-lock-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: directory) }

        let first = try #require(IndexWriterLock.acquire(indexDirectory: directory))
        #expect(IndexWriterLock.acquire(indexDirectory: directory) == nil)
        #expect(IndexWriterLock.recordedHolder(indexDirectory: directory) == getpid())

        first.release()
        let second = IndexWriterLock.acquire(indexDirectory: directory)
        #expect(second != nil)
        second?.release()
    }
}
