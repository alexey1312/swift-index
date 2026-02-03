import Foundation

public struct RemoteConfig: Sendable, Equatable {
    public enum Provider: String, Sendable, CaseIterable {
        case s3
        case gcs
    }

    public enum Compression: String, Sendable, CaseIterable {
        case zstd
        case none
    }

    public struct Sync: Sendable, Equatable {
        public var compression: Compression
        public var autoPull: Bool

        public init(
            compression: Compression = .zstd,
            autoPull: Bool = false
        ) {
            self.compression = compression
            self.autoPull = autoPull
        }
    }

    public var enabled: Bool
    public var provider: Provider
    public var bucket: String
    public var region: String?
    public var project: String?
    public var prefix: String
    public var sync: Sync

    public init(
        enabled: Bool = true,
        provider: Provider,
        bucket: String,
        region: String? = nil,
        project: String? = nil,
        prefix: String = "",
        sync: Sync = Sync()
    ) {
        self.enabled = enabled
        self.provider = provider
        self.bucket = bucket
        self.region = region
        self.project = project
        self.prefix = prefix
        self.sync = sync
    }
}

extension RemoteConfig.Provider: CustomStringConvertible {
    public var description: String {
        rawValue.uppercased()
    }
}

extension RemoteConfig.Compression: CustomStringConvertible {
    public var description: String {
        rawValue
    }
}
