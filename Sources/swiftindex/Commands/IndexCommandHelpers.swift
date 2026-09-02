// MARK: - Index Command Helpers

import ArgumentParser
import Foundation
import Logging
import SwiftIndexCore

// MARK: - Description Generator Factory

enum DescriptionGeneratorFactory {
    static func create(
        config: Config,
        logger: Logger
    ) -> DescriptionGenerator? {
        guard config.searchEnhancement.enabled else {
            return nil
        }

        do {
            let provider = try LLMProviderFactory.createProvider(
                from: config.searchEnhancement.utility,
                openAIKey: config.openAIAPIKey,
                anthropicKey: config.anthropicAPIKey
            )
            return DescriptionGenerator(
                provider: provider,
                batchSize: 5,
                timeout: config.searchEnhancement.utility.timeout
            )
        } catch {
            logger.warning("Failed to create description generator: \(error)")
            return nil
        }
    }

    static func checkAvailability(
        _ generator: DescriptionGenerator?,
        logger: Logger
    ) async {
        guard let generator else { return }
        let available = await generator.isAvailable()
        if available {
            print("Description generation: enabled")
        } else {
            logger.debug("LLM provider not available, descriptions will be skipped")
        }
    }
}

// MARK: - Graph Recording

extension FileIndexer {
    /// Records a file's symbols and references for the call graph.
    static func recordGraphFacts(
        path: String,
        content: String,
        fileHash: String,
        chunks: [CodeChunk],
        context: IndexingContext
    ) async throws {
        guard let graphBuilder = context.graphBuilder, path.hasSuffix(".swift") else { return }

        let facts = SwiftGraphFactsExtractor.extract(
            content: content,
            path: path,
            fileHash: fileHash,
            module: GraphBuilder.inferModule(path: path, projectRoot: context.projectPath)
        )
        try await graphBuilder.record(facts: facts, chunks: chunks)
    }

    /// Records graph facts for a file whose chunks are already current.
    static func backfillGraphIfNeeded(
        path: String,
        content: String,
        fileHash: String,
        context: IndexingContext
    ) async throws {
        guard let graphBuilder = context.graphBuilder, path.hasSuffix(".swift") else { return }
        guard await graphBuilder.needsBackfill(path: path) else { return }

        try await recordGraphFacts(
            path: path,
            content: content,
            fileHash: fileHash,
            chunks: [],
            context: context
        )
    }
}

// MARK: - File Indexer

enum FileIndexer {
    static func indexFile(
        at path: String,
        context: IndexingContext,
        force: Bool
    ) async throws -> FileIndexResult {
        // Check for cancellation
        try Task.checkCancellation()

        // Read file content
        let content = try String(contentsOfFile: path, encoding: .utf8)

        // Compute file hash for incremental indexing
        let fileHash = FileHasher.hash(content)

        // Check if file needs indexing (unless force is set)
        if !force {
            let needsIndexing = try await context.indexManager.needsIndexing(path: path, fileHash: fileHash)
            if !needsIndexing {
                // Chunks are current, but the graph may not be: turning the graph on
                // for an existing index would otherwise leave it empty until someone
                // ran --force. Backfilling is cheap because it re-parses only files
                // with no symbols recorded yet.
                try await backfillGraphIfNeeded(path: path, content: content, fileHash: fileHash, context: context)
                context.logger.debug("Skipping unchanged file: \(path)")
                return FileIndexResult(chunksIndexed: 0, chunksReused: 0, skipped: true)
            }
        }

        // Parse file
        let parseResult = context.parser.parse(content: content, path: path, fileHash: fileHash)

        if case let .failure(error) = parseResult {
            context.logger.debug("Parse failed for \(path): \(error)")
            return FileIndexResult(chunksIndexed: 0, chunksReused: 0, skipped: false)
        }

        var chunks = parseResult.chunks
        guard !chunks.isEmpty else {
            // Record file as indexed even if no chunks (to avoid re-processing)
            try await context.indexManager.recordIndexed(fileHash: fileHash, path: path)
            return FileIndexResult(chunksIndexed: 0, chunksReused: 0, skipped: false)
        }

        // Generate descriptions if enabled
        let (updatedChunks, descriptionsGenerated) = await generateDescriptions(
            for: chunks,
            path: path,
            context: context
        )
        chunks = updatedChunks

        // Re-index the file with content-hash-based change detection
        let reindexResult = try await context.indexManager.reindexWithChangeDetection(
            path: path,
            newChunks: chunks
        ) { chunksToEmbed in
            let contents = chunksToEmbed.map(\.content)
            return try await context.embeddingBatcher.embed(contents)
        }

        // Record graph facts in the same pass that produced the chunks. Edges are
        // written unresolved; names are resolved once the whole symbol table exists.
        try await recordGraphFacts(
            path: path,
            content: content,
            fileHash: fileHash,
            chunks: chunks,
            context: context
        )

        // Index info snippets (documentation) if present
        let snippets = parseResult.snippets
        var snippetsIndexed = 0
        if !snippets.isEmpty {
            snippetsIndexed = try await context.indexManager.reindexSnippets(path: path, snippets: snippets)
        }

        context.logger.debug("Indexed file", metadata: [
            "path": "\(path)",
            "total": "\(reindexResult.totalChunks)",
            "embedded": "\(reindexResult.embeddedChunks)",
            "reused": "\(reindexResult.reusedChunks)",
            "descriptions": "\(descriptionsGenerated)",
            "snippets": "\(snippetsIndexed)",
        ])

        return FileIndexResult(
            chunksIndexed: reindexResult.totalChunks,
            chunksReused: reindexResult.reusedChunks,
            snippetsIndexed: snippetsIndexed,
            descriptionsGenerated: descriptionsGenerated,
            skipped: false
        )
    }

