// MARK: - ClaudeSettingsWriter

import Foundation
import SwiftIndexCore

/// Adds SwiftIndex permissions and the prompt hook to Claude Code project settings.
enum ClaudeSettingsWriter {
    static let permission = "mcp__swiftindex__*"
    static let hookSubcommand = "prompt-hook"

    static func settingsPath(workingDirectory: String) -> String {
        (workingDirectory as NSString).appendingPathComponent(".claude/settings.json")
    }

    /// Settings with the SwiftIndex permission and, when `hookCommand` is set, the
    /// prompt hook. Existing keys stay as they are.
    static func merged(_ settings: [String: Any], hookCommand: String?) -> [String: Any] {
        var result = removed(settings)

        var permissions = result["permissions"] as? [String: Any] ?? [:]
        var allow = permissions["allow"] as? [String] ?? []
        allow.append(permission)
        permissions["allow"] = allow
        result["permissions"] = permissions

        if let hookCommand {
            var hooks = result["hooks"] as? [String: Any] ?? [:]
            var groups = hooks["UserPromptSubmit"] as? [[String: Any]] ?? []
            groups.append(["hooks": [["type": "command", "command": hookCommand]]])
            hooks["UserPromptSubmit"] = groups
            result["hooks"] = hooks
        }
        return result
    }

    /// Settings without anything SwiftIndex added.
    static func removed(_ settings: [String: Any]) -> [String: Any] {
        var result = settings

        if var permissions = result["permissions"] as? [String: Any],
           let allow = permissions["allow"] as? [String]
        {
            permissions["allow"] = allow.filter { $0 != permission }
            result["permissions"] = permissions
        }

        if var hooks = result["hooks"] as? [String: Any],
           let groups = hooks["UserPromptSubmit"] as? [[String: Any]]
        {
            let kept = groups.filter { group in
                let commands = (group["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
                return !commands.contains { $0.hasSuffix(" " + hookSubcommand) }
            }
            if kept.isEmpty {
                hooks.removeValue(forKey: "UserPromptSubmit")
            } else {
                hooks["UserPromptSubmit"] = kept
            }
            result["hooks"] = hooks.isEmpty ? nil : hooks
        }
        return result
    }

    /// Updates the settings file.
    ///
    /// - Returns: Whether the file changed. An unreadable file is left alone.
    static func apply(path: String, hookCommand: String?, removing: Bool) throws -> Bool {
        let fileManager = FileManager.default
        var settings: [String: Any] = [:]
        if fileManager.fileExists(atPath: path) {
            guard let data = fileManager.contents(atPath: path),
                  let json = try? JSONCodec.deserialize(data) as? [String: Any]
            else {
                return false
            }
            settings = json
        } else if removing {
            return false
        }

        let updated = removing ? removed(settings) : merged(settings, hookCommand: hookCommand)
        let before = try JSONCodec.serialize(settings, options: [.prettyPrinted, .sortedKeys])
        let after = try JSONCodec.serialize(updated, options: [.prettyPrinted, .sortedKeys])
        guard before != after else { return false }

        try fileManager.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try after.write(to: URL(fileURLWithPath: path), options: .atomic)
        return true
    }
}
