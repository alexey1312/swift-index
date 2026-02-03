import Foundation

public struct SyncResult: Sendable, Equatable {
    public let filesDownloaded: Int
    public let bytesDownloaded: Int64
    public let skippedUnchanged: Int
    public let duration: TimeInterval

    public init(
        filesDownloaded: Int,
        bytesDownloaded: Int64,
        skippedUnchanged: Int,
        duration: TimeInterval
    ) {
        self.filesDownloaded = filesDownloaded
        self.bytesDownloaded = bytesDownloaded
        self.skippedUnchanged = skippedUnchanged
        self.duration = duration
    }
}

public actor DeltaSyncManager {
    public init() {}

    public func sync(
        provider: RemoteStorageProvider,
        localCache: URL
    ) async throws -> SyncResult {
        let start = Date()
        guard let remoteManifest = try await provider.getManifest() else {
            throw RemoteStorageError.missingManifest
        }

        let localManifest = try loadLocalManifest(from: localCache)
        let filesToDownload = computeDelta(
            remote: remoteManifest,
            localCache: localCache,
            localManifest: localManifest
        )

        var bytesDownloaded: Int64 = 0
        for file in filesToDownload {
            let destination = localCache.appendingPathComponent(file.name)
            try await provider.download(remotePath: file.name, localPath: destination)
            bytesDownloaded += file.compressedSize > 0 ? file.compressedSize : file.size
        }

        try saveLocalManifest(remoteManifest, to: localCache)

        let skipped = remoteManifest.files.count - filesToDownload.count
        return SyncResult(
            filesDownloaded: filesToDownload.count,
            bytesDownloaded: bytesDownloaded,
            skippedUnchanged: max(0, skipped),
            duration: Date().timeIntervalSince(start)
        )
    }

    public func computeDelta(
        remote: RemoteManifest,
        localCache: URL
    ) -> [RemoteManifest.RemoteFile] {
        let localManifest = try? loadLocalManifest(from: localCache)
        return computeDelta(remote: remote, localCache: localCache, localManifest: localManifest)
    }

    private func computeDelta(
        remote: RemoteManifest,
        localCache: URL,
        localManifest: RemoteManifest?
    ) -> [RemoteManifest.RemoteFile] {
        let localByName = Dictionary(
            uniqueKeysWithValues: (localManifest?.files ?? []).map { ($0.name, $0) }
        )

        return remote.files.filter { remoteFile in
            guard let localFile = localByName[remoteFile.name] else {
                return true
            }
            let localURL = localCache.appendingPathComponent(remoteFile.name)
            guard FileManager.default.fileExists(atPath: localURL.path) else {
                return true
            }
            return remoteFile.checksum != localFile.checksum
        }
    }

    private func loadLocalManifest(from localCache: URL) throws -> RemoteManifest? {
        let manifestURL = localCache.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: manifestURL)
        return try JSONCodec.decode(RemoteManifest.self, from: data)
    }

    private func saveLocalManifest(_ manifest: RemoteManifest, to localCache: URL) throws {
        try FileManager.default.createDirectory(at: localCache, withIntermediateDirectories: true)
        let manifestURL = localCache.appendingPathComponent("manifest.json")
        let data = try JSONCodec.encodePrettySorted(manifest)
        try data.write(to: manifestURL, options: [.atomic])
    }
}
