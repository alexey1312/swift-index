// MARK: - StatusCommand

import ArgumentParser
import Foundation
import Logging
import SwiftIndexCore

/// Reports how SwiftIndex is configured and whether its index is usable.
///
/// `providers` only answers "which embedding backends exist"; it says nothing about
/// whether an index exists, matches the current provider, or has fallen behind the
/// working tree — which is what people actually need when search misbehaves.
struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show configuration, index and freshness status",
        discussion: """
        Exits non-zero when something needs attention, so it can gate CI.

        Examples:
          swiftindex status
          swiftindex status --json
          swiftindex status /path/to/project
        """,
        aliases: ["stats"]
    )

    @Argument(help: "Project path (defaults to current directory).")
    var path: String = "."

    @Flag(name: .long, help: "Emit machine-readable JSON.")
    var json = false

    @Option(name: .long, help: "Path to a specific config file.")
    var config: String?

    @Flag(name: .long, help: "Enable verbose logging.")
    var verbose = false

    func run() async throws {
        let logger = CLIUtils.makeLogger(verbose: verbose)
        let resolvedPath = FileCollector.canonicalPath(CLIUtils.resolvePath(path))

        let configuration = try CLIUtils.loadConfig(
            from: config,
            projectDirectory: resolvedPath,
            logger: logger
        )

        let report = await DiagnosticsCollector.collect(
            projectPath: resolvedPath,
            config: configuration,
            configSources: Self.configSources(projectDirectory: resolvedPath, explicit: config),
            logger: logger
        )

        if json {
            print(Self.renderJSON(report))
        } else {
            print(Self.renderHuman(report))
        }

        if !report.isHealthy {
            throw ExitCode.failure
        }
    }

    // MARK: - Rendering

    static func configSources(projectDirectory: String, explicit: String?) -> [String] {
        if let explicit {
            return [CLIUtils.resolvePath(explicit)]
        }

        var sources: [String] = []
        let project = (projectDirectory as NSString).appendingPathComponent(".swiftindex.toml")
        if FileManager.default.fileExists(atPath: project) {
            sources.append(project)
        }

        let global = "\(NSHomeDirectory())/.config/swiftindex/config.toml"
        if FileManager.default.fileExists(atPath: global) {
            sources.append(global)
        }

        return sources
    }

    private static func renderHuman(_ report: DiagnosticsReport) -> String {
        var lines: [String] = []
        lines.append("SwiftIndex status: \(report.projectPath)")
        lines.append("")

        lines.append("Configuration")
        if report.usingBuiltInDefaults {
            lines.append("  source:    built-in defaults (no config file)")
        } else {
            for source in report.configSources {
                lines.append("  source:    \(source)")
            }
        }
        lines.append("  provider:  \(report.resolvedProviderID)")
        lines.append("  model:     \(report.resolvedModelID)")
        lines.append("  dimension: \(report.resolvedDimension)")
        lines.append("")

        lines.append("Embedding providers")
        for provider in report.providers {
            let marker = provider.isReady ? "[OK]" : "[--]"
            let note = provider.isReady ? "ready" : "model not downloaded"
            let dimension = provider.dimension.map { " (\($0)-dim)" } ?? ""
            lines.append("  \(marker) \(provider.id)\(dimension) — \(note)")
        }
        lines.append("")

        lines.append("Index")
        if report.index.exists {
            lines.append("  path:      \(report.index.path)")
            lines.append("  chunks:    \(report.index.chunkCount)")
            lines.append("  vectors:   \(report.index.vectorCount)")
            lines.append("  files:     \(report.index.fileCount)")
            lines.append("  consistent: \(report.index.isConsistent ? "yes" : "no")")
            if let metadata = report.index.metadata {
                lines.append("  built by:  \(metadata.providerID)/\(metadata.modelID) (\(metadata.dimension)-dim)")
            }
        } else {
            lines.append("  no index — run 'swiftindex index' to create one")
        }
        lines.append("")

        if let graph = report.graph, graph.symbols > 0 {
            lines.append("Symbol graph")
            lines.append("  symbols:   \(graph.symbols)")
            lines.append("  edges:     \(graph.edges) (\(graph.resolvedPercentage)% resolved)")
            if graph.isDirty {
                lines.append("  state:     incomplete — a resolution pass did not finish")
            }
            lines.append("")
        }

        if let freshness = report.freshness {
            lines.append("Freshness")
            if freshness.isClean {
                lines.append("  index matches the working tree")
            } else {
                lines.append("  \(freshness.added) added, \(freshness.modified) modified, \(freshness.deleted) deleted")
                lines.append("  run 'swiftindex index' to catch up")
            }
            lines.append("")
        }

        if !report.warnings.isEmpty {
            lines.append("Warnings")
            for warning in report.warnings {
                for (offset, line) in warning.split(separator: "\n").enumerated() {
                    lines.append(offset == 0 ? "  ! \(line)" : "    \(line)")
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func renderJSON(_ report: DiagnosticsReport) -> String {
        var payload: [String: Any] = [
            "project_path": report.projectPath,
            "healthy": report.isHealthy,
            "using_built_in_defaults": report.usingBuiltInDefaults,
            "config_sources": report.configSources,
            "provider": report.resolvedProviderID,
            "model": report.resolvedModelID,
            "dimension": report.resolvedDimension,
            "providers": report.providers.map { provider in
                var entry: [String: Any] = ["id": provider.id, "ready": provider.isReady]
                if let dimension = provider.dimension {
                    entry["dimension"] = dimension
                }
                return entry
            },
            "index": [
                "exists": report.index.exists,
                "path": report.index.path,
                "chunks": report.index.chunkCount,
                "vectors": report.index.vectorCount,
                "files": report.index.fileCount,
                "consistent": report.index.isConsistent,
            ],
            "warnings": report.warnings,
        ]

        if let graph = report.graph {
            payload["graph"] = [
                "symbols": graph.symbols,
                "edges": graph.edges,
                "resolved": graph.resolved,
                "dirty": graph.isDirty,
            ]
        }

        if let freshness = report.freshness {
            payload["freshness"] = [
                "added": freshness.added,
                "modified": freshness.modified,
                "deleted": freshness.deleted,
                "clean": freshness.isClean,
            ]
        }

        guard let data = try? JSONCodec.serialize(payload, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return string
    }
}
