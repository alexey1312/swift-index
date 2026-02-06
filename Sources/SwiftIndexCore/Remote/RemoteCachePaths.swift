import Foundation

public struct RemoteCachePaths: Sendable {
    public let root: URL

    public init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            self.root = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".cache/swiftindex/shared", isDirectory: true)
        }
    }

    public func cacheDirectory(forRepoPath repoPath: URL) -> URL {
        let normalized = repoPath.standardizedFileURL.path
        let hash = FileHasher.hash(normalized)
        return root.appendingPathComponent(hash, isDirectory: true)
    }

    @discardableResult
    public func ensureCacheDirectory(forRepoPath repoPath: URL) throws -> URL {
        let directory = cacheDirectory(forRepoPath: repoPath)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public func manifestURL(in cacheDirectory: URL) -> URL {
        cacheDirectory.appendingPathComponent("manifest.json")
    }
}
