// MARK: - ModelCacheLocation

import Foundation

/// Resolves the directory that downloaded Hugging Face models are stored in.
///
/// swift-transformers' `HubApi` defaults to `~/Documents/huggingface`. That is a
/// poor home for multi-gigabyte model weights on macOS: with iCloud Drive's
/// "Desktop & Documents Folders" option enabled, everything written there is
/// uploaded to iCloud and counted against the user's storage quota, and files
/// can later be evicted to make space. Model weights are a rebuildable cache,
/// so they belong under `~/.cache`, which is also the location this project's
/// documentation has always described.
///
/// Every download path in SwiftIndex (MLX via `MLXModelLoading`, swift-embeddings
/// via `SwiftEmbeddingsProvider`, and `HubModelManager`) resolves its base here,
/// so a model downloaded by one provider is visible to the cache checks of the
/// others.
public enum ModelCacheLocation {
    /// Base directory for model snapshots, resolved once per process.
    ///
    /// Snapshots land in `<base>/models/<repo id>`, matching the layout
    /// `HubApi` uses.
    public static let base: URL = resolveBase()

    /// Environment variable that overrides the cache directory outright.
    static let overrideVariable = "SWIFTINDEX_MODEL_CACHE"

    /// Computes the configured base directory without touching the filesystem.
    ///
    /// - Parameters:
    ///   - environment: Process environment to read overrides from.
    ///   - homeDirectory: The user's home directory.
    /// - Returns: The directory models should be downloaded into.
    static func configuredBase(
        environment: [String: String],
        homeDirectory: URL
    ) -> URL {
        if let override = environment[overrideVariable], !override.isEmpty {
            return expandingTilde(override, homeDirectory: homeDirectory)
        }
        if let xdgCache = environment["XDG_CACHE_HOME"], !xdgCache.isEmpty {
            return expandingTilde(xdgCache, homeDirectory: homeDirectory)
                .appending(component: "huggingface")
        }
        return homeDirectory
            .appending(component: ".cache")
            .appending(component: "huggingface")
    }

    /// The location `HubApi` uses by default, kept only to migrate away from it.
    static func legacyBase(homeDirectory: URL) -> URL {
        homeDirectory
            .appending(component: "Documents")
            .appending(component: "huggingface")
    }

    // MARK: - Private

    private static func expandingTilde(_ path: String, homeDirectory: URL) -> URL {
        if path == "~" {
            return homeDirectory
        }
        if path.hasPrefix("~/") {
            return homeDirectory.appending(path: String(path.dropFirst(2)))
        }
        return URL(fileURLWithPath: path)
    }

    private static func resolveBase() -> URL {
        let fileManager = FileManager.default
        let target = configuredBase(
            environment: ProcessInfo.processInfo.environment,
            homeDirectory: fileManager.homeDirectoryForCurrentUser
        )

        let legacy = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            .map { $0.appending(component: "huggingface") }

        // Move an existing Documents cache across so upgrading users neither
        // re-download gigabytes nor keep syncing them to iCloud. Skipped when
        // the target already exists: whatever is there wins, and the leftover
        // directory is the user's to delete.
        guard let legacy,
              fileManager.fileExists(atPath: legacy.path),
              !fileManager.fileExists(atPath: target.path)
        else {
            return target
        }

        do {
            try fileManager.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(at: legacy, to: target)
            return target
        } catch {
            // Best effort: an unmovable cache is still a usable cache.
            return legacy
        }
    }
}
