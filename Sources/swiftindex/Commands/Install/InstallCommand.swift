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

        var rows: [(name: String, path: String, outcome: InstallOutcome)] = []
        var restartNames: [String] = []

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

            let outcome = try MCPConfigWriter.apply(plan, force: force)
            rows.append((target.displayName, plan.configPath, outcome))
            if outcome == .installed || outcome == .updated {
                restartNames.append(target.displayName)
            }
        }

        printResults(rows, dryRun: dryRun)

        if !restartNames.isEmpty {
            print("")
            print("Restart \(restartNames.joined(separator: ", ")) to load the SwiftIndex tools.")
        }

        if rows.contains(where: \.outcome.isFailure) {
            print("")
            print("Some configs could not be read. Re-run with --force to overwrite them.")
            throw ExitCode.failure
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
