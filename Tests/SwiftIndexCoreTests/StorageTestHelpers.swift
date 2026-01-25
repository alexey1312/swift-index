@testable import SwiftIndexCore

// MARK: - Storage Test Helpers

func makeChunk(
    id: String,
    path: String = "/test/file.swift",
    content: String = "func testFunction() { }",
    startLine: Int = 1,
    endLine: Int = 1,
    kind: ChunkKind = .function,
    symbols: [String] = ["testFunction"],
    references: [String] = [],
    fileHash: String = "testhash123",
    docComment: String? = nil,
    signature: String? = nil,
    breadcrumb: String? = nil,
    language: String = "swift",
    generatedDescription: String? = nil,
    conformances: [String] = [],
    isTypeDeclaration: Bool = false
) -> CodeChunk {
    CodeChunk(
        id: id,
        path: path,
        content: content,
        startLine: startLine,
        endLine: endLine,
        kind: kind,
        symbols: symbols,
        references: references,
        fileHash: fileHash,
        docComment: docComment,
        signature: signature,
        breadcrumb: breadcrumb,
        language: language,
        generatedDescription: generatedDescription,
        conformances: conformances,
        isTypeDeclaration: isTypeDeclaration
    )
}

func makeSnippet(
    id: String,
    path: String = "/test/README.md",
    content: String = "## Documentation\n\nThis is documentation content.",
    startLine: Int = 1,
    endLine: Int = 3,
    breadcrumb: String? = nil,
    chunkId: String? = nil,
    kind: InfoSnippetKind = .markdownSection,
    fileHash: String = "testhash123"
) -> InfoSnippet {
    InfoSnippet(
        id: id,
        path: path,
        content: content,
        startLine: startLine,
        endLine: endLine,
        breadcrumb: breadcrumb,
        chunkId: chunkId,
        kind: kind,
        fileHash: fileHash
    )
}
