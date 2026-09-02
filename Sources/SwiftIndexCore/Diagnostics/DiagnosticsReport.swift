// MARK: - DiagnosticsReport

import Foundation
import Logging

/// A snapshot of how SwiftIndex is configured and whether its index is usable.
public struct DiagnosticsReport: Sendable {
    public struct ProviderStatus: Sendable {
        public let id: String
        public let name: String
        /// Vector dimension, reported only for the provider actually selected.
        ///
        /// For other providers the value would merely echo `embedding.dimension` from
        /// configuration, which is misleading — MLX's real dimension depends on its
        /// model, not on a setting written for a different provider.
        public let dimension: Int?
        /// Ready to use without downloading anything.
        public let isReady: Bool
    }

    public struct IndexStatus: Sendable {
        public let exists: Bool
        public let path: String
        public let chunkCount: Int
        public let vectorCount: Int
        public let fileCount: Int
        public let isConsistent: Bool
        public let metadata: IndexMetadata?
    }

    public struct FreshnessStatus: Sendable {
        public let added: Int
        public let modified: Int
        public let deleted: Int
        public var isClean: Bool {
            added == 0 && modified == 0 && deleted == 0
        }
    }

    public let projectPath: String
    public let configSources: [String]
    public let usingBuiltInDefaults: Bool
    public let resolvedProviderID: String
    public let resolvedModelID: String
    public let resolvedDimension: Int
    public let providers: [ProviderStatus]
    public let index: IndexStatus
    public let freshness: FreshnessStatus?
    public let warnings: [String]

    /// Whether everything needed for a working search is in place.
    public var isHealthy: Bool {
        index.exists && index.chunkCount > 0 && index.isConsistent && warnings.isEmpty
    }
}

/// Collects diagnostics without side effects.
///
/// Deliberately never triggers a model download: `EmbeddingProvider.isAvailable()` may
/// load (and therefore fetch) a model, so asking "what works?" could otherwise cost
/// hundreds of megabytes. Readiness is probed with `isReady()` instead.
public enum DiagnosticsCollector {
    public static func collect(
        projectPath: String,
        config: Config,
        configSources: [String],
        logger: Logger = Logger(label: "Diagnostics")
    ) async -> DiagnosticsReport {
        var warnings: [String] = []

        // Resolve the provider the same way indexing would.
        var providerID = config.embeddingProvider
        var modelID = config.embeddingModel
        var dimension = config.embeddingDimension
        do {
            let resolved = try await EmbeddingProviderFactory.resolve(config: config, logger: logger)
            providerID = resolved.providerID
            modelID = resolved.modelID
            dimension = resolved.dimension
        } catch {
            warnings.append(
                "Configured provider '\(config.embeddingProvider)' is unusable: \(error.localizedDescription)"
            )
        }

        let providers = await probeProviders(
            config: config,
            selectedProviderID: providerID,
            logger: logger
        )
        if !providers.contains(where: \.isReady) {
            warnings.append(
                "No embedding provider is ready. The first index will download a model."
            )
        }

        let indexPath = (projectPath as NSString).appendingPathComponent(config.indexPath)
        let indexStatus = await inspectIndex(at: indexPath, dimension: dimension)

        if let metadata = indexStatus.metadata,
           let reason = metadata.incompatibilityReason(
               providerID: providerID,
               modelID: modelID,
               dimension: dimension
           )
        {
            warnings.append(reason)
        }

        var freshness: DiagnosticsReport.FreshnessStatus?
        if indexStatus.exists, indexStatus.chunkCount > 0 {
            freshness = await measureFreshness(
                projectPath: projectPath,
                config: config,
                indexPath: indexPath,
                dimension: dimension,
                logger: logger
            )
        }

        return DiagnosticsReport(
            projectPath: projectPath,
            configSources: configSources,
            usingBuiltInDefaults: configSources.isEmpty,
            resolvedProviderID: providerID,
            resolvedModelID: modelID,
            resolvedDimension: dimension,
            providers: providers,
            index: indexStatus,
            freshness: freshness,
            warnings: warnings
        )
    }

    // MARK: - Private

    private static func probeProviders(
        config: Config,
        selectedProviderID: String,
        logger: Logger
    ) async -> [DiagnosticsReport.ProviderStatus] {
        var statuses: [DiagnosticsReport.ProviderStatus] = []

        for id in ["mlx", "swift-embeddings", "ollama", "openai", "voyage", "gemini"] {
            guard let resolved = try? EmbeddingProviderFactory.make(
                provider: id,
                config: config,
                logger: logger
            ) else {
                // Usually a missing API key. Not a warning: most users configure one
                // provider and ignore the rest.
                continue
            }
            await statuses.append(DiagnosticsReport.ProviderStatus(
                id: id,
                name: resolved.chain.name,
                dimension: id == selectedProviderID ? resolved.dimension : nil,
                isReady: resolved.chain.isReady()
            ))
        }

        return statuses
    }

    private static func inspectIndex(at path: String, dimension: Int) async -> DiagnosticsReport.IndexStatus {
        let metadata = IndexMetadata.load(fromIndexDirectory: path)
        let dbPath = (path as NSString).appendingPathComponent("chunks.db")

        guard FileManager.default.fileExists(atPath: dbPath) else {
            return DiagnosticsReport.IndexStatus(
                exists: false,
                path: path,
                chunkCount: 0,
                vectorCount: 0,
                fileCount: 0,
                isConsistent: true,
                metadata: metadata
            )
        }

        // Open with the index's own dimension where known, so merely inspecting a
        // mismatched index does not fail.
        let effectiveDimension = metadata?.dimension ?? dimension
        guard let manager = try? IndexManager(directory: path, dimension: effectiveDimension) else {
            return DiagnosticsReport.IndexStatus(
                exists: true,
                path: path,
                chunkCount: 0,
                vectorCount: 0,
                fileCount: 0,
                isConsistent: false,
                metadata: metadata
            )
        }

        // The vector index lives on disk; without loading it, statistics would report
        // zero vectors for a perfectly healthy index and call it inconsistent.
        try? await manager.load()

        guard let stats = try? await manager.statistics() else {
            return DiagnosticsReport.IndexStatus(
                exists: true,
                path: path,
                chunkCount: 0,
                vectorCount: 0,
                fileCount: 0,
                isConsistent: false,
                metadata: metadata
            )
        }

        return DiagnosticsReport.IndexStatus(
            exists: true,
            path: path,
            chunkCount: stats.chunkCount,
            vectorCount: stats.vectorCount,
            fileCount: stats.fileCount,
            isConsistent: stats.isConsistent,
            metadata: metadata
        )
    }

    private static func measureFreshness(
        projectPath: String,
        config: Config,
        indexPath: String,
        dimension: Int,
        logger: Logger
    ) async -> DiagnosticsReport.FreshnessStatus? {
        guard let manager = try? IndexManager(directory: indexPath, dimension: dimension),
              let report = try? await IndexReconciler(logger: logger).reconcile(
                  path: projectPath,
                  config: config,
                  chunkStore: manager.chunkStore
              )
        else {
            return nil
        }

        return DiagnosticsReport.FreshnessStatus(
            added: report.added.count,
            modified: report.modified.count,
            deleted: report.deleted.count
        )
    }
}
