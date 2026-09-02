// MARK: - MLXRuntime

import Foundation

/// Reports whether MLX can actually run on this build.
///
/// MLX needs a compiled Metal library (`default.metallib`). SwiftPM cannot build
/// it, so `scripts/build-mlx-metallib` produces it and release artifacts ship it
/// next to the binary. When it is missing, the first GPU call reaches MLX-C's
/// default error handler, which prints `MLX error: Failed to load the default
/// metallib` and calls `exit(-1)` — the process dies, taking the CLI or the test
/// run with it, with no chance to catch anything in Swift.
///
/// Checking for the library up front turns that hard exit into an ordinary
/// "provider unavailable", so the provider chain falls back to Swift Embeddings.
enum MLXRuntime {
    /// Whether a Metal library MLX can load is present, resolved once per process.
    static let isMetalLibraryAvailable: Bool = locateMetalLibrary() != nil

    /// Path of the Metal library that MLX would load, if any.
    ///
    /// Mirrors the lookup in mlx-swift's `device.cpp`: the directory of the
    /// running binary first, then the SwiftPM resource bundle in any loaded
    /// bundle or framework.
    static func locateMetalLibrary(
        fileManager: FileManager = .default,
        executableURL: URL? = Bundle.main.executableURL,
        bundleURLs: [URL] = defaultBundleURLs()
    ) -> URL? {
        var candidates: [URL] = []

        if let executableDirectory = executableURL?.resolvingSymlinksInPath().deletingLastPathComponent() {
            candidates.append(contentsOf: metalLibraryNames.map { executableDirectory.appending(component: $0) })
        }

        for bundleURL in bundleURLs {
            let resources = bundleURL.appending(component: swiftPMBundleName)
                .appending(component: "Contents")
                .appending(component: "Resources")
            candidates.append(contentsOf: metalLibraryNames.map { resources.appending(component: $0) })
            // Non-macOS-style bundles keep resources at the top level.
            let flatResources = bundleURL.appending(component: swiftPMBundleName)
            candidates.append(contentsOf: metalLibraryNames.map { flatResources.appending(component: $0) })
        }

        return candidates.first { fileManager.fileExists(atPath: $0.path) }
    }

    // MARK: - Private

    /// Library names MLX looks for, in the order it tries them.
    private static let metalLibraryNames = ["default.metallib", "mlx.metallib"]

    /// Resource bundle mlx-swift declares via `SWIFTPM_BUNDLE`.
    private static let swiftPMBundleName = "mlx-swift_Cmlx.bundle"

    /// Bundle directories to search, matching MLX's own bundle walk.
    private static func defaultBundleURLs() -> [URL] {
        var urls: [URL] = [Bundle.main.bundleURL]
        urls.append(contentsOf: Bundle.allBundles.compactMap { $0.resourceURL ?? $0.bundleURL })
        urls.append(contentsOf: Bundle.allFrameworks.compactMap { $0.resourceURL ?? $0.bundleURL })
        return urls
    }
}
