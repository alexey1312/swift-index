import Foundation
@testable import SwiftIndexCore
import Testing

// MARK: - TreeSitterParser Tests

@Suite("TreeSitterParser Tests")
struct TreeSitterParserTests {
    // MARK: - C Function Tests

    @Test("Parse C function declaration")
    func parseCFunction() {
        let parser = TreeSitterParser()
        let content = """
        int calculateSum(int a, int b) {
            return a + b;
        }
        """

        let result = parser.parse(content: content, path: "helpers.c")

        guard case let .success(chunks) = result else {
            Issue.record("Expected successful parse")
            return
        }

        #expect(!chunks.isEmpty)
        #expect(chunks.contains { $0.content.contains("calculateSum") })
    }

    @Test("Parse C struct definition")
    func parseCStruct() {
        let parser = TreeSitterParser()
        let content = """
        struct Point {
            int x;
            int y;
        };
        """

        let result = parser.parse(content: content, path: "types.c")

        guard case let .success(chunks) = result else {
            Issue.record("Expected successful parse")
            return
        }

        #expect(!chunks.isEmpty)
        #expect(chunks.contains { $0.content.contains("Point") })
    }

    // MARK: - JSON Tests

    @Test("Parse JSON object")
    func parseJSONObject() {
        let parser = TreeSitterParser()
        let content = """
        {
            "name": "swift-index",
            "version": "1.0.0",
            "dependencies": {
                "swift-syntax": "600.0.0"
            }
        }
        """

        let result = parser.parse(content: content, path: "package.json")

        guard case let .success(chunks) = result else {
            Issue.record("Expected successful parse")
            return
        }

        #expect(!chunks.isEmpty)
        #expect(chunks.first?.kind == .document)
    }

    @Test("Parse JSON array")
    func parseJSONArray() {
        let parser = TreeSitterParser()
        let content = """
        [
            {"id": 1, "name": "item1"},
            {"id": 2, "name": "item2"}
        ]
        """

        let result = parser.parse(content: content, path: "items.json")

        guard case let .success(chunks) = result else {
            Issue.record("Expected successful parse")
            return
        }

        #expect(!chunks.isEmpty)
    }

    // MARK: - YAML Tests

    @Test("Parse YAML mapping")
    func parseYAMLMapping() {
        let parser = TreeSitterParser()
        let content = """
        name: SwiftIndex
        version: 1.0.0
        settings:
          debug: true
          timeout: 30
        """

        let result = parser.parse(content: content, path: "config.yaml")

        guard case let .success(chunks) = result else {
            Issue.record("Expected successful parse")
            return
        }

        #expect(!chunks.isEmpty)
        #expect(chunks.first?.kind == .document)
    }

    @Test("Parse YAML sequence")
    func parseYAMLSequence() {
        let parser = TreeSitterParser()
        let content = """
        - item1
        - item2
        - nested:
            key: value
        """

        let result = parser.parse(content: content, path: "list.yml")

        guard case let .success(chunks) = result else {
            Issue.record("Expected successful parse")
            return
        }

        #expect(!chunks.isEmpty)
    }

    // MARK: - Markdown Tests

    @Test("Parse Markdown sections")
    func parseMarkdownSection() {
        let parser = TreeSitterParser()
        let content = """
        # Introduction

        This is the introduction section.

        ## Getting Started

        Here's how to get started.

        ### Installation

        Run the following command.
        """

        let result = parser.parse(content: content, path: "README.md")
        let chunks = result.chunks

        #expect(!chunks.isEmpty)
        // Should have chunks for different sections
        #expect(chunks.contains { $0.content.contains("Introduction") })
    }

    @Test("Parse Markdown code block")
    func parseMarkdownCodeBlock() {
        let parser = TreeSitterParser()
        let content = """
        # Example

        ```swift
        let x = 42
        print(x)
        ```

        Some text after code.
        """

        let result = parser.parse(content: content, path: "example.md")
        let chunks = result.chunks

        #expect(!chunks.isEmpty)
    }

    @Test("Extract InfoSnippets from Markdown")
    func extractMarkdownInfoSnippets() {
        let parser = TreeSitterParser()
        let content = """
        # Getting Started

        Welcome to the documentation.

        ## Installation

        Install via Homebrew.

        ## Usage

        Run the command.
        """

        let result = parser.parse(content: content, path: "README.md")
        let snippets = result.snippets

        #expect(!snippets.isEmpty)
        #expect(snippets.count >= 3) // 3 sections

        // Verify snippet properties
        let installSnippet = snippets.first { $0.content.contains("Installation") }
        #expect(installSnippet != nil)
        #expect(installSnippet?.kind == .markdownSection)
        #expect(installSnippet?.language == "markdown")
        #expect(installSnippet?.breadcrumb == "Getting Started > Installation")
    }

