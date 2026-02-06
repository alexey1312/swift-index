import Foundation
import Testing

import Crypto
@testable import SwiftIndexCore

@Suite("Remote Storage Integration Tests")
struct RemoteStorageIntegrationTests {
    @Test("S3 upload and download round-trip")
    func s3UploadDownloadRoundTrip() async throws {
        guard let bucket = ProcessInfo.processInfo.environment["SWIFTINDEX_S3_TEST_BUCKET"],
              let region = ProcessInfo.processInfo.environment["SWIFTINDEX_S3_TEST_REGION"]
        else {
            return
        }

        let prefix = "swiftindex-tests/\(UUID().uuidString)"
        let provider = try S3StorageProvider(bucket: bucket, region: region, prefix: prefix)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftindex-s3-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let source = tempDir.appendingPathComponent("sample.txt")
        let payload = Data("hello-remote-storage".utf8)
        try payload.write(to: source)

        try await provider.upload(localPath: source, remotePath: "sample.txt")

        let destination = tempDir.appendingPathComponent("downloaded.txt")
        try await provider.download(remotePath: "sample.txt", localPath: destination)

        let downloaded = try Data(contentsOf: destination)
        #expect(downloaded == payload)
    }

    @Test("Push/pull cycle with delta sync")
    func pushPullIntegration() async throws {
        guard let bucket = ProcessInfo.processInfo.environment["SWIFTINDEX_S3_TEST_BUCKET"],
              let region = ProcessInfo.processInfo.environment["SWIFTINDEX_S3_TEST_REGION"]
        else {
            return
        }

        let prefix = "swiftindex-tests/\(UUID().uuidString)"
        let provider = try S3StorageProvider(bucket: bucket, region: region, prefix: prefix)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftindex-pushpull-\(UUID().uuidString)")
        let indexDir = tempDir.appendingPathComponent("index", isDirectory: true)
        let cacheDir = tempDir.appendingPathComponent("cache", isDirectory: true)

        try FileManager.default.createDirectory(at: indexDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let chunks = indexDir.appendingPathComponent("chunks.db")
        let vectors = indexDir.appendingPathComponent("vectors.usearch")
        let mapping = indexDir.appendingPathComponent("vectors.usearch.mapping")

        try Data("chunks".utf8).write(to: chunks)
        try Data("vectors".utf8).write(to: vectors)
        try Data("mapping".utf8).write(to: mapping)

        let files = [
            (name: "chunks.db", url: chunks, compress: true),
            (name: "vectors.usearch", url: vectors, compress: true),
            (name: "vectors.usearch.mapping", url: mapping, compress: false),
        ]

        let tempUploadDir = tempDir.appendingPathComponent("upload", isDirectory: true)
        try FileManager.default.createDirectory(at: tempUploadDir, withIntermediateDirectories: true)

        var manifestFiles: [RemoteManifest.RemoteFile] = []
        for file in files {
            let originalSize = try fileSize(at: file.url)
            if file.compress {
                let compressedName = "\(file.name).zst"
                let compressedURL = tempUploadDir.appendingPathComponent(compressedName)
                try CompressionHelper.compressFile(source: file.url, destination: compressedURL)
                let compressedSize = try fileSize(at: compressedURL)
                let checksum = try checksum(at: compressedURL)
                manifestFiles.append(
                    RemoteManifest.RemoteFile(
                        name: compressedName,
                        size: originalSize,
                        compressedSize: compressedSize,
                        checksum: checksum
                    )
                )
                try await provider.upload(localPath: compressedURL, remotePath: compressedName)
            } else {
                let checksum = try checksum(at: file.url)
                manifestFiles.append(
                    RemoteManifest.RemoteFile(
                        name: file.name,
                        size: originalSize,
                        compressedSize: originalSize,
                        checksum: checksum
                    )
                )
                try await provider.upload(localPath: file.url, remotePath: file.name)
            }
        }

        let manifest = RemoteManifest(
            version: 1,
            gitCommit: nil,
            createdAt: Date(),
            files: manifestFiles
        )
        try await provider.putManifest(manifest)

        let delta = DeltaSyncManager()
        _ = try await delta.sync(provider: provider, localCache: cacheDir)

        let downloadedChunks = cacheDir.appendingPathComponent("chunks.db.zst")
        #expect(FileManager.default.fileExists(atPath: downloadedChunks.path))

        let decompressed = cacheDir.appendingPathComponent("chunks.db")
        try CompressionHelper.decompressFile(source: downloadedChunks, destination: decompressed)
        let roundTrip = try Data(contentsOf: decompressed)
        #expect(roundTrip == Data("chunks".utf8))
    }

    @Test("Overlay search uses remote cache")
    func overlaySearchIntegration() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftindex-overlay-\(UUID().uuidString)")
        let localIndexDir = tempDir.appendingPathComponent("local", isDirectory: true)
        let remoteIndexDir = tempDir.appendingPathComponent("remote", isDirectory: true)

        try FileManager.default.createDirectory(at: localIndexDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: remoteIndexDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dimension = 4
        let localIndex = try IndexManager(directory: localIndexDir.path, dimension: dimension)
        let remoteIndex = try IndexManager(directory: remoteIndexDir.path, dimension: dimension)

        let localChunk = CodeChunk(
            id: "local-1",
            path: "/project/Sources/Auth.swift",
            content: "local auth",
            startLine: 1,
            endLine: 2,
            kind: .function,
            symbols: ["Auth"],
            references: [],
            fileHash: "local"
        )

        let remoteChunk = CodeChunk(
            id: "remote-1",
            path: "/project/Sources/Auth.swift",
            content: "remote auth",
            startLine: 1,
            endLine: 2,
            kind: .function,
            symbols: ["Auth"],
            references: [],
            fileHash: "remote"
        )

        let vector = [Float](repeating: 0.1, count: dimension)
        try await localIndex.index(chunk: localChunk, vector: vector)
        try await remoteIndex.index(chunk: remoteChunk, vector: vector)
        try await localIndex.save()
        try await remoteIndex.save()

        let embeddingProvider = OverlayTestEmbeddingProvider(dimension: dimension)

        let cacheDirectory = remoteIndexDir
        let loadedRemote = try await OverlayIndexManager.loadRemoteIndexIfAvailable(
            cacheDirectory: cacheDirectory,
            dimension: dimension
        )

        #expect(loadedRemote != nil)

        let engine = await HybridSearchEngine(
            chunkStore: localIndex.chunkStore,
            vectorStore: localIndex.vectorStore,
            embeddingProvider: embeddingProvider,
            remoteChunkStore: loadedRemote?.chunkStore,
            remoteVectorStore: loadedRemote?.vectorStore
        )

        let results = try await engine.search(
            query: "auth",
            options: SearchOptions(limit: 5, semanticWeight: 0.0)
        )

        #expect(results.count == 1)
        #expect(results.first?.chunk.id == "local-1")
    }

    private func fileSize(at url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attributes[.size] as? NSNumber {
            return size.int64Value
        }
        return 0
    }

    private func checksum(at url: URL) throws -> String {
        guard let stream = InputStream(url: url) else {
            throw RemoteStorageError.ioFailure(
                underlying: NSError(domain: "RemoteStorageIntegrationTests", code: 1, userInfo: nil)
            )
        }
        stream.open()
        defer { stream.close() }

        var hasher = SHA256()
        let bufferSize = 1024 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read < 0 {
                let error = stream.streamError ?? NSError(
                    domain: "RemoteStorageIntegrationTests",
                    code: 2,
                    userInfo: nil
                )
                throw RemoteStorageError.ioFailure(underlying: error)
            }
            if read == 0 {
                break
            }
            hasher.update(data: Data(bytes: buffer, count: read))
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private actor OverlayTestEmbeddingProvider: EmbeddingProvider {
    nonisolated let id = "overlay-test"
    nonisolated let name = "Overlay Test"
    nonisolated let dimension: Int

    init(dimension: Int) {
        self.dimension = dimension
    }

    nonisolated func isAvailable() async -> Bool { true }

    func embed(_ text: String) async throws -> [Float] {
        [Float](repeating: 0.1, count: dimension)
    }
}
