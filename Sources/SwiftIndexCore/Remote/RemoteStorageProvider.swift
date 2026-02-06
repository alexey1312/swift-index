import Foundation

public enum RemoteStorageError: Error, Sendable {
    case invalidConfiguration(String)
    case missingManifest
    case checksumMismatch(expected: String, actual: String)
    case unauthorized
    case notFound(String)
    case networkFailure(underlying: Error)
    case ioFailure(underlying: Error)
    case unsupportedProvider(String)
}

public typealias RemoteStorageProgressHandler = @Sendable (_ bytesReceived: Int64, _ totalBytes: Int64?) -> Void

public protocol RemoteStorageProvider: Sendable {
    func upload(localPath: URL, remotePath: String) async throws
    func download(remotePath: String, localPath: URL) async throws
    func download(
        remotePath: String,
        localPath: URL,
        progress: RemoteStorageProgressHandler?
    ) async throws
    func exists(remotePath: String) async throws -> Bool
    func getManifest() async throws -> RemoteManifest?
    func putManifest(_ manifest: RemoteManifest) async throws
}

public extension RemoteStorageProvider {
    func download(
        remotePath: String,
        localPath: URL,
        progress: RemoteStorageProgressHandler?
    ) async throws {
        try await download(remotePath: remotePath, localPath: localPath)
    }
}
