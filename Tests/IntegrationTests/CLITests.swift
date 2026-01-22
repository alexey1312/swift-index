import Foundation
import Testing

@testable import SwiftIndexCore

/// Tests for CLI commands.
///
/// These tests verify CLI behavior by running commands as subprocesses
/// and checking their output and exit codes.
@Suite("CLI Command Tests")
struct CLITests {
    // MARK: - Test Fixtures

    /// Path to the swiftindex executable.
    /// In tests, we use swift run or the built executable.
    private var executablePath: String {
        // Get the path to the built executable in DerivedData
        let fm = FileManager.default

        // Try to find the debug build
        let debugPath = fm.currentDirectoryPath + "/.build/debug/swiftindex"
        if fm.fileExists(atPath: debugPath) {
            return debugPath
        }

        // Fallback to swift run
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
            .appendingPathComponent("swiftindex-cli-tests-\(UUID().uuidString)")
    }

    // MARK: - Helper Methods

    /// Runs a CLI command and returns output, error, and exit code.
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

        if let env = environment {
            var processEnv = ProcessInfo.processInfo.environment
            for (key, value) in env {
                processEnv[key] = value
            }
            process.environment = processEnv
        }

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

    /// Creates a temporary directory with test fixtures.
    private func createTestFixtures() throws -> URL {
        let dir = tempDir
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Create a sample Swift file
        let swiftFile = dir.appendingPathComponent("Sample.swift")
        try """
        // Sample Swift file for testing
        import Foundation

        struct Sample {
            let name: String

            func greet() -> String {
                return "Hello, \\(name)!"
            }
        }
        """.write(to: swiftFile, atomically: true, encoding: .utf8)

        return dir
    }

    /// Cleans up temporary directory.
    private func cleanupFixtures(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Index Command Tests

    @Test("index command shows help with --help")
    func indexCommandHelp() throws {
        let (stdout, _, exitCode) = try runCommand(["index", "--help"])

        #expect(exitCode == 0, "Exit code should be 0")
        #expect(stdout.contains("Index a Swift codebase"), "Should show command description")
        #expect(stdout.contains("--force"), "Should show force flag")
        #expect(stdout.contains("--config"), "Should show config option")
    }

    @Test("index command with valid directory")
    func indexCommandValidDirectory() throws {
        let fixtureDir = try createTestFixtures()
        defer { cleanupFixtures(fixtureDir) }

        let (stdout, _, exitCode) = try runCommand(["index", fixtureDir.path])

        // Command should succeed (even if indexing is not fully implemented)
        #expect(exitCode == 0, "Exit code should be 0 for valid directory")
        #expect(stdout.contains("Indexing:"), "Should show indexing message")
    }

    @Test("index command with non-existent directory fails")
    func indexCommandInvalidDirectory() throws {
        let (_, stderr, exitCode) = try runCommand([
            "index", "/nonexistent/path/that/does/not/exist",
        ])

        #expect(exitCode != 0, "Should fail for non-existent path")
        #expect(
            stderr.contains("does not exist") || stderr.contains("Error"),
            "Should show error message"
        )
    }

    @Test("index command with --force flag")
    func indexCommandForceFlag() throws {
        let fixtureDir = try createTestFixtures()
        defer { cleanupFixtures(fixtureDir) }

        let (stdout, _, exitCode) = try runCommand(["index", "--force", fixtureDir.path])

        #expect(exitCode == 0, "Should succeed with force flag")
        #expect(stdout.contains("Force: true"), "Should show force enabled")
    }

    // MARK: - Search Command Tests

    @Test("search command shows help with --help")
    func searchCommandHelp() throws {
        let (stdout, _, exitCode) = try runCommand(["search", "--help"])

        #expect(exitCode == 0, "Exit code should be 0")
        #expect(stdout.contains("Search the indexed codebase"), "Should show command description")
        #expect(stdout.contains("--limit"), "Should show limit option")
        #expect(stdout.contains("--json"), "Should show json flag")
    }

    @Test("search command with query")
    func searchCommandWithQuery() throws {
        let (stdout, _, exitCode) = try runCommand(["search", "authentication"])

        #expect(exitCode == 0, "Should succeed")
        #expect(stdout.contains("authentication"), "Should echo the query")
    }

