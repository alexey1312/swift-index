import Foundation
@testable import SwiftIndexCore
import Testing

@Suite("TOMLConfigLoader Tests")
struct TOMLConfigLoaderTests {
    // MARK: - Test Fixtures

    /// Creates a temporary TOML file with the given contents.
    private func createTempTOMLFile(contents: String) throws -> String {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "test-config-\(UUID().uuidString).toml"
        let filePath = tempDir.appendingPathComponent(fileName).path

        try contents.write(toFile: filePath, atomically: true, encoding: .utf8)
        return filePath
    }

    /// Removes a temporary file.
    private func removeTempFile(at path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - File Not Found Tests

    @Test("Throws fileNotFound for missing file")
    func testFileNotFound() throws {
        let loader = TOMLConfigLoader(filePath: "/nonexistent/path/.swiftindex.toml")

        #expect(throws: ConfigError.fileNotFound("/nonexistent/path/.swiftindex.toml")) {
            try loader.load()
        }
    }

    // MARK: - Invalid Syntax Tests

    @Test("Throws invalidSyntax for malformed TOML")
    func invalidSyntax() throws {
        let contents = """
        [embedding
        provider = "mlx"
        """

        let filePath = try createTempTOMLFile(contents: contents)
        defer { removeTempFile(at: filePath) }

        let loader = TOMLConfigLoader(filePath: filePath)

        #expect(throws: ConfigError.self) {
            try loader.load()
        }
    }

    // MARK: - Empty File Tests

    @Test("Returns empty config for empty file")
    func emptyFile() throws {
        let filePath = try createTempTOMLFile(contents: "")
        defer { removeTempFile(at: filePath) }

        let loader = TOMLConfigLoader(filePath: filePath)
        let config = try loader.load()

        #expect(config == PartialConfig.empty)
    }

    // MARK: - Embedding Section Tests

    @Test("Parses embedding section")
    func embeddingSection() throws {
        let contents = """
        [embedding]
        provider = "mlx"
        model = "all-MiniLM-L6-v2"
        dimension = 384
        """

        let filePath = try createTempTOMLFile(contents: contents)
        defer { removeTempFile(at: filePath) }

        let loader = TOMLConfigLoader(filePath: filePath)
        let config = try loader.load()

        #expect(config.embeddingProvider == "mlx")
        #expect(config.embeddingModel == "all-MiniLM-L6-v2")
        #expect(config.embeddingDimension == 384)
    }

    @Test("Parses partial embedding section")
    func partialEmbeddingSection() throws {
        let contents = """
        [embedding]
        provider = "voyage"
        """

        let filePath = try createTempTOMLFile(contents: contents)
        defer { removeTempFile(at: filePath) }

        let loader = TOMLConfigLoader(filePath: filePath)
        let config = try loader.load()

        #expect(config.embeddingProvider == "voyage")
        #expect(config.embeddingModel == nil)
        #expect(config.embeddingDimension == nil)
    }

    // MARK: - Search Section Tests

    @Test("Parses search section")
    func searchSection() throws {
        let contents = """
        [search]
        semantic_weight = 0.8
        rrf_k = 100
        multi_hop_enabled = true
        multi_hop_depth = 3
        """

        let filePath = try createTempTOMLFile(contents: contents)
        defer { removeTempFile(at: filePath) }

        let loader = TOMLConfigLoader(filePath: filePath)
        let config = try loader.load()

        #expect(config.semanticWeight == 0.8)
        #expect(config.rrfK == 100)
        #expect(config.multiHopEnabled == true)
        #expect(config.multiHopDepth == 3)
    }

    @Test("Accepts integer as semantic_weight")
    func integerSemanticWeight() throws {
        let contents = """
        [search]
        semantic_weight = 1
        """

        let filePath = try createTempTOMLFile(contents: contents)
        defer { removeTempFile(at: filePath) }

        let loader = TOMLConfigLoader(filePath: filePath)
        let config = try loader.load()

        #expect(config.semanticWeight == 1.0)
    }

    // MARK: - Indexing Section Tests

    @Test("Parses indexing section with arrays")
    func indexingSection() throws {
        let contents = """
        [indexing]
        exclude = [".git", ".build", "DerivedData"]
        include_extensions = [".swift", ".m", ".h"]
        max_file_size = 2000000
        chunk_size = 2000
        chunk_overlap = 300
        """

        let filePath = try createTempTOMLFile(contents: contents)
        defer { removeTempFile(at: filePath) }

        let loader = TOMLConfigLoader(filePath: filePath)
        let config = try loader.load()

        #expect(config.excludePatterns == [".git", ".build", "DerivedData"])
        #expect(config.includeExtensions == [".swift", ".m", ".h"])
        #expect(config.maxFileSize == 2_000_000)
        #expect(config.chunkSize == 2000)
        #expect(config.chunkOverlap == 300)
    }

    @Test("Handles empty arrays")
    func emptyArrays() throws {
        let contents = """
        [indexing]
        exclude = []
        include_extensions = []
        """

        let filePath = try createTempTOMLFile(contents: contents)
        defer { removeTempFile(at: filePath) }

        let loader = TOMLConfigLoader(filePath: filePath)
        let config = try loader.load()

        #expect(config.excludePatterns == [])
        #expect(config.includeExtensions == [])
    }

    // MARK: - Storage Section Tests

    @Test("Parses storage section")
    func storageSection() throws {
        let contents = """
        [storage]
        index_path = ".custom-index"
        cache_path = "/tmp/swiftindex-cache"
        """

        let filePath = try createTempTOMLFile(contents: contents)
        defer { removeTempFile(at: filePath) }

        let loader = TOMLConfigLoader(filePath: filePath)
        let config = try loader.load()

        #expect(config.indexPath == ".custom-index")
        #expect(config.cachePath == "/tmp/swiftindex-cache")
    }

    // MARK: - API Keys Section Tests

    @Test("Parses api_keys section")
    func aPIKeysSection() throws {
        let contents = """
        [api_keys]
        voyage = "voyage-api-key-123"
        openai = "sk-openai-key-456"
        """

        let filePath = try createTempTOMLFile(contents: contents)
        defer { removeTempFile(at: filePath) }

        let loader = TOMLConfigLoader(filePath: filePath)
        let config = try loader.load()

        #expect(config.voyageAPIKey == "voyage-api-key-123")
        #expect(config.openAIAPIKey == "sk-openai-key-456")
    }

    // MARK: - Watch Section Tests

    @Test("Parses watch section")
    func watchSection() throws {
        let contents = """
        [watch]
        debounce_ms = 1000
        """

        let filePath = try createTempTOMLFile(contents: contents)
        defer { removeTempFile(at: filePath) }

        let loader = TOMLConfigLoader(filePath: filePath)
        let config = try loader.load()

        #expect(config.watchDebounceMs == 1000)
    }

    // MARK: - Logging Section Tests

    @Test("Parses logging section")
    func loggingSection() throws {
        let contents = """
        [logging]
        level = "debug"
        """

        let filePath = try createTempTOMLFile(contents: contents)
        defer { removeTempFile(at: filePath) }

        let loader = TOMLConfigLoader(filePath: filePath)
        let config = try loader.load()

        #expect(config.logLevel == "debug")
    }

    // MARK: - Complete Configuration Tests

    @Test("Parses complete configuration")
    func completeConfiguration() throws {
        let contents = """
        [embedding]
        provider = "mlx"
        model = "all-MiniLM-L6-v2"
        dimension = 384

        [search]
        semantic_weight = 0.7
        rrf_k = 60
        multi_hop_enabled = false
        multi_hop_depth = 2

        [indexing]
        exclude = [".git", ".build"]
        include_extensions = [".swift"]
        max_file_size = 1000000
        chunk_size = 1500
        chunk_overlap = 200

        [storage]
        index_path = ".swiftindex"
        cache_path = "~/.cache/swiftindex"

        [api_keys]
        voyage = "test-voyage-key"
        openai = "test-openai-key"

        [watch]
        debounce_ms = 500

        [logging]
        level = "info"
        """

        let filePath = try createTempTOMLFile(contents: contents)
        defer { removeTempFile(at: filePath) }

        let loader = TOMLConfigLoader(filePath: filePath)
        let config = try loader.load()

        // Verify all fields are populated
        #expect(config.embeddingProvider == "mlx")
        #expect(config.embeddingModel == "all-MiniLM-L6-v2")
        #expect(config.embeddingDimension == 384)
        #expect(config.semanticWeight == 0.7)
        #expect(config.rrfK == 60)
        #expect(config.multiHopEnabled == false)
        #expect(config.multiHopDepth == 2)
        #expect(config.excludePatterns == [".git", ".build"])
        #expect(config.includeExtensions == [".swift"])
        #expect(config.maxFileSize == 1_000_000)
        #expect(config.chunkSize == 1500)
        #expect(config.chunkOverlap == 200)
        #expect(config.indexPath == ".swiftindex")
        #expect(config.cachePath == "~/.cache/swiftindex")
        #expect(config.voyageAPIKey == "test-voyage-key")
        #expect(config.openAIAPIKey == "test-openai-key")
        #expect(config.watchDebounceMs == 500)
        #expect(config.logLevel == "info")
    }

    // MARK: - Type Validation Tests

    @Test("Throws invalidValue for wrong type in embedding.provider")
    func invalidTypeEmbeddingProvider() throws {
        let contents = """
        [embedding]
        provider = 123
        """

        let filePath = try createTempTOMLFile(contents: contents)
        defer { removeTempFile(at: filePath) }

        let loader = TOMLConfigLoader(filePath: filePath)

        #expect(throws: ConfigError.self) {
            try loader.load()
        }
    }

    @Test("Throws invalidValue for wrong type in search.rrf_k")
    func invalidTypeRRFK() throws {
        let contents = """
        [search]
        rrf_k = "sixty"
        """

        let filePath = try createTempTOMLFile(contents: contents)
        defer { removeTempFile(at: filePath) }

        let loader = TOMLConfigLoader(filePath: filePath)

        #expect(throws: ConfigError.self) {
            try loader.load()
        }
    }

    @Test("Throws invalidValue for wrong type in array element")
    func invalidTypeArrayElement() throws {
        let contents = """
        [indexing]
        exclude = [".git", 123, ".build"]
        """

        let filePath = try createTempTOMLFile(contents: contents)
        defer { removeTempFile(at: filePath) }

        let loader = TOMLConfigLoader(filePath: filePath)

        #expect(throws: ConfigError.self) {
            try loader.load()
        }
    }

    @Test("Throws invalidValue for wrong type in boolean field")
    func invalidTypeBooleanField() throws {
        let contents = """
        [search]
        multi_hop_enabled = "yes"
        """

        let filePath = try createTempTOMLFile(contents: contents)
        defer { removeTempFile(at: filePath) }

        let loader = TOMLConfigLoader(filePath: filePath)

        #expect(throws: ConfigError.self) {
            try loader.load()
        }
    }

    // MARK: - Factory Method Tests

    @Test("forProject creates correct path")
    func forProjectPath() {
        let loader = TOMLConfigLoader.forProject(at: "/path/to/project")

        #expect(loader.filePath == "/path/to/project/.swiftindex.toml")
    }

    @Test("forGlobal creates path in home directory")
    func forGlobalPath() {
        let loader = TOMLConfigLoader.forGlobal()
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path

        #expect(loader.filePath == "\(homeDir)/.swiftindex.toml")
    }

    // MARK: - Layered Configuration Tests

    @Test("loadLayered merges configs with correct priority")
    func loadLayeredPriority() throws {
        // Create a project TOML with some values
        let projectContents = """
        [embedding]
        provider = "mlx"

        [search]
        semantic_weight = 0.5
        """

        let tempDir = FileManager.default.temporaryDirectory
        let projectDir = tempDir.appendingPathComponent("test-project-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: projectDir) }

        let configPath = projectDir.appendingPathComponent(".swiftindex.toml")
        try projectContents.write(to: configPath, atomically: true, encoding: .utf8)

        // CLI config should override project config
        let cliConfig = PartialConfig(semanticWeight: 0.9)

        let merged = TOMLConfigLoader.loadLayered(
            cli: cliConfig,
            projectDirectory: projectDir.path
        )

        // CLI takes precedence over project
        #expect(merged.semanticWeight == 0.9)
        // Project value is used when CLI doesn't specify
        #expect(merged.embeddingProvider == "mlx")
        // Default is used when neither specifies
        #expect(merged.chunkSize == 1500)
    }

    @Test("loadLayered handles missing project config")
    func loadLayeredMissingProjectConfig() {
        let cliConfig = PartialConfig(embeddingProvider: "voyage")

        let merged = TOMLConfigLoader.loadLayered(
            cli: cliConfig,
            projectDirectory: "/nonexistent/path"
        )

        #expect(merged.embeddingProvider == "voyage")
        // Falls back to defaults for everything else
        #expect(merged.semanticWeight == 0.7)
    }

    @Test("loadLayered uses defaults for empty configs")
    func loadLayeredDefaults() {
        let merged = TOMLConfigLoader.loadLayered(projectDirectory: "/nonexistent/path")

        // Should match Config.default
        let defaults = Config.default
        #expect(merged.embeddingProvider == defaults.embeddingProvider)
        #expect(merged.semanticWeight == defaults.semanticWeight)
        #expect(merged.rrfK == defaults.rrfK)
        #expect(merged.chunkSize == defaults.chunkSize)
    }

    // MARK: - Edge Cases

    @Test("Handles comments in TOML")
    func commentsInTOML() throws {
        let contents = """
        # This is a comment
        [embedding]
        provider = "mlx"  # inline comment
        # Another comment
        model = "all-MiniLM-L6-v2"
        """

        let filePath = try createTempTOMLFile(contents: contents)
        defer { removeTempFile(at: filePath) }

        let loader = TOMLConfigLoader(filePath: filePath)
        let config = try loader.load()

        #expect(config.embeddingProvider == "mlx")
        #expect(config.embeddingModel == "all-MiniLM-L6-v2")
    }

    @Test("Handles quoted strings with special characters")
    func quotedStringsWithSpecialChars() throws {
        let contents = """
        [storage]
        index_path = ".swift-index/v1"
        cache_path = "/Users/test/Library/Caches/swift index"
        """

        let filePath = try createTempTOMLFile(contents: contents)
        defer { removeTempFile(at: filePath) }

        let loader = TOMLConfigLoader(filePath: filePath)
        let config = try loader.load()

        #expect(config.indexPath == ".swift-index/v1")
        #expect(config.cachePath == "/Users/test/Library/Caches/swift index")
    }

    @Test("Handles unknown sections gracefully")
    func unknownSectionsIgnored() throws {
        let contents = """
        [embedding]
        provider = "mlx"

        [unknown_section]
        some_key = "some_value"

        [another_unknown]
        foo = 123
        """

        let filePath = try createTempTOMLFile(contents: contents)
        defer { removeTempFile(at: filePath) }

        let loader = TOMLConfigLoader(filePath: filePath)
        let config = try loader.load()

        // Should parse known section and ignore unknown ones
        #expect(config.embeddingProvider == "mlx")
    }

    @Test("Handles unknown keys within known sections")
    func unknownKeysIgnored() throws {
        let contents = """
        [embedding]
        provider = "mlx"
        unknown_key = "unknown_value"
        another_unknown = 42
        """

        let filePath = try createTempTOMLFile(contents: contents)
        defer { removeTempFile(at: filePath) }

        let loader = TOMLConfigLoader(filePath: filePath)
        let config = try loader.load()

        // Should parse known keys and ignore unknown ones
        #expect(config.embeddingProvider == "mlx")
    }
}
