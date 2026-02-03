@preconcurrency import AWSS3
import Foundation
import Smithy

public final class S3StorageProvider: RemoteStorageProvider, @unchecked Sendable {
    private let bucket: String
    private let prefix: String
    private let client: S3Client
    private let multipartThreshold: Int64 = 8 * 1024 * 1024
    private let multipartChunkSize: Int = 8 * 1024 * 1024

    public init(bucket: String, region: String, prefix: String = "") throws {
        self.bucket = bucket
        self.prefix = prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        client = try S3Client(region: region)
    }

    public func upload(localPath: URL, remotePath: String) async throws {
        let key = resolveKey(remotePath)
        let fileSize = try fileSize(at: localPath)

        if fileSize >= multipartThreshold {
            try await multipartUpload(localPath: localPath, key: key, fileSize: fileSize)
            return
        }

        let data = try Data(contentsOf: localPath)
        let input = PutObjectInput(
            body: .data(data),
            bucket: bucket,
            contentLength: data.count,
            key: key
        )
        _ = try await client.putObject(input: input)
    }

    public func download(remotePath: String, localPath: URL) async throws {
        let key = resolveKey(remotePath)
        let output = try await client.getObject(input: GetObjectInput(bucket: bucket, key: key))
        guard let body = output.body, let data = try await body.readData() else {
            throw RemoteStorageError.notFound(key)
        }
        try FileManager.default.createDirectory(
            at: localPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: localPath, options: [.atomic])
    }

    public func exists(remotePath: String) async throws -> Bool {
        let key = resolveKey(remotePath)
        do {
            _ = try await client.headObject(input: HeadObjectInput(bucket: bucket, key: key))
            return true
        } catch is NoSuchKey {
            return false
        } catch {
            throw RemoteStorageError.networkFailure(underlying: error)
        }
    }

    public func getManifest() async throws -> RemoteManifest? {
        let key = resolveKey("manifest.json")
        do {
            let output = try await client.getObject(input: GetObjectInput(bucket: bucket, key: key))
            guard let body = output.body, let data = try await body.readData() else {
                return nil
            }
            return try JSONCodec.decode(RemoteManifest.self, from: data)
        } catch is NoSuchKey {
            return nil
        } catch {
            throw RemoteStorageError.networkFailure(underlying: error)
        }
    }

    public func putManifest(_ manifest: RemoteManifest) async throws {
        let key = resolveKey("manifest.json")
        let data = try JSONCodec.encodePrettySorted(manifest)
        let input = PutObjectInput(
            body: .data(data),
            bucket: bucket,
            contentLength: data.count,
            key: key
        )
        _ = try await client.putObject(input: input)
    }

    private func multipartUpload(localPath: URL, key: String, fileSize: Int64) async throws {
        let createInput = CreateMultipartUploadInput(bucket: bucket, key: key)
        let createOutput = try await client.createMultipartUpload(input: createInput)
        guard let uploadId = createOutput.uploadId else {
            throw RemoteStorageError.networkFailure(
                underlying: NSError(domain: "S3StorageProvider", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Missing uploadId for multipart upload",
                ])
            )
        }

        var completedParts: [S3ClientTypes.CompletedPart] = []
        let handle = try FileHandle(forReadingFrom: localPath)
        defer { try? handle.close() }

        var partNumber = 1
        var bytesRemaining = fileSize
        do {
            while bytesRemaining > 0 {
                let chunkSize = min(Int64(multipartChunkSize), bytesRemaining)
                let data = try handle.read(upToCount: Int(chunkSize)) ?? Data()
                if data.isEmpty {
                    break
                }

                let uploadInput = UploadPartInput(
                    body: .data(data),
                    bucket: bucket,
                    contentLength: data.count,
                    key: key,
                    partNumber: partNumber,
                    uploadId: uploadId
                )
                let output = try await client.uploadPart(input: uploadInput)
                guard let eTag = output.eTag else {
                    throw RemoteStorageError.networkFailure(
                        underlying: NSError(domain: "S3StorageProvider", code: 2, userInfo: [
                            NSLocalizedDescriptionKey: "Missing ETag for part \(partNumber)",
                        ])
                    )
                }
                completedParts.append(S3ClientTypes.CompletedPart(eTag: eTag, partNumber: partNumber))
                bytesRemaining -= Int64(data.count)
                partNumber += 1
            }

            let completed = S3ClientTypes.CompletedMultipartUpload(parts: completedParts)
            let completeInput = CompleteMultipartUploadInput(
                bucket: bucket,
                key: key,
                multipartUpload: completed,
                uploadId: uploadId
            )
            _ = try await client.completeMultipartUpload(input: completeInput)
        } catch {
            let abortInput = AbortMultipartUploadInput(bucket: bucket, key: key, uploadId: uploadId)
            _ = try? await client.abortMultipartUpload(input: abortInput)
            throw error
        }
    }

    private func resolveKey(_ path: String) -> String {
        let cleaned = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !prefix.isEmpty else { return cleaned }
        return "\(prefix)/\(cleaned)"
    }

    private func fileSize(at url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attributes[.size] as? NSNumber {
            return size.int64Value
        }
        return 0
    }
}
