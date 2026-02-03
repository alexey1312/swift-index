import ArgumentParser
import Foundation
import Logging
import SwiftIndexCore

struct RemoteStatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show remote vs local cache status"
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

        let remoteManifest = try await provider.getManifest()
        let localManifest = try RemoteCLI.loadLocalManifest(from: cacheDirectory)

        print("Remote status")
        print("─────────────")

        if let remoteManifest {
            let timestamp = ISO8601DateFormatter().string(from: remoteManifest.createdAt)
            print("Remote: v\(remoteManifest.version) (\(timestamp))")
            if let commit = remoteManifest.gitCommit {
                print("Remote commit: \(commit)")
            }
        } else {
            print("Remote: No index found")
        }

        if let localManifest {
            let timestamp = ISO8601DateFormatter().string(from: localManifest.createdAt)
            print("Local cache: v\(localManifest.version) (\(timestamp))")
        } else {
            print("Local cache: not downloaded")
        }

        print("")

        if let remoteManifest, let localManifest {
            if remoteManifest.version > localManifest.version {
                print("Remote index is newer. Run 'swiftindex pull' to update.")
            } else if remoteManifest.version == localManifest.version {
                print("Local cache is up to date.")
            } else {
                print("Local cache is newer than remote.")
            }
        } else if remoteManifest != nil {
            print("No local cache. Run 'swiftindex pull' to download.")
        } else {
            print("No remote index available. Someone needs to run 'swiftindex push' first.")
        }
    }
}
