// MARK: - AgentInstructionsWriter

import Foundation

/// Keeps a marked SwiftIndex block in the instruction files agents read.
///
/// MCP server instructions reach only the main session. Subagents, and agents
/// that do not read them, learn which tools to use from CLAUDE.md, AGENTS.md or
/// GEMINI.md instead.
enum AgentInstructionsWriter {
    static let startMarker = "<!-- SWIFTINDEX_START -->"
    static let endMarker = "<!-- SWIFTINDEX_END -->"

    static let block = """
    \(startMarker)
    ## SwiftIndex

    This project has a SwiftIndex index: text search, semantic search and a symbol graph.

    - To understand code, call the `explore` MCP tool first. It returns ranked source with line numbers in Read format.
    - Use `code_graph` for callers, callees, impact and dead code.
    - To find the tests for a change, run `git diff --name-only | swiftindex affected --stdin`.
    - Use Grep only for exact text that the index cannot find.
    - Give these rules to subagents: they do not see MCP server instructions.
    \(endMarker)
    """

    /// Instruction file an agent reads in the project root, if it has one.
    static func fileName(forAgent id: String) -> String? {
        switch id {
        case "claude-code": "CLAUDE.md"
        case "gemini": "GEMINI.md"
        case "codex", "cursor", "windsurf": "AGENTS.md"
        default: nil
        }
    }

    /// Replaces the marked block, or appends it when the file has none.
    static func upsert(into content: String) -> String {
        let stripped = remove(from: content)
        guard !stripped.isEmpty else { return block + "\n" }
        return stripped + (stripped.hasSuffix("\n") ? "\n" : "\n\n") + block + "\n"
    }

    /// Removes the marked block and the separator line that `upsert` added before it.
    static func remove(from content: String) -> String {
        guard let start = content.range(of: startMarker),
              let end = content.range(of: endMarker, range: start.upperBound ..< content.endIndex)
        else {
            return content
        }
        var before = String(content[..<start.lowerBound])
        var after = content[end.upperBound...]
        if after.hasPrefix("\n") {
            after.removeFirst()
        }
        if after.isEmpty, before.hasSuffix("\n\n") {
            before.removeLast()
        }
        return before + after
    }

    /// Writes or removes the block in each file, once per real file.
    ///
    /// In many repositories CLAUDE.md is a symlink to AGENTS.md; resolving links
    /// keeps the block from being written twice into one file. A file that exists
    /// but is not readable UTF-8 text is never written; it goes into `failures`.
    ///
    /// - Returns: The paths that changed.
    static func apply(paths: [String], removing: Bool, failures: inout [InstallFileError]) throws -> [String] {
        let fileManager = FileManager.default
        var seen = Set<String>()
        var changed: [String] = []
        for path in paths {
            let realPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            guard seen.insert(realPath).inserted else { continue }

            var existing = ""
            if fileManager.fileExists(atPath: realPath) {
                guard let data = fileManager.contents(atPath: realPath) else {
                    failures.append(InstallFileError(path: path, reason: "cannot be read"))
                    continue
                }
                guard let text = String(data: data, encoding: .utf8) else {
                    failures.append(InstallFileError(path: path, reason: "is not UTF-8 text"))
                    continue
                }
                existing = text
            }
            if removing, !existing.contains(startMarker) {
                continue
            }
            let updated = removing ? remove(from: existing) : upsert(into: existing)
            guard updated != existing else { continue }
            try updated.write(toFile: realPath, atomically: true, encoding: .utf8)
            changed.append(path)
        }
        return changed
    }
}
