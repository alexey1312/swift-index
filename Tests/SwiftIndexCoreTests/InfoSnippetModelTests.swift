import Foundation
@testable import SwiftIndexCore
import Testing

// MARK: - InfoSnippet Model Tests

@Suite("InfoSnippet Model Tests")
struct InfoSnippetModelTests {
    @Test("Initialize InfoSnippet with all fields")
    func initializeWithAllFields() {
        let snippet = InfoSnippet(
            id: "snippet-1",
            path: "/test/README.md",
            content: "# Installation\n\nRun `npm install`.",
            startLine: 1,
            endLine: 3,
            breadcrumb: "README > Installation",
            tokenCount: 15,
            language: "markdown",
            chunkId: "chunk-ref-1",
            kind: .markdownSection,
            fileHash: "hash123"
        )

        #expect(snippet.id == "snippet-1")
        #expect(snippet.path == "/test/README.md")
        #expect(snippet.content == "# Installation\n\nRun `npm install`.")
        #expect(snippet.startLine == 1)
        #expect(snippet.endLine == 3)
        #expect(snippet.breadcrumb == "README > Installation")
        #expect(snippet.tokenCount == 15)
        #expect(snippet.language == "markdown")
        #expect(snippet.chunkId == "chunk-ref-1")
        #expect(snippet.kind == .markdownSection)
    }

    @Test("Initialize InfoSnippet with defaults")
    func initializeWithDefaults() {
        let content = "This is documentation content."
        let snippet = InfoSnippet(
            path: "/test/file.swift",
            content: content,
            startLine: 10,
            endLine: 15,
            fileHash: "hash456"
        )

        #expect(snippet.id.isEmpty == false) // UUID generated
        #expect(snippet.tokenCount == content.count / 4)
        #expect(snippet.language == "swift")
        #expect(snippet.chunkId == nil)
        #expect(snippet.kind == .documentation)
        #expect(snippet.breadcrumb == nil)
    }

    @Test("Language detection from path")
    func languageDetection() {
        let swiftSnippet = InfoSnippet(
            path: "/test/file.swift", content: "doc", startLine: 1, endLine: 1, fileHash: "h"
        )
        let mdSnippet = InfoSnippet(
            path: "/test/README.md", content: "doc", startLine: 1, endLine: 1, fileHash: "h"
        )
        let markdownSnippet = InfoSnippet(
            path: "/test/GUIDE.markdown", content: "doc", startLine: 1, endLine: 1, fileHash: "h"
        )
        let txtSnippet = InfoSnippet(
            path: "/test/notes.txt", content: "doc", startLine: 1, endLine: 1, fileHash: "h"
        )
        let objcSnippet = InfoSnippet(
            path: "/test/ViewController.m", content: "doc", startLine: 1, endLine: 1, fileHash: "h"
        )
        let unknownSnippet = InfoSnippet(
            path: "/test/file.xyz", content: "doc", startLine: 1, endLine: 1, fileHash: "h"
        )

        #expect(swiftSnippet.language == "swift")
        #expect(mdSnippet.language == "markdown")
        #expect(markdownSnippet.language == "markdown")
        #expect(txtSnippet.language == "text")
        #expect(objcSnippet.language == "objective-c")
        #expect(unknownSnippet.language == "unknown")
    }

    @Test("Token count estimation")
    func tokenCountEstimation() {
        let content = String(repeating: "a", count: 100)
        let snippet = InfoSnippet(
            path: "/test/file.md", content: content, startLine: 1, endLine: 5, fileHash: "h"
        )

        #expect(snippet.tokenCount == 25) // 100 / 4 = 25
    }

    @Test("InfoSnippet is Hashable")
    func hashableConformance() {
        let snippet1 = InfoSnippet(
            id: "same-id", path: "/test.md", content: "a", startLine: 1, endLine: 1, fileHash: "h"
        )
        let snippet2 = InfoSnippet(
            id: "same-id", path: "/other.md", content: "b", startLine: 2, endLine: 3, fileHash: "x"
        )
        let snippet3 = InfoSnippet(
            id: "different-id", path: "/test.md", content: "a", startLine: 1, endLine: 1, fileHash: "h"
        )

        var set = Set<InfoSnippet>()
        set.insert(snippet1)
        set.insert(snippet2) // Same ID, should not create new entry
        set.insert(snippet3)

        #expect(set.count == 2)
    }

    @Test("InfoSnippet description format")
    func descriptionFormat() {
        let snippet = InfoSnippet(
            path: "/test/README.md",
            content: "content",
            startLine: 5,
            endLine: 10,
            breadcrumb: "README > Usage",
            kind: .markdownSection,
            fileHash: "h"
        )

        let description = snippet.description
        #expect(description.contains("markdownSection"))
        #expect(description.contains("/test/README.md"))
        #expect(description.contains("5-10"))
        #expect(description.contains("README > Usage"))
    }

    @Test("InfoSnippetKind has all expected cases")
    func snippetKindCases() {
        let allKinds = InfoSnippetKind.allCases

        #expect(allKinds.contains(.documentation))
        #expect(allKinds.contains(.markdownSection))
        #expect(allKinds.contains(.apiDocumentation))
        #expect(allKinds.contains(.example))
        #expect(allKinds.contains(.annotation))
        #expect(allKinds.count == 5)
    }

    @Test("InfoSnippet is Codable")
    func codableConformance() throws {
        let original = InfoSnippet(
            id: "codable-1",
            path: "/test/file.md",
            content: "Documentation content",
            startLine: 1,
            endLine: 5,
            breadcrumb: "Section > Subsection",
            tokenCount: 10,
            language: "markdown",
            chunkId: "parent-chunk-id",
            kind: .markdownSection,
            fileHash: "hash123"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(InfoSnippet.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.path == original.path)
        #expect(decoded.content == original.content)
        #expect(decoded.breadcrumb == original.breadcrumb)
        #expect(decoded.chunkId == original.chunkId)
        #expect(decoded.kind == original.kind)
    }
}
