import Foundation

public enum RemoteStorageProviderFactory {
    public static func makeProvider(config: RemoteConfig) throws -> RemoteStorageProvider {
        switch config.provider {
        case .s3:
            guard let region = config.region, !region.isEmpty else {
                throw RemoteStorageError.invalidConfiguration("S3 requires a region in [remote].region")
            }
            return try S3StorageProvider(bucket: config.bucket, region: region, prefix: config.prefix)
        case .gcs:
            return try GCSStorageProvider(
                bucket: config.bucket,
                project: config.project,
                credentialsFile: nil,
                prefix: config.prefix
            )
        }
    }
}
