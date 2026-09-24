// MARK: - ExploreCommand

import ArgumentParser
import Foundation
import Logging
import SwiftIndexCore

/// Prints the ranked, line-numbered source that answers a code question.
struct ExploreCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "explore",
        abstract: "Show the code that answers a question, ranked with the symbol graph",
        discussion: """
        Examples:
          swiftindex explore "how is the index saved"
          swiftindex explore "IndexManager.save ChunkStore" --max-files 3
          swiftindex explore "provider selection" --bm25
        """
    )

    @Argument(help: "Question or symbol names.")
    var query: String

    @Option(name: .long, help: "Maximum files in the answer.")
    var maxFiles: Int?

    @Option(name: .long, help: "Maximum characters in the answer.")
    var budget: Int?

    @Flag(name: .long, help: "Find seeds with text search only, without an embedding model.")
    var bm25 = false

    @Option(name: .long, help: "Project path.")
    var path = "."

    @Flag(name: .long, help: "Enable verbose logging.")
    var verbose = false

    func validate() throws {
        if let budget, budget <= 0 {
            throw ValidationError("--budget must be a positive number of characters.")
        }
    }

    func run() async throws {
        let logger = CLIUtils.makeLogger(verbose: verbose)
        let resolvedPath = FileCollector.canonicalPath(CLIUtils.resolvePath(path))
        let configuration = try CLIUtils.loadConfig(from: nil, projectDirectory: resolvedPath, logger: logger)
        let indexPath = (resolvedPath as NSString).appendingPathComponent(configuration.indexPath)
        guard FileManager.default.fileExists(atPath: indexPath) else {
            throw ValidationError("Index not found at \(indexPath). Run 'swiftindex index' first.")
        }

        let engine = try await makeEngine(configuration: configuration, indexPath: indexPath, logger: logger)
        var options = ExploreOptions(maxFiles: maxFiles, projectRoot: resolvedPath)
        if let budget {
            let tier = ExploreBudget.forIndex(fileCount: 0)
            options.budget = ExploreBudget(characters: budget, files: maxFiles ?? tier.files)
        }
        let result = try await engine.explore(query: query, options: options)
        print(result.text)
    }

    /// Uses hybrid seeds when the index has vectors and a provider can embed the
    /// query, else text search alone.
    private func makeEngine(configuration: Config, indexPath: String, logger: Logger) async throws -> ExploreEngine {
        let resolved = try await EmbeddingProviderFactory.resolve(
            config: configuration,
            indexDirectory: indexPath,
            logger: logger
        )
        let indexManager = try IndexManager(directory: indexPath, dimension: resolved.dimension)
        try await indexManager.load()
        let store = await indexManager.chunkStore

        let hasVectors = try await indexManager.vectorCount() > 0
        guard !bm25, hasVectors, await resolved.chain.isAvailable() else {
            let search = BM25Search(chunkStore: store)
            return ExploreEngine(store: store, seedSearch: search, graphConfig: configuration.graph)
        }
        let search = await HybridSearchEngine(
            chunkStore: store,
            vectorStore: indexManager.vectorStore,
            embeddingProvider: resolved.chain,
            rrfK: configuration.rrfK
        )
        return ExploreEngine(store: store, seedSearch: search, graphConfig: configuration.graph)
    }
}
