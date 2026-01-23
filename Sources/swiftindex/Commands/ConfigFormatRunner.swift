import ArgumentParser
import Foundation
import Logging
import SwiftIndexCore

enum ConfigFormatRunner {
    static func run(
        config: String?,
        all: Bool,
        check: Bool,
        stdin: Bool,
        verbose: Bool
    ) throws {
        if stdin {
            if all || config != nil {
                throw ValidationError("Use --stdin without --all or --config")
            }
            try formatStdin(checkOnly: check)
            return
        }

        if all, config != nil {
            throw ValidationError("Use --all without --config")
        }

        let logger = CLIUtils.makeLogger(verbose: verbose)
        let targets = try resolveTargets(config: config, all: all)

        if targets.isEmpty {
            print("No .swiftindex.toml files found.")
            return
        }

        var hadChanges = false

        for path in targets {
            let contents = try String(contentsOfFile: path, encoding: .utf8)
            let formatted = try TOMLConfigValidator.format(contents: contents)

            if contents == formatted {
                if !check {
                    print("Already formatted: \(path)")
                }
                continue
            }

            if check {
                print("UNFORMATTED: \(path)")
                hadChanges = true
                continue
            }

            try formatted.write(toFile: path, atomically: true, encoding: .utf8)
            logger.info("Formatted configuration", metadata: ["path": "\(path)"])
            print("Formatted: \(path)")
            hadChanges = true
        }

        if check, hadChanges {
            throw ExitCode(2)
        }
    }

    private static func resolveTargets(config: String?, all: Bool) throws -> [String] {
        if let config {
            let resolvedPath = CLIUtils.resolvePath(config)
            guard FileManager.default.fileExists(atPath: resolvedPath) else {
                throw ConfigError.fileNotFound(resolvedPath)
            }
            return [resolvedPath]
        }

        if !all {
            let resolvedPath = CLIUtils.resolvePath(".swiftindex.toml")
            guard FileManager.default.fileExists(atPath: resolvedPath) else {
                throw ConfigError.fileNotFound(resolvedPath)
            }
            return [resolvedPath]
        }

        return findConfigFiles()
    }

    private static func findConfigFiles() -> [String] {
        let root = FileManager.default.currentDirectoryPath
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else {
            return []
        }

        var results: [String] = []

        for case let url as URL in enumerator {
            if let isDirectory = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory,
               isDirectory,
               shouldSkipDirectory(url)
            {
                enumerator.skipDescendants()
                continue
            }

            if url.lastPathComponent == ".swiftindex.toml" {
                results.append(url.path)
            }
        }

        return results.sorted()
    }

    private static func shouldSkipDirectory(_ url: URL) -> Bool {
        switch url.lastPathComponent {
        case ".git", ".build", "DerivedData", ".swiftindex":
            true
        default:
            false
        }
    }

    private static func formatStdin(checkOnly: Bool) throws {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        let contents = String(data: data, encoding: .utf8) ?? ""
        let formatted = try TOMLConfigValidator.format(contents: contents)

        if checkOnly {
            if contents != formatted {
                throw ExitCode(2)
            }
            return
        }

        print(formatted)
    }
}