    private static func generateDescriptions(
        for chunks: [CodeChunk],
        path: String,
        context: IndexingContext
    ) async -> ([CodeChunk], Int) {
        guard let generator = context.descriptionGenerator,
              await context.descriptionState.isActive()
        else {
            return (chunks, 0)
        }

        // Compute relative path for progress display
        let relativePath: String = if path.hasPrefix(context.projectPath) {
            String(path.dropFirst(context.projectPath.count + 1))
        } else {
            (path as NSString).lastPathComponent
        }

        let batchResult = await generator.generateBatch(
            for: chunks,
            file: relativePath,
            onProgress: context.descriptionProgress
        )

        if batchResult.failures > 0 {
            let reason = batchResult.firstError ?? "Unknown error"
            let didDisable = await context.descriptionState.disable(reason: reason)
            if didDisable {
                var metadata: Logger.Metadata = [
                    "provider": "\(generator.providerName)",
                    "error": "\(reason)",
                ]
                if let hint = descriptionFailureHint(for: reason) {
                    metadata["hint"] = "\(hint)"
                }
                context.logger.warning("Description generation disabled after failure", metadata: metadata)
            }
        }

        guard !batchResult.descriptions.isEmpty else {
            return (chunks, 0)
        }

        // Create new chunks with descriptions
        let updatedChunks = chunks.map { chunk in
            if let description = batchResult.descriptions[chunk.id] {
                return CodeChunk(
                    id: chunk.id,
                    path: chunk.path,
                    content: chunk.content,
                    startLine: chunk.startLine,
                    endLine: chunk.endLine,
                    kind: chunk.kind,
                    symbols: chunk.symbols,
                    references: chunk.references,
                    fileHash: chunk.fileHash,
                    createdAt: chunk.createdAt,
                    docComment: chunk.docComment,
                    signature: chunk.signature,
                    breadcrumb: chunk.breadcrumb,
                    tokenCount: chunk.tokenCount,
                    language: chunk.language,
                    contentHash: chunk.contentHash,
                    generatedDescription: description,
                    conformances: chunk.conformances,
                    isTypeDeclaration: chunk.isTypeDeclaration
                )
            }
            return chunk
        }

        return (updatedChunks, batchResult.descriptions.count)
    }

    private static func descriptionFailureHint(for reason: String) -> String? {
        let lower = reason.lowercased()
        if lower.contains("rate limited") || lower.contains("rate limit") {
            return "Provider rate-limited; check quota or retry later."
        }
        if lower.contains("api key") {
            return "Missing or invalid API key."
        }
        if lower.contains("cli tool not found") || lower.contains("not found: claude") {
            return "CLI tool not available in PATH."
        }
        if lower.contains("process failed") {
            return "Provider process failed; check auth/credits or CLI status."
        }
        if lower.contains("not available") {
            return "Provider unavailable; check configuration and connectivity."
        }
        return nil
    }
}
