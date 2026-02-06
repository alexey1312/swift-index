import AsyncHTTPClient
@preconcurrency import Core
import Foundation
import NIOCore
import NIOPosix
@preconcurrency import Storage

public actor GCSStorageProvider: RemoteStorageProvider {
    private let bucket: String
    private let prefix: String
    private let eventLoopGroup: MultiThreadedEventLoopGroup
    private let httpClient: HTTPClient
    private let client: GoogleCloudStorageClient

    public init(
        bucket: String,
        project: String? = nil,
        credentialsFile: String? = nil,
        prefix: String = ""
    ) throws {
        self.bucket = bucket
        self.prefix = prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let credentials = try GoogleCloudCredentialsConfiguration(
            projectId: project,
            credentialsFile: credentialsFile
        )
        let storageConfig = GoogleCloudStorageConfiguration.default()
        eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoopGroup))
        client = try GoogleCloudStorageClient(
            credentials: credentials,
            storageConfig: storageConfig,
            httpClient: httpClient,
            eventLoop: eventLoopGroup.next()
        )
    }

    public func shutdown() async throws {
        try await httpClient.shutdown()
        try await eventLoopGroup.shutdownGracefully()
    }

    public func upload(localPath: URL, remotePath: String) async throws {
        let key = resolveKey(remotePath)
        let data = try Data(contentsOf: localPath)
        // TODO: implement chunked upload for large files (GCS resumable upload API)
        _ = try await client.object
            .createSimpleUpload(
                bucket: bucket,
                body: .data(data),
                name: key,
                contentType: "application/octet-stream",
                queryParameters: nil
            )
            .get()
    }

    public func download(remotePath: String, localPath: URL) async throws {
        try await download(remotePath: remotePath, localPath: localPath, progress: nil)
    }

    public func download(
        remotePath: String,
        localPath: URL,
        progress: RemoteStorageProgressHandler?
    ) async throws {
        let key = resolveKey(remotePath)
        let response = try await client.object
            .getMedia(bucket: bucket, object: key, range: nil, queryParameters: nil)
            .get()
        guard let data = response.data else {
            throw RemoteStorageError.notFound(key)
        }
        progress?(Int64(0), Int64(data.count))
        try FileManager.default.createDirectory(
            at: localPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: localPath, options: [.atomic])
        progress?(Int64(data.count), Int64(data.count))
    }

    public func exists(remotePath: String) async throws -> Bool {
        let key = resolveKey(remotePath)
        do {
            _ = try await client.object.get(
                bucket: bucket, object: key, queryParameters: nil
            ).get()
            return true
        } catch let error as CloudStorageAPIError {
            if error.error.code == 404 {
                return false
            }
            throw RemoteStorageError.networkFailure(underlying: error)
        } catch {
            throw RemoteStorageError.networkFailure(underlying: error)
        }
    }

    public func getManifest() async throws -> RemoteManifest? {
        let key = resolveKey("manifest.json")
        do {
            let response = try await client.object
                .getMedia(bucket: bucket, object: key, range: nil, queryParameters: nil)
                .get()
            guard let data = response.data else {
                return nil
            }
            return try JSONCodec.decode(RemoteManifest.self, from: data)
        } catch let error as CloudStorageAPIError {
            if error.error.code == 404 {
                return nil
            }
            throw RemoteStorageError.networkFailure(underlying: error)
        }
    }

    public func putManifest(_ manifest: RemoteManifest) async throws {
        let key = resolveKey("manifest.json")
        let data = try JSONCodec.encodePrettySorted(manifest)
        _ = try await client.object
            .createSimpleUpload(
                bucket: bucket,
                body: .data(data),
                name: key,
                contentType: "application/json",
                queryParameters: nil
            )
            .get()
    }

    private func resolveKey(_ path: String) -> String {
        let cleaned = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !prefix.isEmpty else { return cleaned }
        return "\(prefix)/\(cleaned)"
    }
}
