// MARK: - AffectedCommand

import ArgumentParser
import Foundation
import Logging
import SwiftIndexCore

/// Lists the test files that a set of changed files can break.
struct AffectedCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "affected",
        abstract: "List test files affected by changed files",
        discussion: """
        Examples:
          swiftindex affected Sources/App/Store.swift
          git diff --name-only | swiftindex affected --stdin
          git diff --name-only main | swiftindex affected --stdin --format json
        """
    )

    @Argument(help: "Changed files, absolute or relative to the project path.")
    var files: [String] = []

    @Flag(name: .long, help: "Read changed files from standard input, one per line.")
    var stdin = false

    @Option(name: .long, help: "Maximum reverse graph hops (1-8).")
    var depth = 4

    @Option(name: .long, help: "Output format: plain or json.")
    var format = "plain"

    @Option(name: .long, help: "Project path.")
    var path = "."

    @Flag(name: .long, help: "Enable verbose logging.")
    var verbose = false

    func run() async throws {
        let logger = CLIUtils.makeLogger(verbose: verbose)
        let resolvedPath = FileCollector.canonicalPath(CLIUtils.resolvePath(path))
        let configuration = try CLIUtils.loadConfig(from: nil, projectDirectory: resolvedPath, logger: logger)

        var changed = files
        if stdin {
            while let line = readLine() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    changed.append(trimmed)
                }
            }
        }
        guard !changed.isEmpty else {
            throw ValidationError("Provide changed files as arguments or with --stdin.")
        }

        let databasePath = ((resolvedPath as NSString).appendingPathComponent(configuration.indexPath) as NSString)
            .appendingPathComponent("chunks.db")
        guard FileManager.default.fileExists(atPath: databasePath) else {
            throw ValidationError("No index found. Run 'swiftindex index' first.")
        }

        let tests = try await AffectedAnalyzer.affectedTests(
            changedPaths: changed,
            store: GRDBChunkStore(path: databasePath),
            projectRoot: resolvedPath,
            depth: min(max(depth, 1), 8)
        )
        try printResult(tests, projectRoot: resolvedPath)
    }

    private func printResult(_ tests: [AffectedTest], projectRoot: String) throws {
        let prefix = projectRoot.hasSuffix("/") ? projectRoot : projectRoot + "/"
        let relative = tests.map { test in
            AffectedTest(
                path: test.path.hasPrefix(prefix) ? String(test.path.dropFirst(prefix.count)) : test.path,
                reason: test.reason
            )
        }

        switch format.lowercased() {
        case "plain":
            for test in relative {
                print(test.path)
            }
        case "json":
            try print(String(bytes: JSONCodec.encodePretty(relative), encoding: .utf8) ?? "[]")
        default:
            throw ValidationError("Unknown format '\(format)'. Valid: plain, json.")
        }
    }
}
