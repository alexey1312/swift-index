// MARK: - MLXRuntimeTests

import Foundation
@testable import SwiftIndexCore
import Testing

@Suite("MLXRuntime")
struct MLXRuntimeTests {
    @Test("No Metal library found in an empty build directory")
    func missingMetalLibrary() throws {
        let root = try TemporaryDirectory()
        let executable = root.url.appending(component: "swiftindex")

        let found = MLXRuntime.locateMetalLibrary(
            executableURL: executable,
            bundleURLs: [root.url]
        )

        #expect(found == nil)
    }

    @Test("Ignores a bare default.metallib next to the binary, which MLX does not load")
    func ignoresColocatedDefaultLibrary() throws {
        let root = try TemporaryDirectory()
        let executable = root.url.appending(component: "swiftindex")
        let library = root.url.appending(component: "default.metallib")
        try Data().write(to: library)

        let found = MLXRuntime.locateMetalLibrary(
            executableURL: executable,
            bundleURLs: []
        )

        #expect(found == nil)
    }

    @Test("Finds mlx.metallib next to the binary")
    func findsAlternateName() throws {
        let root = try TemporaryDirectory()
        let executable = root.url.appending(component: "swiftindex")
        try Data().write(to: root.url.appending(component: "mlx.metallib"))

        let found = MLXRuntime.locateMetalLibrary(
            executableURL: executable,
            bundleURLs: []
        )

        #expect(found?.lastPathComponent == "mlx.metallib")
    }

    @Test("Finds a Metal library in the SwiftPM resource bundle")
    func findsBundledMetalLibrary() throws {
        let root = try TemporaryDirectory()
        let resources = root.url
            .appending(component: "mlx-swift_Cmlx.bundle")
            .appending(component: "Contents")
            .appending(component: "Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try Data().write(to: resources.appending(component: "default.metallib"))

        let found = MLXRuntime.locateMetalLibrary(
            executableURL: root.url.appending(component: "elsewhere/swiftindex"),
            bundleURLs: [root.url]
        )

        #expect(found?.path.contains("mlx-swift_Cmlx.bundle") == true)
    }
}

// MARK: - TemporaryDirectory

/// A directory that removes itself when the test finishes with it.
private struct TemporaryDirectory: ~Copyable {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(component: "swiftindex-mlxruntime-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

@Suite("MLXEmbeddingProvider token limit")
struct MLXTokenLimitTests {
    @Test("A short input stays unchanged")
    func shortInput() {
        #expect(MLXEmbeddingProvider.truncated([1, 2, 3], to: 4) == [1, 2, 3])
    }

    @Test("A long input keeps the limit and its final token")
    func longInput() {
        let tokens = Array(0 ..< 10000)
        let result = MLXEmbeddingProvider.truncated(tokens)
        #expect(result.count == MLXEmbeddingProvider.maxTokens)
        #expect(result.last == 9999)
        #expect(Array(result.prefix(3)) == [0, 1, 2])
    }
}