    @Test("InfoSnippets have correct chunkId linkage")
    func infoSnippetChunkIdLinkage() {
        let parser = TreeSitterParser()
        let content = """
        # Documentation

        Some content here.
        """

        let result = parser.parse(content: content, path: "doc.md")
        let chunks = result.chunks
        let snippets = result.snippets

        #expect(chunks.count == snippets.count)

        // Each snippet should link to its corresponding chunk
        for snippet in snippets {
            let matchingChunk = chunks.first { $0.id == snippet.chunkId }
            #expect(matchingChunk != nil)
            #expect(matchingChunk?.startLine == snippet.startLine)
            #expect(matchingChunk?.endLine == snippet.endLine)
        }
    }

    // MARK: - Objective-C Tests

    @Test("Parse Objective-C interface")
    func parseObjCInterface() {
        let parser = TreeSitterParser()
        let content = """
        @interface MyClass : NSObject

        @property (nonatomic, strong) NSString *name;

        - (void)doSomething;

        @end
        """

        let result = parser.parse(content: content, path: "MyClass.h")

        guard case let .success(chunks) = result else {
            Issue.record("Expected successful parse")
            return
        }

        #expect(!chunks.isEmpty)
        #expect(chunks.contains { $0.content.contains("MyClass") })
    }

    @Test("Parse Objective-C implementation")
    func parseObjCImplementation() {
        let parser = TreeSitterParser()
        let content = """
        @implementation MyClass

        - (void)doSomething {
            NSLog(@"Doing something");
        }

        @end
        """

        let result = parser.parse(content: content, path: "MyClass.m")

        guard case let .success(chunks) = result else {
            Issue.record("Expected successful parse")
            return
        }

        #expect(!chunks.isEmpty)
    }

    @Test("Parse Objective-C method definition")
    func parseObjCMethodDefinition() {
        let parser = TreeSitterParser()
        let content = """
        @implementation Calculator

        - (int)addA:(int)a toB:(int)b {
            return a + b;
        }

        + (instancetype)sharedInstance {
            static Calculator *instance = nil;
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                instance = [[Calculator alloc] init];
            });
            return instance;
        }

        @end
        """

        let result = parser.parse(content: content, path: "Calculator.m")

        guard case let .success(chunks) = result else {
            Issue.record("Expected successful parse")
            return
        }

        #expect(!chunks.isEmpty)
        #expect(chunks.contains { $0.content.contains("addA") || $0.content.contains("sharedInstance") })
    }

    // MARK: - Edge Cases

    @Test("Handle empty content")
    func testEmptyContent() {
        let parser = TreeSitterParser()
        let result = parser.parse(content: "", path: "empty.c")

        guard case let .failure(error) = result else {
            Issue.record("Expected failure for empty content")
            return
        }

        #expect(error == .emptyContent)
    }

    @Test("Handle whitespace-only content")
    func whitespaceOnlyContent() {
        let parser = TreeSitterParser()
        let result = parser.parse(content: "   \n\n  \t  ", path: "whitespace.c")

        guard case let .failure(error) = result else {
            Issue.record("Expected failure for whitespace-only content")
            return
        }

        #expect(error == .emptyContent)
    }

    // MARK: - Rich Metadata Tests

    @Test("Detect C language")
    func detectCLanguage() {
        let parser = TreeSitterParser()
        let content = """
        int main() {
            return 0;
        }
        """

        let result = parser.parse(content: content, path: "main.c")
        guard case let .success(chunks) = result else {
            Issue.record("Expected successful parse")
            return
        }

        #expect(chunks.first?.language == "c")
    }

    @Test("Detect Objective-C language")
    func detectObjectiveCLanguage() {
        let parser = TreeSitterParser()
        let content = """
        @implementation Test
        @end
        """

        let result = parser.parse(content: content, path: "Test.m")
        guard case let .success(chunks) = result else {
            Issue.record("Expected successful parse")
            return
        }

        #expect(chunks.first?.language == "objective-c")
    }

    @Test("Detect JSON language")
    func detectJSONLanguage() {
        let parser = TreeSitterParser()
        let content = """
        {"key": "value"}
        """

        let result = parser.parse(content: content, path: "config.json")
        guard case let .success(chunks) = result else {
            Issue.record("Expected successful parse")
            return
        }

        #expect(chunks.first?.language == "json")
    }

