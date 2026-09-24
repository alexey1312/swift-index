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

    static func hookCommand(executablePath: String) -> String {
        "'" + executablePath.replacingOccurrences(of: "'", with: #"'\''"#) + "' " + hookSubcommand
    }

    static func isSwiftIndexHook(_ command: String) -> Bool {
        command.trimmingCharacters(in: .whitespaces).hasSuffix(" " + hookSubcommand)
    }

    /// Settings with the SwiftIndex permission. When `hookCommand` is set, the prompt
    /// hook is added or replaced; otherwise an existing hook stays. Other keys stay as they are.
    static func merged(_ settings: [String: Any], hookCommand: String?) -> [String: Any] {
        var result = settings

        var permissions = result["permissions"] as? [String: Any] ?? [:]
        var allow = permissions["allow"] as? [String] ?? []
        if !allow.contains(permission) {
            allow.append(permission)
        }
        permissions["allow"] = allow
        result["permissions"] = permissions

        if let hookCommand {
            result = removingHook(result)
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
        var result = removingHook(settings)

        if var permissions = result["permissions"] as? [String: Any],
           let allow = permissions["allow"] as? [String],
           allow.contains(permission)
        {
            let kept = allow.filter { $0 != permission }
            permissions["allow"] = kept.isEmpty ? nil : kept
            result["permissions"] = permissions.isEmpty ? nil : permissions
        }
        return result
    }

    private static func removingHook(_ settings: [String: Any]) -> [String: Any] {
        guard var hooks = settings["hooks"] as? [String: Any],
              let groups = hooks["UserPromptSubmit"] as? [[String: Any]]
        else {
            return settings
        }
        var changed = false
        let kept: [[String: Any]] = groups.compactMap { group in
            guard let entries = group["hooks"] as? [[String: Any]] else { return group }
            let others = entries.filter { !isSwiftIndexHook($0["command"] as? String ?? "") }
            guard others.count != entries.count else { return group }
            changed = true
            guard !others.isEmpty else { return nil }
            var updated = group
            updated["hooks"] = others
            return updated
        }
        guard changed else { return settings }

        var result = settings
        hooks["UserPromptSubmit"] = kept.isEmpty ? nil : kept
        result["hooks"] = hooks.isEmpty ? nil : hooks
        return result
    }

    /// - Returns: Whether the file changed.
    /// - Throws: `InstallFileError` for a file that exists but is not a JSON object. The file is left alone.
    static func apply(path: String, hookCommand: String?, removing: Bool) throws -> Bool {
        let fileManager = FileManager.default
        var settings: [String: Any] = [:]
        if fileManager.fileExists(atPath: path) {
            guard let data = fileManager.contents(atPath: path) else {
                throw InstallFileError(path: path, reason: "cannot be read")
            }
            settings = try InstallFileError.jsonObject(path: path, data: data)
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
