import AsyncHTTPClient
@preconcurrency import Core
import Foundation
import NIOCore
import NIOPosix
@preconcurrency import Storage

public actor GCSStorageProvider: RemoteStorageProvider {
    private let bucket: String
    private let prefix: String
    private let project: String?
    private let credentialsFile: String?

    public init(
        bucket: String,
        project: String? = nil,
        credentialsFile: String? = nil,
        prefix: String = ""
    ) {
        self.bucket = bucket
        self.project = project
        self.credentialsFile = credentialsFile
        self.prefix = prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    public func upload(localPath: URL, remotePath: String) async throws {
        let key = resolveKey(remotePath)
        let data = try Data(contentsOf: localPath)

        try await withClient { client in
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
    }

    public func download(remotePath: String, localPath: URL) async throws {
        let key = resolveKey(remotePath)
        try await withClient { client in
            let response = try await client.object
                .getMedia(bucket: bucket, object: key, range: nil, queryParameters: nil)
                .get()
            guard let data = response.data else {
                throw RemoteStorageError.notFound(key)
            }
            try FileManager.default.createDirectory(
                at: localPath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: localPath, options: [.atomic])
        }
    }

    public func exists(remotePath: String) async throws -> Bool {
        let key = resolveKey(remotePath)
        return try await withClient { client in
            do {
                _ = try await client.object.get(bucket: bucket, object: key, queryParameters: nil).get()
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
    }

    public func getManifest() async throws -> RemoteManifest? {
        let key = resolveKey("manifest.json")
        return try await withClient { client in
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
    }

    public func putManifest(_ manifest: RemoteManifest) async throws {
        let key = resolveKey("manifest.json")
        let data = try JSONCodec.encodePrettySorted(manifest)

        try await withClient { client in
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
    }

    private func resolveKey(_ path: String) -> String {
        let cleaned = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !prefix.isEmpty else { return cleaned }
        return "\(prefix)/\(cleaned)"
    }

    private func withClient<T>(
        _ operation: (GoogleCloudStorageClient) async throws -> T
    ) async throws -> T {
        let credentials = try GoogleCloudCredentialsConfiguration(
            projectId: project,
            credentialsFile: credentialsFile
        )
        let storageConfig = GoogleCloudStorageConfiguration.default()
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoopGroup))
        let eventLoop = eventLoopGroup.next()
        let client = try GoogleCloudStorageClient(
            credentials: credentials,
            storageConfig: storageConfig,
            httpClient: httpClient,
            eventLoop: eventLoop
        )

        do {
            let result = try await operation(client)
            try await httpClient.shutdown()
            try await eventLoopGroup.shutdownGracefully()
            return result
        } catch {
            try? await httpClient.shutdown()
            try? await eventLoopGroup.shutdownGracefully()
            throw error
        }
    }
}
