import ArgumentParser
import Foundation
import Logging
import Noora
import SwiftIndexCore
import TOML

struct RemoteConfigCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Configure remote storage settings",
        discussion: """
        Runs an interactive setup wizard for remote storage and writes
        the [remote] section into .swiftindex.toml.
        """
    )

    @Option(name: .shortAndLong, help: "Path to configuration file")
    var config: String?

    @Flag(name: .shortAndLong, help: "Enable verbose debug output")
    var verbose: Bool = false

    mutating func run() async throws {
        let logger = CLIUtils.makeLogger(verbose: verbose)
        let configPath = CLIUtils.resolvePath(config ?? ".swiftindex.toml")
        let ui = Noora()

        guard FileManager.default.fileExists(atPath: configPath) else {
            print("Configuration not found: \(configPath)")
            print("Run 'swiftindex init' first to create a configuration file.")
            throw ExitCode.failure
        }

        let configuration = try RemoteCLI.loadConfigOrThrow(configPath: configPath, logger: logger)
        if let existing = configuration.remote, existing.enabled {
            let overwrite = ui.yesOrNoChoicePrompt(
                question: "Remote config already exists. Overwrite it?",
                defaultAnswer: false
            )
            if !overwrite {
                print("Remote configuration unchanged.")
                return
            }
        }

        let provider = ui.singleChoicePrompt(
            title: "Remote storage",
            question: "Select a provider:",
            options: RemoteConfig.Provider.allCases,
            description: "S3 and GCS are supported."
        )

        let bucket = ui.textPrompt(
            title: nil,
            prompt: "Bucket name",
            description: nil,
            validationRules: [NonEmptyValidationRule(error: "Bucket name cannot be empty.")]
        )

        var region: String?
        var project: String?

        switch provider {
        case .s3:
            region = ui.textPrompt(
                title: nil,
                prompt: "AWS region",
                description: TerminalText(stringLiteral: "Example: us-east-1"),
                validationRules: [NonEmptyValidationRule(error: "Region cannot be empty.")]
            )
        case .gcs:
            project = ui.textPrompt(
                title: nil,
                prompt: "GCP project (optional)",
                description: TerminalText(stringLiteral: "Leave blank to use default credentials."),
                validationRules: []
            )
            if project?.isEmpty == true {
                project = nil
            }
        }

        let prefix = ui.textPrompt(
            title: nil,
            prompt: "Bucket prefix (optional)",
            description: TerminalText(stringLiteral: "Leave blank for bucket root."),
            validationRules: []
        )

        let compressionChoice = ui.singleChoicePrompt(
            title: "Compression",
            question: "Select compression for uploads:",
            options: RemoteConfig.Compression.allCases,
            description: "zstd is recommended for large indexes."
        )

        let autoPull = ui.yesOrNoChoicePrompt(
            title: "Sync",
            question: "Auto-pull before search when remote is newer?",
            defaultAnswer: false
        )

        let remote = RemoteConfig(
            enabled: true,
            provider: provider,
            bucket: bucket,
            region: region,
            project: project,
            prefix: prefix,
            sync: RemoteConfig.Sync(compression: compressionChoice, autoPull: autoPull)
        )

        print("\nValidating credentials...")
        do {
            let providerClient = try RemoteCLI.makeProvider(from: remote)
            _ = try await providerClient.exists(remotePath: "manifest.json")
            print("✓ Credentials verified")
        } catch {
            print("✗ Credential validation failed: \(error.localizedDescription)")
            throw ExitCode.failure
        }

        try writeRemoteConfig(remote, to: configPath)
        print("\nUpdated configuration: \(configPath)")
    }

    private func writeRemoteConfig(_ remote: RemoteConfig, to path: String) throws {
        let contents = try String(contentsOfFile: path, encoding: .utf8)
        let decoder = TOMLDecoder()
        let value = try decoder.decode(TOMLValue.self, from: contents)

        guard case let .table(rootTable) = value else {
            throw ValidationError("Root of .swiftindex.toml must be a table")
        }

        var updated = rootTable
        var remoteTable: [String: TOMLValue] = [
            "enabled": .boolean(remote.enabled),
            "provider": .string(remote.provider.rawValue),
            "bucket": .string(remote.bucket),
            "prefix": .string(remote.prefix),
        ]

        if let region = remote.region {
            remoteTable["region"] = .string(region)
        }

        if let project = remote.project {
            remoteTable["project"] = .string(project)
        }

        remoteTable["sync"] = .table([
            "compression": .string(remote.sync.compression.rawValue),
            "auto_pull": .boolean(remote.sync.autoPull),
        ])

        updated["remote"] = .table(remoteTable)

        let encoder = TOMLEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let output = try encoder.encodeToString(TOMLValue.table(updated))
        try output.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