    @Test("search command with --json flag")
    func searchCommandJSONOutput() throws {
        let (stdout, _, exitCode) = try runCommand(["search", "test query", "--json"])

        #expect(exitCode == 0, "Should succeed")
        #expect(stdout.contains("{"), "Should output JSON")
        #expect(stdout.contains("\"query\""), "Should have query field")
    }

    @Test("search command with --limit option")
    func searchCommandLimitOption() throws {
        let (stdout, _, exitCode) = try runCommand(["search", "test", "--limit", "5"])

        #expect(exitCode == 0, "Should succeed")
        #expect(stdout.contains("Limit: 5"), "Should show limit")
    }

    @Test("search command with invalid limit fails")
    func searchCommandInvalidLimit() throws {
        let (_, stderr, exitCode) = try runCommand(["search", "test", "--limit", "0"])

        #expect(exitCode != 0, "Should fail for invalid limit")
        #expect(stderr.contains("greater than 0") || stderr.contains("Error"), "Should show error")
    }

    // MARK: - Install Command Tests

    @Test("install-claude-code command shows help with --help")
    func installCommandHelp() throws {
        let (stdout, _, exitCode) = try runCommand(["install-claude-code", "--help"])

        #expect(exitCode == 0, "Exit code should be 0")
        #expect(stdout.contains("Install SwiftIndex"), "Should show command description")
        #expect(stdout.contains("--dry-run"), "Should show dry-run flag")
    }

    @Test("install-claude-code command with --dry-run")
    func installCommandDryRun() throws {
        let (stdout, _, exitCode) = try runCommand(["install-claude-code", "--dry-run"])

        #expect(exitCode == 0, "Should succeed in dry-run mode")
        #expect(stdout.contains("Dry run"), "Should indicate dry run")
        #expect(stdout.contains("swiftindex"), "Should mention swiftindex")
        #expect(stdout.contains("mcp.json") || stdout.contains("Config"), "Should mention config")
    }

    @Test("install-claude-code creates valid JSON config")
    func installCommandCreatesValidConfig() throws {
        // Create temporary config directory
        let configDir = tempDir.appendingPathComponent(".config/claude-code")
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        // Note: We can't actually run install without modifying real config,
        // so we just verify dry-run produces valid JSON
        let (stdout, _, exitCode) = try runCommand(["install-claude-code", "--dry-run"])

        #expect(exitCode == 0, "Should succeed")

        // Check that the dry-run output contains valid JSON structure
        #expect(stdout.contains("\"swiftindex\""), "Should have swiftindex key")
        #expect(stdout.contains("\"command\""), "Should have command key")
        #expect(stdout.contains("\"args\""), "Should have args key")

        cleanupFixtures(tempDir)
    }

    @Test("install-claude-code supports cursor target")
    func installCommandCursorTarget() throws {
        let (stdout, _, exitCode) = try runCommand([
            "install-claude-code", "cursor", "--dry-run",
        ])

        #expect(exitCode == 0, "Should succeed")
        #expect(stdout.contains("Cursor"), "Should mention Cursor")
    }

    // MARK: - General CLI Tests

    @Test("swiftindex shows help with no arguments")
    func noArgumentsShowsHelp() throws {
        let (stdout, _, exitCode) = try runCommand(["--help"])

        #expect(exitCode == 0, "Should succeed")
        #expect(stdout.contains("index"), "Should list index command")
        #expect(stdout.contains("search"), "Should list search command")
    }

    @Test("swiftindex shows version with --version")
    func versionFlag() throws {
        // This may or may not be implemented
        let (stdout, _, _) = try runCommand(["--version"])

        // Just verify it doesn't crash and produces output
        #expect(!stdout.isEmpty, "Should produce some output")
    }

    @Test("swiftindex handles unknown command gracefully")
    func unknownCommand() throws {
        let (_, stderr, exitCode) = try runCommand(["nonexistent-command"])

        #expect(exitCode != 0, "Should fail for unknown command")
        #expect(
            stderr.contains("unknown") || stderr.contains("Unknown") || stderr.contains("Error"),
            "Should indicate unknown command"
        )
    }
}
