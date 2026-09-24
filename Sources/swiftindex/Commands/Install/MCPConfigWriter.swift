// MARK: - MCPConfigWriter

import Foundation
import SwiftIndexCore

/// Result of applying an install plan.
enum InstallOutcome: Sendable, Equatable {
    case installed
    case updated
    case alreadyPresent
    case skippedUnreadable
    case wouldInstall

    var summary: String {
        switch self {
        case .installed: "installed"
        case .updated: "updated"
        case .alreadyPresent: "already configured"
        case .skippedUnreadable: "skipped (unreadable config)"
        case .wouldInstall: "would install"
        }
    }
}

/// A configuration file that exists but cannot be parsed. Install never overwrites it.
struct InstallFileError: Error, CustomStringConvertible {
    let path: String
    let reason: String

    var description: String {
        "\(path) \(reason). Fix it and run again."
    }

    static func invalidJSON(path: String, error: Error?) -> InstallFileError {
        InstallFileError(path: path, reason: "is not valid JSON: " + (error.map { "\($0)" } ?? "not a JSON object"))
    }

    /// Top-level JSON object in `data`, or an error that names `path`.
    static func jsonObject(path: String, data: Data) throws -> [String: Any] {
        let parsed: Any
        do {
            parsed = try JSONCodec.deserialize(data)
        } catch {
            throw invalidJSON(path: path, error: error)
        }
        guard let object = parsed as? [String: Any] else { throw invalidJSON(path: path, error: nil) }
        return object
    }
}

/// A planned change to one agent's configuration.
struct InstallPlan: Sendable {
    let target: AgentTarget
    let configPath: String
    let executablePath: String
    let workingDirectory: String?
    /// Rendered configuration, used for both `--dry-run` output and the real write.
    let preview: String
}

/// Writes SwiftIndex's MCP entry into an agent's configuration.
///
/// `plan` and `apply` share the rendered configuration so `--dry-run` cannot drift
/// from what actually gets written — previously each install command printed its own
/// separate preview.
enum MCPConfigWriter {
    static let serverName = "swiftindex"

    // MARK: - Planning

    static func plan(
        target: AgentTarget,
        scope: InstallScope,
        executablePath: String,
        workingDirectory: String
    ) -> InstallPlan? {
        guard let configPath = target.configPath(scope: scope, workingDirectory: workingDirectory) else {
            return nil
        }

        let cwd = (target.includesCwd && scope == .project) ? workingDirectory : nil
        let preview: String = switch target.format {
        case .mcpServersJSON:
            renderJSONPreview(executablePath: executablePath)
        case .codexTOML:
            renderTOMLSection(executablePath: executablePath, cwd: cwd)
        }

        return InstallPlan(
            target: target,
            configPath: configPath,
            executablePath: executablePath,
            workingDirectory: cwd,
            preview: preview
        )
    }

    // MARK: - Applying

    static func apply(_ plan: InstallPlan, force: Bool) throws -> InstallOutcome {
        switch plan.target.format {
        case .mcpServersJSON:
            try applyJSON(plan, force: force)
        case .codexTOML:
            try applyTOML(plan, force: force)
        }
    }

    // MARK: - JSON

    private static func renderJSONPreview(executablePath: String) -> String {
        let entry: [String: Any] = ["mcpServers": [serverName: serverEntry(executablePath: executablePath)]]
        guard let data = try? JSONCodec.serialize(entry, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return string
    }

    private static func serverEntry(executablePath: String) -> [String: Any] {
        ["type": "stdio", "command": executablePath, "args": ["serve"]]
    }

    private static func applyJSON(_ plan: InstallPlan, force: Bool) throws -> InstallOutcome {
        let fileManager = FileManager.default
        var existing: [String: Any] = [:]
        let exists = fileManager.fileExists(atPath: plan.configPath)

        if exists {
            // Refuse even with --force: ~/.claude.json also holds Claude Code's own state.
            guard let data = fileManager.contents(atPath: plan.configPath) else {
                throw InstallFileError(path: plan.configPath, reason: "cannot be read")
            }
            existing = try InstallFileError.jsonObject(path: plan.configPath, data: data)
        }

        var servers = existing["mcpServers"] as? [String: Any] ?? [:]
        let alreadyPresent = servers[serverName] != nil
        if alreadyPresent, !force {
            return .alreadyPresent
        }

        try backUpIfNeeded(path: plan.configPath, exists: exists)

        servers[serverName] = serverEntry(executablePath: plan.executablePath)
        existing["mcpServers"] = servers

        try createParentDirectory(for: plan.configPath)
        let data = try JSONCodec.serialize(existing, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: plan.configPath), options: .atomic)

        return alreadyPresent ? .updated : .installed
    }

