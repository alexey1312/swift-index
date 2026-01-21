import Testing
@testable import SwiftIndexCore

@Suite("SwiftIndexCore Tests")
struct SwiftIndexCoreTests {
    @Test("CodeChunk creation")
    func testCodeChunkCreation() {
        let chunk = CodeChunk(
            path: "/test/file.swift",
            content: "func hello() {}",
            startLine: 1,
            endLine: 1,
            kind: .function,
            symbols: ["hello"],
            fileHash: "abc123"
        )

        #expect(chunk.path == "/test/file.swift")
        #expect(chunk.kind == .function)
        #expect(chunk.symbols == ["hello"])
    }

    @Test("ChunkKind properties")
    func testChunkKindProperties() {
        #expect(ChunkKind.function.isSwift)
        #expect(ChunkKind.objcMethod.isObjC)
        #expect(ChunkKind.cFunction.isC)
        #expect(ChunkKind.class.isTypeDeclaration)
        #expect(ChunkKind.method.isCallable)
    }

    @Test("Config default values")
    func testConfigDefaults() {
        let config = Config.default

        #expect(config.embeddingProvider == "auto")
        #expect(config.semanticWeight == 0.7)
        #expect(config.rrfK == 60)
        #expect(config.chunkSize == 1500)
    }

    @Test("Config merge priority")
    func testConfigMergePriority() {
        let low = PartialConfig(semanticWeight: 0.5)
        let high = PartialConfig(semanticWeight: 0.9)

        // High priority first in array
        let merged = Config.merge([high, low])

        #expect(merged.semanticWeight == 0.9)
    }

    @Test("SearchOptions defaults")
    func testSearchOptionsDefaults() {
        let options = SearchOptions.default

        #expect(options.limit == 20)
        #expect(options.semanticWeight == 0.7)
        #expect(options.rrfK == 60)
        #expect(options.multiHop == false)
    }
}
