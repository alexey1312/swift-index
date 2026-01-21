// MARK: - ModelDownloader

import Foundation

/// Downloads and manages embedding models from HuggingFace Hub.
///
/// The `ModelDownloader` handles downloading, caching, and verification of
/// embedding models required by local providers (MLX, SwiftEmbeddings).
///
/// ## Features
///
/// - Progress reporting during download
/// - Resume interrupted downloads
/// - Verification of downloaded files
/// - Automatic cache management
///
/// ## Usage
///
/// ```swift
/// let downloader = ModelDownloader()
///
/// // Download a model
/// let modelPath = try await downloader.downloadModel(
///     .bgeSmall,
///     progressHandler: { progress in
///         print("Downloaded: \(Int(progress * 100))%")
///     }
/// )
///
/// // Check if model exists locally
/// let exists = await downloader.isModelCached(.bgeSmall)
/// ```
public actor ModelDownloader {
    // MARK: - Types

    /// Supported embedding models for download.
    public enum Model: String, Sendable, CaseIterable {
        case bgeSmall = "bge-small-en-v1.5"
        case bgeBase = "bge-base-en-v1.5"
        case miniLM = "all-MiniLM-L6-v2"

        /// HuggingFace repository identifier.
        public var huggingFaceId: String {
            switch self {
            case .bgeSmall:
                return "BAAI/bge-small-en-v1.5"
            case .bgeBase:
                return "BAAI/bge-base-en-v1.5"
            case .miniLM:
                return "sentence-transformers/all-MiniLM-L6-v2"
            }
        }

        /// Embedding dimension for this model.
        public var dimension: Int {
            switch self {
            case .bgeSmall, .miniLM:
                return 384
            case .bgeBase:
                return 768
            }
        }

        /// Approximate download size in bytes.
        public var approximateSize: Int64 {
            switch self {
            case .bgeSmall:
                return 133_000_000 // ~127 MB
            case .bgeBase:
                return 438_000_000 // ~418 MB
            case .miniLM:
                return 91_000_000 // ~87 MB
            }
        }

        /// Required files for this model.
        public var requiredFiles: [String] {
            [
                "model.safetensors",
                "vocab.txt",
                "config.json",
                "tokenizer_config.json",
            ]
        }
    }

    /// Progress callback type.
    public typealias ProgressHandler = @Sendable (Double) -> Void

    // MARK: - Properties

    private let session: URLSession
    private let fileManager: FileManager
    private var activeDownloads: [Model: Task<URL, Error>] = [:]

    /// Base directory for cached models.
    public var cacheDirectory: URL {
        let cacheDir =
            fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return cacheDir
            .appendingPathComponent("SwiftIndex")
            .appendingPathComponent("models")
    }

    // MARK: - Initialization

    /// Creates a new model downloader.
    ///
    /// - Parameters:
    ///   - session: URL session for downloads (default: shared).
    ///   - fileManager: File manager for local operations (default: default).
    public init(
        session: URLSession = .shared,
        fileManager: FileManager = .default
    ) {
        self.session = session
        self.fileManager = fileManager
    }

    // MARK: - Public API

    /// Checks if a model is already downloaded and valid.
    ///
    /// - Parameter model: The model to check.
    /// - Returns: `true` if all required files exist locally.
    public func isModelCached(_ model: Model) -> Bool {
        let modelDir = modelDirectory(for: model)
        return model.requiredFiles.allSatisfy { file in
            fileManager.fileExists(atPath: modelDir.appendingPathComponent(file).path)
        }
    }

    /// Returns the local path for a cached model.
    ///
    /// - Parameter model: The model to get path for.
    /// - Returns: Path to model directory if cached, nil otherwise.
    public func cachedModelPath(_ model: Model) -> URL? {
        guard isModelCached(model) else { return nil }
        return modelDirectory(for: model)
    }

    /// Downloads a model from HuggingFace Hub.
    ///
    /// - Parameters:
    ///   - model: The model to download.
    ///   - progressHandler: Optional callback for progress updates (0.0 - 1.0).
    /// - Returns: Path to the downloaded model directory.
    /// - Throws: `ProviderError.downloadFailed` on failure.
    public func downloadModel(
        _ model: Model,
        progressHandler: ProgressHandler? = nil
    ) async throws -> URL {
        // Check if already cached
        if isModelCached(model) {
            progressHandler?(1.0)
            return modelDirectory(for: model)
        }

        // Check for existing download task
        if let existingTask = activeDownloads[model] {
            return try await existingTask.value
        }

        // Start new download
        let task = Task<URL, Error> {
            try await performDownload(model, progressHandler: progressHandler)
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

    /// Downloads model if not cached, using ensure semantics.
    ///
    /// This is a convenience method that combines caching check with download.
    ///
    /// - Parameters:
    ///   - model: The model to ensure availability.
    ///   - progressHandler: Optional progress callback.
    /// - Returns: Path to model directory.
    public func ensureModel(
        _ model: Model,
        progressHandler: ProgressHandler? = nil
    ) async throws -> URL {
        if let cached = cachedModelPath(model) {
            progressHandler?(1.0)
            return cached
        }
        return try await downloadModel(model, progressHandler: progressHandler)
    }

    /// Deletes a cached model.
    ///
    /// - Parameter model: The model to delete.
    /// - Throws: File system errors on failure.
    public func deleteModel(_ model: Model) throws {
        let modelDir = modelDirectory(for: model)
        if fileManager.fileExists(atPath: modelDir.path) {
            try fileManager.removeItem(at: modelDir)
        }
    }

    /// Deletes all cached models.
    ///
    /// - Throws: File system errors on failure.
    public func clearCache() throws {
        if fileManager.fileExists(atPath: cacheDirectory.path) {
            try fileManager.removeItem(at: cacheDirectory)
        }
    }

    /// Lists all cached models with their sizes.
    ///
    /// - Returns: Dictionary of model name to size in bytes.
    public func listCachedModels() -> [Model: Int64] {
        var result: [Model: Int64] = [:]

        for model in Model.allCases where isModelCached(model) {
            let modelDir = modelDirectory(for: model)
            if let size = directorySize(modelDir) {
                result[model] = size
            }
        }

        return result
    }

    // MARK: - Private Helpers

    private func modelDirectory(for model: Model) -> URL {
        cacheDirectory.appendingPathComponent(model.rawValue)
    }

    private func performDownload(
        _ model: Model,
        progressHandler: ProgressHandler?
    ) async throws -> URL {
        let modelDir = modelDirectory(for: model)

        // Create directory
        try fileManager.createDirectory(at: modelDir, withIntermediateDirectories: true)

        let totalFiles = model.requiredFiles.count
        var completedFiles = 0

        // Download each required file
        for file in model.requiredFiles {
            let fileURL = huggingFaceURL(for: model, file: file)
            let destinationURL = modelDir.appendingPathComponent(file)

            // Skip if file already exists
            if fileManager.fileExists(atPath: destinationURL.path) {
                completedFiles += 1
                progressHandler?(Double(completedFiles) / Double(totalFiles))
                continue
            }

            do {
                try await downloadFile(
                    from: fileURL,
                    to: destinationURL,
                    fileProgress: { fileProgress in
                        let overallProgress =
                            (Double(completedFiles) + fileProgress) / Double(totalFiles)
                        progressHandler?(overallProgress)
                    }
                )
                completedFiles += 1
            } catch {
                // Clean up partial download
                try? fileManager.removeItem(at: modelDir)
                throw ProviderError.downloadFailed(
                    reason: "Failed to download \(file): \(error.localizedDescription)"
                )
            }
        }

        // Verify download
        guard isModelCached(model) else {
            throw ProviderError.downloadFailed(
                reason: "Model verification failed after download"
            )
        }

        return modelDir
    }

    private func downloadFile(
        from url: URL,
        to destination: URL,
        fileProgress: @escaping (Double) -> Void
    ) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 300 // 5 minutes per file

        // Use download task for large files
        let (tempURL, response) = try await session.download(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.downloadFailed(reason: "Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            throw ProviderError.downloadFailed(
                reason: "HTTP \(httpResponse.statusCode)"
            )
        }

        // Move to final destination
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: tempURL, to: destination)

        fileProgress(1.0)
    }

    private func huggingFaceURL(for model: Model, file: String) -> URL {
        // HuggingFace Hub API format
        // https://huggingface.co/{org}/{repo}/resolve/main/{file}
        let baseURL = "https://huggingface.co/\(model.huggingFaceId)/resolve/main/\(file)"
        return URL(string: baseURL)!
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

extension ModelDownloader {
    /// Human-readable size string.
    public static func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
