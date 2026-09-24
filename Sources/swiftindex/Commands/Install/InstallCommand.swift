// MARK: - InstallCommand

import ArgumentParser
import Foundation
import Logging
import Noora
import SwiftIndexCore

/// Registers SwiftIndex as an MCP server with every AI agent found on the machine.
///
/// Replaces having to know, and run, a separate command per agent.
struct InstallCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Configure SwiftIndex for installed AI coding agents",
        discussion: """
        Detects installed agents and registers the SwiftIndex MCP server with each.

        Examples:
          swiftindex install                       Configure every detected agent
          swiftindex install --global              Use global rather than project config
          swiftindex install --agent claude-code   Configure specific agents
          swiftindex install --all                 Configure every known agent
          swiftindex install --list                Show detection results only
          swiftindex install --dry-run             Show what would change
          swiftindex install --hook                Also add the Claude Code prompt hook
          swiftindex install --remove              Remove everything install added
        """
    )

    @Option(name: .long, help: "Agent id to configure (repeatable).")
    var agent: [String] = []

    @Flag(name: .long, help: "Configure every known agent, detected or not.")
    var all = false

    @Flag(name: .long, help: "Show detection results without changing anything.")
    var list = false

    @Flag(name: .long, help: "Write global instead of project-local configuration.")
    var global = false

    @Flag(name: .long, help: "Show what would change without writing.")
    var dryRun = false

    @Flag(name: .long, help: "Overwrite an existing SwiftIndex entry.")
    var force = false

    @Option(name: .long, help: "Path to the swiftindex binary.")
    var binaryPath: String?

    @Flag(
        inversion: .prefixedNo,
        help: "Write usage rules into CLAUDE.md, AGENTS.md or GEMINI.md (project scope only)."
    )
    var instructions = true

    @Flag(name: .long, help: "Add a Claude Code prompt hook that injects matching code for named symbols.")
    var hook = false

    @Flag(name: .long, help: "Remove the MCP entries, instruction blocks, permissions and hook.")
    var remove = false

    @Flag(name: .long, help: "Enable verbose logging.")
    var verbose = false

    func run() async throws {
        let logger = CLIUtils.makeLogger(verbose: verbose)
        let targets = try selectTargets()

        if list {
            printDetection(targets)
            return
        }

        let pathResult = CLIUtils.resolveExecutablePath(explicitPath: binaryPath)
        if pathResult.isDevelopmentBuild {
            print("Warning: using a development build at \(pathResult.path).")
            print("Agents will keep pointing at this path after the build directory changes.")
            print("")
        }

        let workingDirectory = FileManager.default.currentDirectoryPath
        let scope: InstallScope = global ? .global : .project

        if remove {
            try removeInstallation(targets: targets, scope: scope, workingDirectory: workingDirectory)
            return
        }

        var rows: [(name: String, path: String, outcome: InstallOutcome)] = []
        var restartNames: [String] = []
        var failures: [InstallFileError] = []

        for target in targets {
            // Some agents have no project-scoped config; fall back to global rather
            // than silently skipping them.
            let effectiveScope: InstallScope =
                target.configPath(scope: scope, workingDirectory: workingDirectory) == nil ? .global : scope

            guard let plan = MCPConfigWriter.plan(
                target: target,
                scope: effectiveScope,
                executablePath: pathResult.path,
                workingDirectory: workingDirectory
            ) else {
                continue
            }

            if dryRun {
                rows.append((target.displayName, plan.configPath, .wouldInstall))
                logger.debug("Would write to \(plan.configPath):\n\(plan.preview)")
                continue
            }

            do {
                let outcome = try MCPConfigWriter.apply(plan, force: force)
                rows.append((target.displayName, plan.configPath, outcome))
                if outcome == .installed || outcome == .updated {
                    restartNames.append(target.displayName)
                }
            } catch let error as InstallFileError {
                rows.append((target.displayName, plan.configPath, .skippedUnreadable))
                failures.append(error)
            }
        }

        printResults(rows, dryRun: dryRun)
        if !dryRun {
            try installAgentGuidance(
                targets: targets,
                scope: scope,
                executablePath: pathResult.path,
                workingDirectory: workingDirectory,
                failures: &failures
            )
        }

        if !restartNames.isEmpty {
            print("")
            print("Restart \(restartNames.joined(separator: ", ")) to load the SwiftIndex tools.")
        }
        try report(failures)
    }

    // MARK: - Agent Guidance

    /// Writes instruction blocks and Claude Code settings for project installs.
    private func installAgentGuidance(
        targets: [AgentTarget],
        scope: InstallScope,
        executablePath: String,
        workingDirectory: String,
        failures: inout [InstallFileError]
    ) throws {
        guard scope == .project else { return }

        var changed: [String] = []
        if instructions {
            let files = targets.compactMap { AgentInstructionsWriter.fileName(forAgent: $0.id) }
                .map { (workingDirectory as NSString).appendingPathComponent($0) }
            changed += try AgentInstructionsWriter.apply(paths: files, removing: false, failures: &failures)
        }
        if targets.contains(where: { $0.id == "claude-code" }) {
            let path = ClaudeSettingsWriter.settingsPath(workingDirectory: workingDirectory)
            let command = hook ? ClaudeSettingsWriter.hookCommand(executablePath: executablePath) : nil
            if try collecting(&failures, { try ClaudeSettingsWriter.apply(
                path: path, hookCommand: command, removing: false
            ) }) {
                changed.append(path)
            }
        }
        printChanged(changed, verb: "Updated")
    }

    private func removeInstallation(targets: [AgentTarget], scope: InstallScope, workingDirectory: String) throws {
        var changed: [String] = []
        var failures: [InstallFileError] = []
        for target in targets {
            guard let path = target.configPath(scope: scope, workingDirectory: workingDirectory)
                ?? target.configPath(scope: .global, workingDirectory: workingDirectory)
            else {
                continue
            }
            if try collecting(&failures, { try MCPConfigWriter.remove(configPath: path, format: target.format) }) {
                changed.append(path)
            }
        }
        if scope == .project {
            let files = targets.compactMap { AgentInstructionsWriter.fileName(forAgent: $0.id) }
                .map { (workingDirectory as NSString).appendingPathComponent($0) }
            changed += try AgentInstructionsWriter.apply(paths: files, removing: true, failures: &failures)
            let settings = ClaudeSettingsWriter.settingsPath(workingDirectory: workingDirectory)
            if try collecting(&failures, { try ClaudeSettingsWriter.apply(
                path: settings, hookCommand: nil, removing: true
            ) }) {
                changed.append(settings)
            }
        }
        printChanged(changed, verb: "Removed SwiftIndex from")
        if changed.isEmpty, failures.isEmpty {
            print("Nothing to remove.")
        }
        try report(failures)
    }

    private func collecting(_ failures: inout [InstallFileError], _ body: () throws -> Bool) throws -> Bool {
        do {
            return try body()
        } catch let error as InstallFileError {
            failures.append(error)
            return false
        }
    }

    private func report(_ failures: [InstallFileError]) throws {
        guard !failures.isEmpty else { return }
        print("")
        for failure in failures {
            print(failure.description)
        }
        throw ExitCode.failure
    }

    private func printChanged(_ paths: [String], verb: String) {
        guard !paths.isEmpty else { return }
        print("")
        print("\(verb):")
        for path in paths {
            print("  \(path)")
        }
    }

    // MARK: - Helpers

    private func selectTargets() throws -> [AgentTarget] {
        if !agent.isEmpty {
            return try agent.map { id in
                guard let target = AgentRegistry.target(id: id) else {
                    let known = AgentRegistry.all.map(\.id).joined(separator: ", ")
                    throw ValidationError("Unknown agent '\(id)'. Known agents: \(known)")
                }
                return target
            }
        }

        if all {
            return AgentRegistry.all
        }

        let detected = AgentRegistry.all.filter { $0.isDetected() }
        if detected.isEmpty, !list {
            print("No supported AI agents detected.")
            print("")
            print("Use --all to configure every known agent, or --agent <id> to pick one.")
            print("Known agents: \(AgentRegistry.all.map(\.id).joined(separator: ", "))")
        }
        return detected
    }

    private func printDetection(_ selected: [AgentTarget]) {
        let selectedIDs = Set(selected.map(\.id))
        print("Known agents:")
        print("")
        for target in AgentRegistry.all {
            let detected = target.isDetected()
            let marker = detected ? "[OK]" : "[--]"
            let note = selectedIDs.contains(target.id) && detected ? " (would configure)" : ""
            let paddedID = target.id.padding(toLength: 16, withPad: " ", startingAt: 0)
            print("  \(marker) \(paddedID) \(target.displayName)\(note)")
        }
    }

    private func printResults(
        _ rows: [(name: String, path: String, outcome: InstallOutcome)],
        dryRun: Bool
    ) {
        guard !rows.isEmpty else { return }

        print(dryRun ? "Dry run - would configure:" : "SwiftIndex MCP configuration:")
        print("")
        for row in rows {
            print("  \(row.name): \(row.outcome.summary)")
            print("    \(row.path)")
        }
    }
}