    @Test("Detect YAML language")
    func detectYAMLLanguage() {
        let parser = TreeSitterParser()
        let content = """
        key: value
        """

        let result = parser.parse(content: content, path: "config.yaml")
        guard case let .success(chunks) = result else {
            Issue.record("Expected successful parse")
            return
        }

        #expect(chunks.first?.language == "yaml")
    }

    @Test("Detect Markdown language")
    func detectMarkdownLanguage() {
        let parser = TreeSitterParser()
        let content = """
        # Title
        Some content.
        """

        let result = parser.parse(content: content, path: "README.md")
        let chunks = result.chunks

        #expect(chunks.first?.language == "markdown")
    }

    @Test("Build breadcrumb for Markdown sections")
    func buildMarkdownBreadcrumb() {
        let parser = TreeSitterParser()
        let content = """
        # Getting Started

        Introduction text.

        ## Installation

        Install instructions.

        ### Prerequisites

        Requirements list.
        """

        let result = parser.parse(content: content, path: "README.md")
        let chunks = result.chunks

        // First section should have breadcrumb
        let gettingStarted = chunks.first { $0.symbols.contains("Getting Started") }
        #expect(gettingStarted?.breadcrumb == "Getting Started")

        // Nested section should have hierarchical breadcrumb
        let installation = chunks.first { $0.symbols.contains("Installation") }
        #expect(installation?.breadcrumb == "Getting Started > Installation")

        let prereqs = chunks.first { $0.symbols.contains("Prerequisites") }
        #expect(prereqs?.breadcrumb == "Getting Started > Installation > Prerequisites")
    }

    @Test("Calculate token count")
    func calculateTokenCount() {
        let parser = TreeSitterParser()
        let content = """
        # Title

        This is some content that should have tokens calculated.
        """

        let result = parser.parse(content: content, path: "test.md")
        let chunks = result.chunks

        let chunk = chunks.first
        #expect(chunk != nil)
        #expect(chunk?.tokenCount ?? 0 > 0)
        // Token count is approximately content.count / 4
        let expectedApprox = chunk!.content.count / 4
        #expect(abs(chunk!.tokenCount - expectedApprox) <= 1)
    }

    @Test("Extract C function signature")
    func extractCFunctionSignature() {
        let parser = TreeSitterParser()
        let content = """
        // Calculate the sum of two integers
        int calculateSum(int a, int b) {
            return a + b;
        }
        """

        let result = parser.parse(content: content, path: "math.c")
        guard case let .success(chunks) = result else {
            Issue.record("Expected successful parse")
            return
        }

        let funcChunk = chunks.first { $0.kind == .function }
        #expect(funcChunk != nil)
        #expect(funcChunk?.signature != nil)
        #expect(funcChunk?.signature?.contains("calculateSum") == true)
    }

    @Test("Extract doc comment from C code")
    func extractCDocComment() {
        let parser = TreeSitterParser()
        let content = """
        // Calculate the sum of two integers
        // Returns the result of a + b
        int calculateSum(int a, int b) {
            return a + b;
        }
        """

        let result = parser.parse(content: content, path: "math.c")
        guard case let .success(chunks) = result else {
            Issue.record("Expected successful parse")
            return
        }

        let funcChunk = chunks.first { $0.kind == .function }
        #expect(funcChunk != nil)
        #expect(funcChunk?.docComment != nil)
        #expect(funcChunk?.docComment?.contains("Calculate the sum") == true)
    }
}

// MARK: - HybridParser Tests

@Suite("HybridParser Tests")
struct HybridParserTests {
    @Test("Routes Swift files to SwiftSyntaxParser")
    func routesSwiftToSwiftSyntax() {
        let parser = HybridParser()
        let content = """
        func hello() {
            print("Hello")
        }
        """

        let result = parser.parse(content: content, path: "test.swift")

        guard case let .success(chunks) = result else {
            Issue.record("Expected successful parse")
            return
        }

        #expect(!chunks.isEmpty)
        #expect(chunks.first?.kind == .function)
    }

    @Test("Routes Objective-C files to TreeSitterParser")
    func routesObjCToTreeSitter() {
        let parser = HybridParser()
        let content = """
        @interface Test : NSObject
        @end
        """

        let result = parser.parse(content: content, path: "Test.h")

        guard case let .success(chunks) = result else {
            Issue.record("Expected successful parse")
            return
        }

        #expect(!chunks.isEmpty)
    }

