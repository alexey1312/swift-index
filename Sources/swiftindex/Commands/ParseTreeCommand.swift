// MARK: - Parse Tree Command

import ArgumentParser
import Foundation
import SwiftIndexCore

/// Command to visualize the AST structure of Swift files.
///
/// Usage:
///   swiftindex parse-tree MyFile.swift
///   swiftindex parse-tree Sources/ --pattern "**/*.swift"
///   swiftindex parse-tree Sources/ --kind class,struct --format human
struct ParseTreeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "parse-tree",
        abstract: "Visualize Swift AST structure",
        discussion: """
        Parses Swift files and displays their abstract syntax tree structure.
        Supports both single files and directories with glob patterns.

        Examples:
          swiftindex parse-tree MyFile.swift
          swiftindex parse-tree Sources/
          swiftindex parse-tree Sources/ --pattern "*/Models/*.swift"
          swiftindex parse-tree MyFile.swift --kind class,struct,method
          swiftindex parse-tree Sources/ --max-depth 2 --format human
        """
    )

    // MARK: - Arguments

    @Argument(
        help: "Path to a Swift file or directory"
    )
    var path: String

    // MARK: - Options

    @Option(
        name: [.short, .long],
        help: "Glob pattern for directory mode (default: **/*.swift)"
    )
    var pattern: String?

    @Option(
        name: .long,
        help: "Maximum AST depth to traverse"
    )
    var maxDepth: Int?

    @Option(
        name: [.short, .long],
        parsing: .upToNextOption,
        help: "Filter by node kinds (e.g., class, struct, method, function)"
    )
    var kind: [String] = []

    @Option(
        name: [.short, .long],
        help: "Output format: toon, human, or json (default: human)"
    )
    var format: OutputFormat = .human

    @Flag(
        name: [.short, .long],
        help: "Enable verbose debug output"
    )
    var verbose: Bool = false

    // MARK: - Execution

    mutating func run() async throws {
        let logger = CLIUtils.makeLogger(verbose: verbose)

        // Resolve path
        let resolvedPath = CLIUtils.resolvePath(path)
        logger.debug("Resolved path: \(resolvedPath)")

        // Check if path exists
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolvedPath, isDirectory: &isDirectory) else {
            throw ValidationError("Path does not exist: \(resolvedPath)")
        }

        // Build options
        // Support both "--kind struct --kind method" and "--kind struct,method" formats
        let allKinds = kind.flatMap { $0.split(separator: ",").map { String($0).lowercased() } }
        let kindFilter: Set<String>? = allKinds.isEmpty ? nil : Set(allKinds)
        let options = ParseTreeOptions(
            maxDepth: maxDepth,
            kindFilter: kindFilter,
            expandChildren: true,
            pattern: pattern
        )

        let visualizer = ParseTreeVisualizer()

        if isDirectory.boolValue {
            // Directory mode
            logger.info("Scanning directory: \(resolvedPath)")

            let result = try await visualizer.visualizeDirectory(at: resolvedPath, options: options)

            if result.files.isEmpty {
                print("No matching Swift files found.")
                let effectivePattern = pattern ?? "**/*.swift"
                print("Pattern: \(effectivePattern)")
                return
            }

            logger.info("Found \(result.totalFiles) files, \(result.totalNodes) nodes")

            let output = try formatBatchResult(result, format: format, visualizer: visualizer)
            print(output)

        } else {
            // Single file mode
            logger.info("Parsing file: \(resolvedPath)")

            let result = try visualizer.visualizeFile(at: resolvedPath, options: options)

            if result.nodes.isEmpty {
                print("No declarations found in file.")
                return
            }

            logger.info("Found \(result.totalNodes) nodes, max depth \(result.maxDepth)")

            let output = try formatSingleResult(result, format: format, visualizer: visualizer)
            print(output)
        }
    }

    // MARK: - Private Helpers

    private func formatSingleResult(
        _ result: ParseTreeResult,
        format: OutputFormat,
        visualizer: ParseTreeVisualizer
    ) throws -> String {
        switch format {
        case .human:
            visualizer.formatHuman(result)
        case .toon:
            visualizer.formatTOON(result)
        case .json:
            try visualizer.formatJSON(result)
        }
    }

    private func formatBatchResult(
        _ result: ParseTreeBatchResult,
        format: OutputFormat,
        visualizer: ParseTreeVisualizer
    ) throws -> String {
        switch format {
        case .human:
            visualizer.formatHuman(result)
        case .toon:
            visualizer.formatTOON(result)
        case .json:
            try visualizer.formatJSON(result)
        }
    }
}
