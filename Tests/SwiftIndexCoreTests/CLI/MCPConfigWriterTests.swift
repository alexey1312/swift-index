import Foundation
import Testing

// The install machinery lives in the executable target, so these tests exercise the
// same file formats the writers produce and the invariants they must preserve.

@Suite("MCP Config Writer Format Tests")
struct MCPConfigWriterTests {
    private func makeTempDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .resolvingSymlinksInPath()
            .appendingPathComponent("swiftindex-install-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Merging preserves unrelated keys in an agent config")
    func mergePreservesUnknownKeys() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // ~/.claude.json holds Claude Code's own state, not just MCP entries. Losing
        // unrelated keys would corrupt the user's editor configuration.
        let path = directory.appendingPathComponent("config.json")
        let original: [String: Any] = [
            "someUnrelatedSetting": "keep-me",
            "mcpServers": ["other": ["command": "/usr/bin/other"]],
        ]
        try JSONSerialization
            .data(withJSONObject: original, options: [.prettyPrinted])
            .write(to: path)

        // Simulate the merge the writer performs.
        var config = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any]
        )
        var servers = try #require(config["mcpServers"] as? [String: Any])
        servers["swiftindex"] = ["type": "stdio", "command": "/usr/local/bin/swiftindex", "args": ["serve"]]
        config["mcpServers"] = servers
        try JSONSerialization
            .data(withJSONObject: config, options: [.prettyPrinted])
            .write(to: path)

        let reloaded = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any]
        )
        let reloadedServers = try #require(reloaded["mcpServers"] as? [String: Any])

        #expect(reloaded["someUnrelatedSetting"] as? String == "keep-me")
        #expect(reloadedServers["other"] != nil)
        #expect(reloadedServers["swiftindex"] != nil)
    }

    @Test("Codex TOML section removal leaves other sections intact")
    func tOMLSectionRemoval() {
        // Mirrors MCPConfigWriter.removeSection, which must not disturb neighbouring
        // sections when replacing the SwiftIndex entry.
        let content = """
        [mcp_servers.other]
        command = "/usr/bin/other"

        [mcp_servers.swiftindex]
        command = "/old/path/swiftindex"
        args = ["serve"]

        [profile.default]
        model = "gpt-5"
        """

        var result: [String] = []
        var inSection = false
        for line in content.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces) == "[mcp_servers.swiftindex]" {
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
        let stripped = result.joined(separator: "\n")

        #expect(!stripped.contains("[mcp_servers.swiftindex]"))
        #expect(!stripped.contains("/old/path/swiftindex"))
        #expect(stripped.contains("[mcp_servers.other]"))
        #expect(stripped.contains("[profile.default]"))
    }
}