    @Test("Routes unknown extensions to PlainTextParser")
    func routesUnknownToPlainText() {
        let parser = HybridParser()
        let content = """
        Some random content
        in an unknown file format.
        """

        let result = parser.parse(content: content, path: "unknown.xyz")

        guard case let .success(chunks) = result else {
            Issue.record("Expected successful parse with plain text fallback")
            return
        }

        #expect(!chunks.isEmpty)
        #expect(chunks.first?.kind == .unknown)
    }

    @Test("Routes C files correctly")
    func routesCFiles() {
        let parser = HybridParser()
        let content = """
        int main() {
            return 0;
        }
        """

        let result = parser.parse(content: content, path: "main.c")

        guard case let .success(chunks) = result else {
            Issue.record("Expected successful parse")
            return
        }

        #expect(!chunks.isEmpty)
    }

    @Test("Routes JSON files correctly")
    func routesJSONFiles() {
        let parser = HybridParser()
        let content = """
        {"key": "value"}
        """

        let result = parser.parse(content: content, path: "config.json")

        guard case let .success(chunks) = result else {
            Issue.record("Expected successful parse")
            return
        }

        #expect(!chunks.isEmpty)
    }

    @Test("Routes YAML files correctly")
    func routesYAMLFiles() {
        let parser = HybridParser()
        let content = """
        key: value
        """

        let result = parser.parse(content: content, path: "config.yaml")

        guard case let .success(chunks) = result else {
            Issue.record("Expected successful parse")
            return
        }

        #expect(!chunks.isEmpty)
    }

    @Test("Routes Markdown files correctly")
    func routesMarkdownFiles() {
        let parser = HybridParser()
        let content = """
        # Title
        Some content.
        """

        let result = parser.parse(content: content, path: "README.md")
        let chunks = result.chunks

        #expect(!chunks.isEmpty)
    }

    @Test("Supported extensions includes all expected types")
    func testSupportedExtensions() {
        let parser = HybridParser()
        let extensions = parser.supportedExtensions

        // Swift
        #expect(extensions.contains("swift"))

        // Objective-C
        #expect(extensions.contains("m"))
        #expect(extensions.contains("mm"))
        #expect(extensions.contains("h"))

        // C/C++
        #expect(extensions.contains("c"))
        #expect(extensions.contains("cpp"))
        #expect(extensions.contains("cc"))

        // Data formats
        #expect(extensions.contains("json"))
        #expect(extensions.contains("yaml"))
        #expect(extensions.contains("yml"))

        // Documentation
        #expect(extensions.contains("md"))
        #expect(extensions.contains("markdown"))
    }
}

// MARK: - PlainTextParser Tests

@Suite("PlainTextParser Tests")
struct PlainTextParserTests {
    @Test("Creates single chunk for small content")
    func smallContent() {
        let parser = PlainTextParser()
        let content = "Small content."

        let result = parser.parse(content: content, path: "test.txt")

        guard case let .success(chunks) = result else {
            Issue.record("Expected successful parse")
            return
        }

        #expect(chunks.count == 1)
        #expect(chunks.first?.kind == .unknown)
    }

    @Test("Creates multiple chunks for large content")
    func largeContent() {
        let parser = PlainTextParser(maxChunkSize: 100, overlapSize: 20)
        // Create content larger than maxChunkSize (100) with multiple lines
        // Each line is ~15 chars, so 20 lines = 300 chars
        var lines: [String] = []
        for i in 1 ... 20 {
            lines.append("Line \(i) text.")
        }
        let content = lines.joined(separator: "\n")

        let result = parser.parse(content: content, path: "large.txt")

        guard case let .success(chunks) = result else {
            Issue.record("Expected successful parse")
            return
        }

        #expect(
            chunks.count > 1,
            "Content of \(content.count) chars should produce multiple chunks with maxChunkSize=100"
        )
    }

    @Test("Preserves line numbers")
    func lineNumbers() {
        let parser = PlainTextParser()
        let content = """
        Line 1
        Line 2
        Line 3
        Line 4
        Line 5
        """

        let result = parser.parse(content: content, path: "test.txt")

        guard case let .success(chunks) = result else {
            Issue.record("Expected successful parse")
            return
        }

        #expect(chunks.first?.startLine == 1)
        #expect(chunks.first?.endLine == 5)
    }

    @Test("Handles empty content")
    func testEmptyContent() {
        let parser = PlainTextParser()
        let result = parser.parse(content: "", path: "empty.txt")

        guard case let .failure(error) = result else {
            Issue.record("Expected failure for empty content")
            return
        }

        #expect(error == .emptyContent)
    }
}
