// MARK: - Fmt Command

import ArgumentParser
import Foundation
import Logging
import SwiftIndexCore

struct FmtCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fmt",
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
