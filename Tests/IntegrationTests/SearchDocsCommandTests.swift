import Foundation
import Testing

@testable import SwiftIndexCore

/// Tests for SearchDocsCommand.
@Suite("SearchDocsCommand Tests")
struct SearchDocsCommandTests {
    // MARK: - Test Fixtures

    /// Path to the swiftindex executable.
    private var executablePath: String {
        let fm = FileManager.default
        let root = packageRootPath

        if let buildDir = ProcessInfo.processInfo.environment["SWIFTPM_BUILD_DIR"] {
            let candidate = (buildDir as NSString).appendingPathComponent("swiftindex")
            if fm.fileExists(atPath: candidate) {
                return candidate
            }
        }

        if let candidate = findBuiltExecutable(in: (root as NSString).appendingPathComponent(".build")) {
            return candidate
        }

        return "swift"
    }

    /// Arguments to pass before command when using swift run.
    private var baseArgs: [String] {
        if executablePath == "swift" {
            return ["run", "swiftindex"]
        }
        return []
    }

    /// Temporary directory for test fixtures.
    private var tempDir: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftindex-docs-tests-\(UUID().uuidString)")
    }

    /// Package root path.
    private var packageRootPath: String {
        let fm = FileManager.default
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

        while true {
            let candidate = dir.appendingPathComponent("Package.swift").path
            if fm.fileExists(atPath: candidate) {
                return dir.path
            }

            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path {
                break
            }
            dir = parent
        }

        return fm.currentDirectoryPath
    }

    private func findBuiltExecutable(in buildRoot: String) -> String? {
        let fm = FileManager.default
        let directDebug = (buildRoot as NSString).appendingPathComponent("debug/swiftindex")
        if fm.fileExists(atPath: directDebug) {
            return directDebug
        }

        guard let entries = try? fm.contentsOfDirectory(atPath: buildRoot) else {
            return nil
        }

        for entry in entries {
            let candidate = (buildRoot as NSString).appendingPathComponent("\(entry)/debug/swiftindex")
            if fm.fileExists(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    // MARK: - Helper Methods

    private func runCommand(
        _ arguments: [String],
        workingDirectory: String? = nil,
        environment: [String: String]? = nil
    ) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        let process = Process()

        if executablePath == "swift" {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
            process.arguments = baseArgs + arguments
        } else {
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
        }

        if let workDir = workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workDir)
        }

        var processEnv = ProcessInfo.processInfo.environment
        processEnv["SWIFTINDEX_EMBEDDING_PROVIDER"] = "mock"
        if let env = environment {
            for (key, value) in env {
                processEnv[key] = value
            }
        }
        process.environment = processEnv

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        return (stdout, stderr, process.terminationStatus)
    }

    private func createTestFixtures() throws -> URL {
        let dir = tempDir
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Create a sample Markdown file
        let mdFile = dir.appendingPathComponent("README.md")
        try """
        # Project Documentation

        ## Installation

        To install the project, run:
        `npm install`

        ## Configuration

        Configure the project using `config.json`.
        """.write(to: mdFile, atomically: true, encoding: .utf8)

        // Create config file with mock provider
        let configFile = dir.appendingPathComponent(".swiftindex.toml")
        try """
        [embedding]
        provider = "mock"
        model = "all-MiniLM-L6-v2"
        dimension = 384
        """.write(to: configFile, atomically: true, encoding: .utf8)

        return dir
    }

    private func prepareIndexedFixtures() throws -> URL {
        let dir = try createTestFixtures()
        let (_, _, exitCode) = try runCommand(["index", "--force", dir.path])
        #expect(exitCode == 0, "Indexing fixtures should succeed")
        return dir
    }

    private func cleanupFixtures(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Tests

    @Test("search-docs help")
    func searchDocsHelp() throws {
        let (stdout, _, exitCode) = try runCommand(["search-docs", "--help"])
        #expect(exitCode == 0)
        #expect(stdout.contains("Search indexed documentation"))
        #expect(stdout.contains("--format"))
    }

    @Test("search-docs with query")
    func searchDocsWithQuery() throws {
        let fixtureDir = try prepareIndexedFixtures()
        defer { cleanupFixtures(fixtureDir) }

        let (stdout, _, exitCode) = try runCommand([
            "search-docs",
            "install",
            "--path",
            fixtureDir.path,
        ])

        #expect(exitCode == 0)
        // Check for content from README.md
        #expect(stdout.contains("README.md") || stdout.contains("docs_search"))
        // TOON format default
        #expect(stdout.contains("docs_search"))
    }

    @Test("search-docs human format")
    func searchDocsHumanFormat() throws {
        let fixtureDir = try prepareIndexedFixtures()
        defer { cleanupFixtures(fixtureDir) }

        let (stdout, _, exitCode) = try runCommand([
            "search-docs",
            "configuration",
            "--format", "human",
            "--path",
            fixtureDir.path,
        ])

        #expect(exitCode == 0)
        #expect(stdout.contains("Found"))
        #expect(stdout.contains("README.md"))
        #expect(stdout.contains("Configuration"))
    }

    @Test("search-docs json format")
    func searchDocsJSONFormat() throws {
        let fixtureDir = try prepareIndexedFixtures()
        defer { cleanupFixtures(fixtureDir) }

        let (stdout, _, exitCode) = try runCommand([
            "search-docs",
            "install",
            "--format", "json",
            "--path",
            fixtureDir.path,
        ])

        #expect(exitCode == 0)
        #expect(stdout.contains("\"query\": \"install\""))
        #expect(stdout.contains("\"content\""))
    }
}
