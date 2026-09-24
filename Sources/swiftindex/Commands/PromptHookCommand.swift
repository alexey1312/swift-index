// MARK: - PromptHookCommand

import ArgumentParser
import Foundation
import SwiftIndexCore

/// Claude Code `UserPromptSubmit` hook: adds the code for symbols a prompt names.
///
/// Runs before the agent starts, so an agent that would first search for a named
/// type gets its source at once. The hook injects context only when a code-like
/// word in the prompt is an exact symbol in the index. It uses text search and
/// the graph only, never an embedding model, and always exits 0: a hook failure
/// must never block the prompt.
struct PromptHookCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "prompt-hook",
        abstract: "Claude Code prompt hook (reads hook JSON on stdin)",
        shouldDisplay: false
    )

    static let timeout: Duration = .milliseconds(1500)
    static let budget = ExploreBudget(characters: 8000, files: 3)

    func run() async throws {
        let watchdog = Task.detached {
            try? await Task.sleep(for: Self.timeout)
            Foundation.exit(0)
        }
        defer { watchdog.cancel() }

        if let context = try? await Self.context(for: FileHandle.standardInput.readDataToEndOfFile()) {
            print(context)
        }
    }

    /// Hook output for one hook input, or nil when the prompt names no indexed symbol.
    static func context(for input: Data) async throws -> String? {
        guard let json = try JSONCodec.deserialize(input) as? [String: Any],
              let prompt = json["prompt"] as? String
        else {
            return nil
        }
        let cwd = json["cwd"] as? String ?? FileManager.default.currentDirectoryPath

        let config = (try? TOMLConfigLoader.loadLayered(
            env: .empty,
            projectDirectory: cwd,
            requireInitialization: false
        )) ?? Config()
        let database = ((cwd as NSString).appendingPathComponent(config.indexPath) as NSString)
            .appendingPathComponent("chunks.db")
        guard FileManager.default.fileExists(atPath: database) else { return nil }

        let store = try GRDBChunkStore(path: database)
        var named = false
        for token in ExploreEngine.identifierTokens(in: prompt) where !named {
            named = try await !store.findSymbols(matching: token, limit: 1).isEmpty
        }
        guard named else { return nil }

        let engine = ExploreEngine(store: store, seedSearch: BM25Search(chunkStore: store), graphConfig: config.graph)
        let result = try await engine.explore(
            query: prompt,
            options: ExploreOptions(budget: budget, projectRoot: FileCollector.canonicalPath(cwd))
        )
        guard !result.plan.files.isEmpty else { return nil }

        let output: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "UserPromptSubmit",
                "additionalContext": "SwiftIndex found code for symbols named in the prompt:\n\n" + result.text,
            ],
        ]
        return try String(bytes: JSONCodec.serialize(output, options: [.sortedKeys]), encoding: .utf8)
    }
}
