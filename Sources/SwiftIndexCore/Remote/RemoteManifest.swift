import Foundation

public struct RemoteManifest: Codable, Sendable, Equatable {
    public let version: Int
    public let gitCommit: String?
    public let createdAt: Date
    public let files: [RemoteFile]

    public init(
        version: Int,
        gitCommit: String?,
        createdAt: Date,
        files: [RemoteFile]
    ) {
        self.version = version
        self.gitCommit = gitCommit
        self.createdAt = createdAt
        self.files = files
    }

    public struct RemoteFile: Codable, Sendable, Equatable {
        public let name: String
        public let size: Int64
        public let compressedSize: Int64
        public let checksum: String

        public init(
            name: String,
            size: Int64,
            compressedSize: Int64,
            checksum: String
        ) {
            self.name = name
            self.size = size
            self.compressedSize = compressedSize
            self.checksum = checksum
        }
    }
}
