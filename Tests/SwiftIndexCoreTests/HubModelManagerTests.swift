// MARK: - HubModelManagerTests

import Foundation
@testable import SwiftIndexCore
import Testing

// MARK: - HubModelManager.Model Tests

@Suite("HubModelManager.Model Tests")
struct HubModelManagerModelTests {
    @Test("Model enum has correct dimensions")
    func modelDimensions() {
        #expect(HubModelManager.Model.bgeSmall.dimension == 384)
        #expect(HubModelManager.Model.bgeBase.dimension == 768)
        #expect(HubModelManager.Model.miniLM.dimension == 384)
    }

    @Test("Model enum has correct HuggingFace IDs")
    func modelHuggingFaceIds() {
        #expect(HubModelManager.Model.bgeSmall.huggingFaceId == "BAAI/bge-small-en-v1.5")
        #expect(HubModelManager.Model.bgeBase.huggingFaceId == "BAAI/bge-base-en-v1.5")
        #expect(HubModelManager.Model.miniLM.huggingFaceId == "sentence-transformers/all-MiniLM-L6-v2")
    }

    @Test("Model enum has required files")
    func modelRequiredFiles() {
        let files = HubModelManager.Model.bgeSmall.requiredFiles

        #expect(files.contains("config.json"))
        #expect(files.contains("tokenizer.json"))
        #expect(files.contains("tokenizer_config.json"))
        #expect(files.contains("*.safetensors"))
    }

    @Test("All models are iterable")
    func allModelsCaseIterable() {
        let allModels = HubModelManager.Model.allCases
        #expect(allModels.count == 3)
    }

    @Test("Model approximate sizes are reasonable")
    func modelApproximateSizes() {
        // All models should have positive sizes
        for model in HubModelManager.Model.allCases {
            #expect(model.approximateSize > 0)
        }

        // bge-base should be larger than bge-small
        #expect(HubModelManager.Model.bgeBase.approximateSize > HubModelManager.Model.bgeSmall.approximateSize)
    }
}

// MARK: - HubModelManager Tests

@Suite("HubModelManager Tests")
struct HubModelManagerTests {
    @Test("Manager initializes correctly")
    func managerInitialization() async {
        let manager = HubModelManager()

        // Manager should be created without errors
        let cachedModels = await manager.listCachedModels()
        #expect(cachedModels.isEmpty || cachedModels.count <= HubModelManager.Model.allCases.count)
    }

    @Test("isModelCached returns false for non-cached models")
    func isModelCachedReturnsFalse() async {
        // Create manager with a custom empty cache directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftIndexTest-\(UUID().uuidString)")

        let manager = HubModelManager(cacheDirectory: tempDir)

        // Model should not be cached in empty directory
        let isCached = await manager.isModelCached(.bgeSmall)
        #expect(isCached == false)

        // Clean up
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("cachedModelPath returns nil for non-cached models")
    func cachedModelPathReturnsNil() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftIndexTest-\(UUID().uuidString)")

        let manager = HubModelManager(cacheDirectory: tempDir)

        let path = await manager.cachedModelPath(.bgeSmall)
        #expect(path == nil)

        // Clean up
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("formatSize produces human-readable output")
    func formatSizeOutput() {
        let kb = HubModelManager.formatSize(1024)
        let mb = HubModelManager.formatSize(1024 * 1024)
        let gb = HubModelManager.formatSize(1024 * 1024 * 1024)

        #expect(kb.contains("KB") || kb.contains("kB"))
        #expect(mb.contains("MB"))
        #expect(gb.contains("GB"))
    }

    @Test("listCachedModels returns empty for fresh cache")
    func listCachedModelsEmpty() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftIndexTest-\(UUID().uuidString)")

        let manager = HubModelManager(cacheDirectory: tempDir)

        let cached = await manager.listCachedModels()
        #expect(cached.isEmpty)

        // Clean up
        try? FileManager.default.removeItem(at: tempDir)
    }
}

// MARK: - Integration Tests (require network)

@Suite("HubModelManager Integration Tests", .disabled("Requires network access and model download"))
struct HubModelManagerIntegrationTests {
    @Test("Can download and cache a model")
    func downloadModel() async throws {
        let manager = HubModelManager()

        let modelPath = try await manager.ensureModel(.bgeSmall, progress: nil)

        // Model path should exist
        #expect(FileManager.default.fileExists(atPath: modelPath.path))
    }

    @Test("Can load tokenizer for downloaded model")
    func loadTokenizer() async throws {
        let manager = HubModelManager()

        // Ensure model is downloaded first
        _ = try await manager.ensureModel(.bgeSmall, progress: nil)

        // Load tokenizer
        let tokenizer = try await manager.loadTokenizer(for: .bgeSmall)

        // Tokenizer should encode text
        let tokens = tokenizer.encode(text: "Hello, world!")
        #expect(!tokens.isEmpty)
    }

    @Test("Cached model is returned immediately")
    func cachedModelReturnsImmediately() async throws {
        let manager = HubModelManager()

        // First call downloads the model
        _ = try await manager.ensureModel(.bgeSmall, progress: nil)

        // Second call should return cached model quickly
        _ = try await manager.ensureModel(.bgeSmall, progress: nil)
    }
}
