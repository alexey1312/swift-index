@testable import SwiftIndexCore
import XCTest

final class RemoteCachePathsTests: XCTestCase {
    func testCacheDirectoriesAreIsolatedByRepoHash() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cachePaths = RemoteCachePaths(root: tempRoot)

        let repoA = URL(fileURLWithPath: "/tmp/repo-a")
        let repoB = URL(fileURLWithPath: "/tmp/repo-b")

        let cacheA = cachePaths.cacheDirectory(forRepoPath: repoA)
        let cacheB = cachePaths.cacheDirectory(forRepoPath: repoB)

        XCTAssertNotEqual(cacheA.path, cacheB.path)

        try cachePaths.ensureCacheDirectory(forRepoPath: repoA)
        try cachePaths.ensureCacheDirectory(forRepoPath: repoB)

        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheA.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheB.path))
    }
}
