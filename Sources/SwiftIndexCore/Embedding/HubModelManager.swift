// MARK: - HubModelManager

import Foundation
import Hub
import Tokenizers

/// Manages embedding models from HuggingFace Hub using swift-transformers.
///
/// This actor provides a unified interface for downloading, caching, and loading
/// embedding models and their tokenizers. It leverages the HuggingFace Hub API
/// for reliable downloads with progress reporting and automatic caching.
///
/// ## Features
///
/// - Automatic model downloading from HuggingFace Hub
/// - Progress reporting during downloads
/// - Model caching with validation
/// - Tokenizer loading via AutoTokenizer
/// - Thread-safe operation via actor isolation
///
/// ## Usage
///
/// ```swift
/// let manager = HubModelManager()
///
/// // Download and get model path
/// let modelPath = try await manager.ensureModel(.bgeSmall) { progress in
///     print("Downloaded: \(Int(progress * 100))%")
/// }
///
/// // Load tokenizer for a model
/// let tokenizer = try await manager.loadTokenizer(for: .bgeSmall)
/// let tokens = tokenizer.encode(text: "Hello, world!")
/// ```
public actor HubModelManager {
    // MARK: - Types

    /// Supported embedding models.
    public enum Model: String, Sendable, CaseIterable {
        case bgeSmall = "bge-small-en-v1.5"
        case bgeBase = "bge-base-en-v1.5"
        case miniLM = "all-MiniLM-L6-v2"

        /// HuggingFace repository identifier.
        public var huggingFaceId: String {
            switch self {
            case .bgeSmall:
                "BAAI/bge-small-en-v1.5"
            case .bgeBase:
                "BAAI/bge-base-en-v1.5"
            case .miniLM:
                "sentence-transformers/all-MiniLM-L6-v2"
            }
        }

        /// Embedding dimension for this model.
        public var dimension: Int {
            switch self {
            case .bgeSmall, .miniLM:
                384
            case .bgeBase:
                768
            }
        }

        /// Approximate download size in bytes.
        public var approximateSize: Int64 {
            switch self {
            case .bgeSmall:
                133_000_000 // ~127 MB
            case .bgeBase:
                438_000_000 // ~418 MB
            case .miniLM:
                91_000_000 // ~87 MB
            }
        }

        /// Required files for this model.
        public var requiredFiles: [String] {
            [
                "config.json",
                "tokenizer.json",
                "tokenizer_config.json",
                "*.safetensors",
            ]
        }
    }

    /// Progress callback type.
    public typealias ProgressHandler = @Sendable (Double) -> Void

    // MARK: - Properties

    private let fileManager: FileManager
    private var cachedTokenizers: [Model: any Tokenizer] = [:]
    private var activeDownloads: [Model: Task<URL, Error>] = [:]

    /// Custom cache directory override (for testing).
    private let customCacheDirectory: URL?

    /// Hub API instance for downloads.
    private var hubApi: HubApi {
        if let cacheDir = customCacheDirectory {
            return HubApi(downloadBase: cacheDir)
        }
        return HubApi()
    }

    // MARK: - Initialization

    /// Creates a new hub model manager.
    ///
    /// - Parameters:
    ///   - fileManager: File manager for local operations (default: default).
    ///   - cacheDirectory: Optional custom cache directory (for testing).
    public init(
        fileManager: FileManager = .default,
        cacheDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        customCacheDirectory = cacheDirectory
    }

    // MARK: - Public API

    /// Ensures a model is available locally, downloading if necessary.
    ///
    /// - Parameters:
    ///   - model: The model to ensure availability.
    ///   - progress: Optional callback for download progress (0.0 - 1.0).
    /// - Returns: Path to the model directory.
    /// - Throws: `ProviderError.downloadFailed` on failure.
    public func ensureModel(
        _ model: Model,
        progress: ProgressHandler? = nil
    ) async throws -> URL {
        // Check for existing download task
        if let existingTask = activeDownloads[model] {
            return try await existingTask.value
        }

        // Start new download task
        let task = Task<URL, Error> {
            try await downloadModel(model, progress: progress)
        }

        activeDownloads[model] = task

        do {
            let result = try await task.value
            activeDownloads[model] = nil
            return result
        } catch {
            activeDownloads[model] = nil
            throw error
        }
    }

    /// Loads or retrieves a cached tokenizer for a model.
    ///
    /// - Parameter model: The model to get tokenizer for.
    /// - Returns: The tokenizer for the model.
    /// - Throws: `ProviderError.downloadFailed` if model cannot be downloaded.
    public func loadTokenizer(for model: Model) async throws -> any Tokenizer {
        // Return cached tokenizer if available
        if let cached = cachedTokenizers[model] {
            return cached
        }

        // Ensure model is downloaded
        let modelDir = try await ensureModel(model, progress: nil)

        // Load tokenizer from model directory
        let tokenizer = try await AutoTokenizer.from(modelFolder: modelDir)

        // Cache for future use
        cachedTokenizers[model] = tokenizer

        return tokenizer
    }

    /// Checks if a model is already cached locally.
    ///
    /// - Parameter model: The model to check.
    /// - Returns: `true` if the model appears to be cached.
    public func isModelCached(_ model: Model) -> Bool {
        let repo = Hub.Repo(id: model.huggingFaceId)
        let hubApi = hubApi

        // Check if the snapshot directory exists
        let repoDir = hubApi.localRepoLocation(repo)
        let configPath = repoDir.appendingPathComponent("config.json")

        return fileManager.fileExists(atPath: configPath.path)
    }

    /// Returns the local path for a cached model.
    ///
    /// - Parameter model: The model to get path for.
    /// - Returns: Path to model directory if cached, nil otherwise.
    public func cachedModelPath(_ model: Model) -> URL? {
        guard isModelCached(model) else { return nil }
        let repo = Hub.Repo(id: model.huggingFaceId)
        return hubApi.localRepoLocation(repo)
    }

    /// Clears all cached models and tokenizers.
    ///
    /// - Throws: File system errors on failure.
    public func clearCache() throws {
        cachedTokenizers.removeAll()

        // Remove model directories
        for model in Model.allCases {
            let modelDir = cachedModelPath(model)
            if let dir = modelDir, fileManager.fileExists(atPath: dir.path) {
                try fileManager.removeItem(at: dir)
            }
        }
    }

    /// Lists all cached models with their sizes.
    ///
    /// - Returns: Dictionary of model to size in bytes.
    public func listCachedModels() -> [Model: Int64] {
        var result: [Model: Int64] = [:]

        for model in Model.allCases where isModelCached(model) {
            if let modelDir = cachedModelPath(model),
               let size = directorySize(modelDir)
            {
                result[model] = size
            }
        }

        return result
    }

    // MARK: - Private Helpers

    private func downloadModel(
        _ model: Model,
        progress: ProgressHandler?
    ) async throws -> URL {
        let repo = Hub.Repo(id: model.huggingFaceId)

        do {
            let modelDir = try await hubApi.snapshot(
                from: repo,
                matching: model.requiredFiles
            ) { downloadProgress in
                progress?(downloadProgress.fractionCompleted)
            }

            progress?(1.0)
            return modelDir
        } catch {
            throw ProviderError.downloadFailed(
                reason: "Failed to download model \(model.rawValue): \(error.localizedDescription)"
            )
        }
    }

    private func directorySize(_ url: URL) -> Int64? {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var size: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                  let fileSize = resourceValues.fileSize
            else {
                continue
            }
            size += Int64(fileSize)
        }

        return size
    }
}

// MARK: - Convenience Extensions

public extension HubModelManager {
    /// Human-readable size string.
    static func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