    // MARK: - TOML

    private static func renderTOMLSection(executablePath: String, cwd: String?) -> String {
        var section = """
        [mcp_servers.\(serverName)]
        command = "\(executablePath)"
        args = ["serve"]
        """
        if let cwd {
            section += "\ncwd = \"\(cwd)\""
        }
        return section
    }

    private static func applyTOML(_ plan: InstallPlan, force: Bool) throws -> InstallOutcome {
        let fileManager = FileManager.default
        let exists = fileManager.fileExists(atPath: plan.configPath)
        var contents = ""

        if exists {
            guard let existing = try? String(contentsOfFile: plan.configPath, encoding: .utf8) else {
                throw InstallFileError(path: plan.configPath, reason: "is not readable UTF-8 text")
            }
            contents = existing
        }

        let alreadyPresent = contents.contains("[mcp_servers.\(serverName)]")
        if alreadyPresent, !force {
            return .alreadyPresent
        }

        if alreadyPresent {
            contents = removeSection(from: contents)
        }

        return try writeTOML(plan, contents: contents, exists: exists, alreadyPresent: alreadyPresent)
    }

    private static func writeTOML(
        _ plan: InstallPlan,
        contents: String,
        exists: Bool,
        alreadyPresent: Bool
    ) throws -> InstallOutcome {
        try backUpIfNeeded(path: plan.configPath, exists: exists)
        try createParentDirectory(for: plan.configPath)

        var updated = contents
        if !updated.isEmpty, !updated.hasSuffix("\n\n") {
            updated += updated.hasSuffix("\n") ? "\n" : "\n\n"
        }
        updated += plan.preview + "\n"

        try updated.write(to: URL(fileURLWithPath: plan.configPath), atomically: true, encoding: .utf8)
        return alreadyPresent ? .updated : .installed
    }

    /// Removes an existing `[mcp_servers.swiftindex]` section.
    static func removeSection(from content: String) -> String {
        var result: [String] = []
        var inSection = false

        for line in content.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces) == "[mcp_servers.\(serverName)]" {
                inSection = true
                continue
            }
            if inSection, line.hasPrefix("[") {
                inSection = false
            }
            if !inSection {
                result.append(line)
            }
        }

        while result.last?.isEmpty == true {
            result.removeLast()
        }
        return result.joined(separator: "\n")
    }

    // MARK: - Removal

    /// Removes the SwiftIndex entry from one config file.
    ///
    /// - Returns: Whether the file changed.
    /// - Throws: `InstallFileError` for a file that exists but cannot be parsed. The file is left alone.
    static func remove(configPath: String, format: MCPConfigFormat) throws -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: configPath) else { return false }
        guard let data = fileManager.contents(atPath: configPath) else {
            throw InstallFileError(path: configPath, reason: "cannot be read")
        }

        switch format {
        case .mcpServersJSON:
            var json = try InstallFileError.jsonObject(path: configPath, data: data)
            guard var servers = json["mcpServers"] as? [String: Any],
                  servers.removeValue(forKey: serverName) != nil
            else {
                return false
            }
            json["mcpServers"] = servers
            try backUpIfNeeded(path: configPath, exists: true)
            let updated = try JSONCodec.serialize(json, options: [.prettyPrinted, .sortedKeys])
            try updated.write(to: URL(fileURLWithPath: configPath), options: .atomic)
            return true

        case .codexTOML:
            guard let content = String(bytes: data, encoding: .utf8) else {
                throw InstallFileError(path: configPath, reason: "is not readable UTF-8 text")
            }
            let updated = removeSection(from: content)
            guard updated != content.trimmingCharacters(in: .newlines) else { return false }
            try backUpIfNeeded(path: configPath, exists: true)
            try (updated + "\n").write(toFile: configPath, atomically: true, encoding: .utf8)
            return true
        }
    }

    // MARK: - Safety

    /// Copies an existing config aside before modifying it.
    ///
    /// A single `swiftindex install` can now touch several files, including
    /// `~/.claude.json`, which holds Claude Code's own state rather than just MCP
    /// entries. Cheap insurance against a bad merge.
    private static func backUpIfNeeded(path: String, exists: Bool) throws {
        guard exists else { return }
        let backup = path + ".swiftindex.bak"
        try? FileManager.default.removeItem(atPath: backup)
        try FileManager.default.copyItem(atPath: path, toPath: backup)
    }

    private static func createParentDirectory(for path: String) throws {
        let directory = (path as NSString).deletingLastPathComponent
        guard !directory.isEmpty else { return }
        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )
    }
}
