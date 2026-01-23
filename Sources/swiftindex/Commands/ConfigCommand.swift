// MARK: - Config Command

import ArgumentParser
import Foundation
import Logging
import SwiftIndexCore

struct ConfigCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Lint and format SwiftIndex configuration",
        subcommands: [
            ConfigLintCommand.self,
            ConfigFormatCommand.self,
        ]
    )
}

struct ConfigLintCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lint",
        abstract: "Lint .swiftindex.toml for formatting and configuration issues"
    )

    @Option(
        name: .shortAndLong,
        help: "Path to configuration file (default: ./.swiftindex.toml)"
    )
    var config: String?

    @Flag(
        name: .shortAndLong,
        help: "Enable verbose debug output"
    )
    var verbose: Bool = false

    mutating func run() async throws {
        let logger = CLIUtils.makeLogger(verbose: verbose)
        let configPath = config ?? ".swiftindex.toml"
        let resolvedPath = CLIUtils.resolvePath(configPath)

        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            throw ConfigError.fileNotFound(resolvedPath)
        }

        let contents = try String(contentsOfFile: resolvedPath, encoding: .utf8)
        let diagnostics = try TOMLConfigValidator.lint(contents: contents, filePath: resolvedPath)

        if diagnostics.isEmpty {
            print("Config OK: \(resolvedPath)")
            return
        }

        logger.debug("Config lint diagnostics", metadata: ["path": "\(resolvedPath)"])

        for diagnostic in diagnostics {
            let prefix = diagnostic.severity.rawValue.uppercased()
            if let keyPath = diagnostic.keyPath {
                print("\(prefix): \(keyPath): \(diagnostic.message)")
            } else {
                print("\(prefix): \(diagnostic.message)")
            }
        }

        if diagnostics.contains(where: { $0.severity == .error }) {
            throw ExitCode(2)
        }
    }
}

struct ConfigFormatCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "format",
        abstract: "Format .swiftindex.toml using canonical TOML formatting"
    )

    @Option(
        name: .shortAndLong,
        help: "Path to configuration file (default: ./.swiftindex.toml)"
    )
    var config: String?

    @Flag(
        name: .shortAndLong,
        help: "Enable verbose debug output"
    )
    var verbose: Bool = false

    @Flag(
        name: .shortAndLong,
        help: "Check if configs are formatted without writing changes"
    )
    var check: Bool = false

    @Flag(
        name: .shortAndLong,
        help: "Format all .swiftindex.toml files under the current directory"
    )
    var all: Bool = false

    @Flag(
        name: .shortAndLong,
        help: "Read config from stdin and write formatted output to stdout"
    )
    var stdin: Bool = false

    mutating func run() async throws {
        try ConfigFormatRunner.run(
            config: config,
            all: all,
            check: check,
            stdin: stdin,
            verbose: verbose
        )
    }
}
