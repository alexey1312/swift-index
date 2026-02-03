import ArgumentParser
import Foundation
import Logging
import Noora
import SwiftIndexCore

struct PullCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pull",
        abstract: "Download the remote index into the local cache",
        discussion: """
        Fetches the remote manifest, downloads only changed files, and
        decompresses them into the shared cache for overlay search.
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
        let cacheDirectory = RemoteCLI.cacheDirectory(for: repoPath, config: configuration)
        let provider = try RemoteCLI.makeProvider(from: remoteConfig)

        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        guard let remoteManifest = try await provider.getManifest() else {
            print("No remote index found. Someone needs to run 'swiftindex push' first.")
            throw ExitCode.failure
        }

        let deltaManager = DeltaSyncManager()
        let filesToDownload = await deltaManager.computeDelta(
            remote: remoteManifest,
            localCache: cacheDirectory
        )

        let start = Date()
        if filesToDownload.isEmpty {
            print("Remote index is already up to date.")
            return
        }

        let ui = Noora()
        let terminal = Terminal()
        let renderer = StickyProgressRenderer(terminal: terminal)
        var bytesDownloaded: Int64 = 0

        try await ui.progressBarStep(
            message: "Downloading index",
            successMessage: "Download complete",
            errorMessage: "Download failed",
            renderer: renderer
        ) { updateProgress in
            for (index, file) in filesToDownload.enumerated() {
                let destination = cacheDirectory.appendingPathComponent(file.name)
                try await provider.download(remotePath: file.name, localPath: destination, progress: nil)

                let checksum = try RemoteCLI.checksum(at: destination)
                if checksum != file.checksum {
                    throw RemoteStorageError.checksumMismatch(expected: file.checksum, actual: checksum)
                }

                if destination.pathExtension == "zst" {
                    let decompressedURL = destination.deletingPathExtension()
                    try CompressionHelper.decompressFile(source: destination, destination: decompressedURL)
                }

                bytesDownloaded += file.compressedSize > 0 ? file.compressedSize : file.size
                let progress = Double(index + 1) / Double(filesToDownload.count)
                updateProgress(progress)
            }
        }

        try RemoteCLI.saveLocalManifest(remoteManifest, to: cacheDirectory)

        let skipped = max(0, remoteManifest.files.count - filesToDownload.count)
        let duration = Date().timeIntervalSince(start)

        print("\nDownloaded \(filesToDownload.count) files")
        if skipped > 0 {
            print("Skipped \(skipped) unchanged files")
        }
        print("Total downloaded: \(RemoteCLI.formatBytes(bytesDownloaded))")
        print("Duration: \(RemoteCLI.formatDuration(duration))")
        let timestamp = ISO8601DateFormatter().string(from: remoteManifest.createdAt)
        print("Version: \(remoteManifest.version) (\(timestamp))")
    }
}
