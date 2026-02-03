import ArgumentParser
import Foundation
import Logging
import Noora
import SwiftIndexCore

struct PushCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "push",
        abstract: "Upload the local index to remote storage",
        discussion: """
        Compresses local index files, uploads them to the configured remote
        storage provider, and writes a manifest for delta sync.
        """
    )

    @Argument(help: "Path to the repository (default: current directory)")
    var path: String = "."

    @Option(name: .shortAndLong, help: "Path to configuration file")
    var config: String?

    @Flag(name: .shortAndLong, help: "Enable verbose debug output")
    var verbose: Bool = false

    mutating func run() async throws {
        let logger = CLIUtils.makeLogger(verbose: verbose)
        let configuration = try RemoteCLI.loadConfigOrThrow(configPath: config, logger: logger)
        let remoteConfig = try RemoteCLI.requireRemoteConfig(configuration)
        let repoPath = try RemoteCLI.resolveProjectPath(path)
        let indexDirectory = RemoteCLI.indexDirectory(for: repoPath, config: configuration)

        guard FileManager.default.fileExists(atPath: indexDirectory.path) else {
            throw ValidationError(
                "No local index found. Run 'swiftindex index' first."
            )
        }

        let provider = try RemoteCLI.makeProvider(from: remoteConfig)
        let compression = remoteConfig.sync.compression

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let indexFiles = try localIndexFiles(in: indexDirectory)
        let uploadFiles = try prepareUploadFiles(
            indexFiles: indexFiles,
            tempDirectory: tempDirectory,
            compression: compression
        )

        let previousManifest = try? await provider.getManifest()
        let nextVersion = (previousManifest?.version ?? 0) + 1
        let gitCommit = RemoteCLI.gitCommit(for: repoPath)

        let manifest = RemoteManifest(
            version: nextVersion,
            gitCommit: gitCommit,
            createdAt: Date(),
            files: uploadFiles.map(\.manifestFile)
        )

        print("Preparing upload...")
        print("Remote: \(remoteConfig.provider.rawValue.uppercased()) bucket \"\(remoteConfig.bucket)\"")
        print("Files: \(uploadFiles.count)")

        let ui = Noora()
        let terminal = Terminal()
        let renderer = StickyProgressRenderer(terminal: terminal)

        try await ui.progressBarStep(
            message: "Uploading index",
            successMessage: "Upload complete",
            errorMessage: "Upload failed",
            renderer: renderer
        ) { updateProgress in
            for (index, file) in uploadFiles.enumerated() {
                try await provider.upload(localPath: file.localURL, remotePath: file.remoteName)
                let progress = Double(index + 1) / Double(uploadFiles.count)
                updateProgress(progress)
            }
        }

        try await provider.putManifest(manifest)

        let totalBytes = uploadFiles.reduce(Int64(0)) { $0 + $1.manifestFile.compressedSize }
        print("\nUploaded \(uploadFiles.count) files (\(RemoteCLI.formatBytes(totalBytes)))")
        print("Version: \(manifest.version)")
        if let commit = manifest.gitCommit {
            print("Git commit: \(commit)")
        }
    }

    private struct LocalIndexFile {
        let name: String
        let url: URL
        let compress: Bool
    }

    private struct UploadFile {
        let localURL: URL
        let remoteName: String
        let manifestFile: RemoteManifest.RemoteFile
    }

    private func localIndexFiles(in indexDirectory: URL) throws -> [LocalIndexFile] {
        let chunks = LocalIndexFile(
            name: "chunks.db",
            url: indexDirectory.appendingPathComponent("chunks.db"),
            compress: true
        )
        let vectors = LocalIndexFile(
            name: "vectors.usearch",
            url: indexDirectory.appendingPathComponent("vectors.usearch"),
            compress: true
        )
        let mapping = LocalIndexFile(
            name: "vectors.usearch.mapping",
            url: indexDirectory.appendingPathComponent("vectors.usearch.mapping"),
            compress: false
        )

        let files = [chunks, vectors, mapping]
        for file in files {
            guard FileManager.default.fileExists(atPath: file.url.path) else {
                throw ValidationError("Missing index file: \(file.url.lastPathComponent)")
            }
        }
        return files
    }

    private func prepareUploadFiles(
        indexFiles: [LocalIndexFile],
        tempDirectory: URL,
        compression: RemoteConfig.Compression
    ) throws -> [UploadFile] {
        try indexFiles.map { file in
            let originalSize = try RemoteCLI.fileSize(at: file.url)
            if compression == .zstd, file.compress {
                let compressedName = "\(file.name).zst"
                let compressedURL = tempDirectory.appendingPathComponent(compressedName)
                try CompressionHelper.compressFile(source: file.url, destination: compressedURL)
                let compressedSize = try RemoteCLI.fileSize(at: compressedURL)
                let checksum = try RemoteCLI.checksum(at: compressedURL)
                let manifestFile = RemoteManifest.RemoteFile(
                    name: compressedName,
                    size: originalSize,
                    compressedSize: compressedSize,
                    checksum: checksum
                )
                return UploadFile(localURL: compressedURL, remoteName: compressedName, manifestFile: manifestFile)
            }

            let checksum = try RemoteCLI.checksum(at: file.url)
            let manifestFile = RemoteManifest.RemoteFile(
                name: file.name,
                size: originalSize,
                compressedSize: originalSize,
                checksum: checksum
            )
            return UploadFile(localURL: file.url, remoteName: file.name, manifestFile: manifestFile)
        }
    }
}
