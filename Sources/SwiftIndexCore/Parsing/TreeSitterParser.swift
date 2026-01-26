// MARK: - TreeSitterParser

import Crypto
import Foundation
import SwiftTreeSitter

/// A parser for non-Swift files using tree-sitter or pattern-based parsing.
///
/// This parser handles multiple languages including:
/// - Objective-C (.m, .mm, .h)
/// - C/C++ (.c, .cpp, .cc, .cxx, .h, .hpp)
/// - JSON (.json)
/// - YAML (.yaml, .yml)
/// - Markdown (.md, .markdown)
///
/// For languages where tree-sitter grammars are not available at runtime,
/// it falls back to pattern-based parsing that extracts meaningful chunks.
public struct TreeSitterParser: Parser, Sendable {
    // MARK: - Parser Protocol

    public var supportedExtensions: Set<String> {
        [
            // Objective-C
            "m", "mm", "h",
            // C/C++
            "c", "cpp", "cc", "cxx", "hpp",
            // Data formats
            "json",
            "yaml", "yml",
            // Documentation
            "md", "markdown",
        ]
    }

    // MARK: - Regex Patterns

    // swiftlint:disable force_try line_length
    private enum Patterns {
        // Objective-C
        static let objcImplementation = try! NSRegularExpression(pattern: #"@implementation\s+(\w+)[\s\S]*?@end"#)
        static let objcMethod = try! NSRegularExpression(
            pattern: #"^[-+]\s*\([^)]+\)\s*\w+[^{]*\{[\s\S]*?^\}"#,
            options: .anchorsMatchLines
        )

        // Header
        static let objcInterface = try! NSRegularExpression(pattern: #"@interface\s+(\w+)[\s\S]*?@end"#)
        static let objcProtocol = try! NSRegularExpression(pattern: #"@protocol\s+(\w+)[\s\S]*?@end"#)
        static let cFuncDecl = try! NSRegularExpression(
            pattern: #"^\w[\w\s\*]+\s+(\w+)\s*\([^)]*\)\s*;"#,
            options: .anchorsMatchLines
        )
        static let cStructTypedef =
            try! NSRegularExpression(pattern: #"typedef\s+struct\s*\w*\s*\{[\s\S]*?\}\s*(\w+)\s*;"#)

        // C
        static let cFunction = try! NSRegularExpression(
            pattern: #"^[\w\s\*]+\s+(\w+)\s*\([^)]*\)\s*\{[\s\S]*?^\}"#,
            options: .anchorsMatchLines
        )
        static let cStruct = try! NSRegularExpression(pattern: #"struct\s+(\w+)\s*\{[\s\S]*?\}\s*;"#)
        static let cEnum = try! NSRegularExpression(pattern: #"enum\s+(\w+)\s*\{[\s\S]*?\}\s*;"#)

        // C++
        static let cppClass = try! NSRegularExpression(
            pattern: #"class\s+(\w+)[\s\S]*?\{[\s\S]*?^\};"#,
            options: .anchorsMatchLines
        )
        static let cppFunction = try! NSRegularExpression(
            pattern: #"^[\w\s\*:&<>]+\s+(\w+::)?(\w+)\s*\([^)]*\)\s*(const)?\s*\{[\s\S]*?^\}"#,
            options: .anchorsMatchLines
        )
        static let cppNamespace = try! NSRegularExpression(pattern: #"namespace\s+(\w+)\s*\{"#)

        // JSON & YAML
        static let jsonKey = try! NSRegularExpression(pattern: #"^\s*"(\w+)"\s*:"#, options: .anchorsMatchLines)
        static let yamlKey = try! NSRegularExpression(pattern: #"^(\w+):"#, options: .anchorsMatchLines)
    }

    // swiftlint:enable force_try line_length

    // MARK: - Initialization

    public init() {}

    // MARK: - Parsing

    public func parse(content: String, path: String, fileHash: String) -> ParseResult {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(.emptyContent)
        }

        let ext = (path as NSString).pathExtension.lowercased()

        // Route to specialized parser based on extension
        switch ext {
        case "m", "mm":
            return parseObjectiveC(content: content, path: path, fileHash: fileHash)
        case "h":
            return parseHeader(content: content, path: path, fileHash: fileHash)
        case "c":
            return parseC(content: content, path: path, fileHash: fileHash)
        case "cpp", "cc", "cxx", "hpp":
            return parseCpp(content: content, path: path, fileHash: fileHash)
        case "json":
            return parseJSON(content: content, path: path, fileHash: fileHash)
        case "yaml", "yml":
            return parseYAML(content: content, path: path, fileHash: fileHash)
        case "md", "markdown":
            return parseMarkdown(content: content, path: path, fileHash: fileHash)
        default:
            return PlainTextParser().parse(content: content, path: path, fileHash: fileHash)
        }
    }

    // MARK: - Objective-C Parsing

    private func parseObjectiveC(content: String, path: String, fileHash: String) -> ParseResult {
        var chunks: [CodeChunk] = []

        // Parse @implementation blocks
        chunks.append(contentsOf: extractMatches(
            regex: Patterns.objcImplementation,
            content: content,
            path: path,
            kind: .class,
            fileHash: fileHash
        ))

        // Parse method implementations within @implementation
        chunks.append(contentsOf: extractMatches(
            regex: Patterns.objcMethod,
            content: content,
            path: path,
            kind: .method,
            fileHash: fileHash
        ))

        // If no specific patterns matched, create a document chunk
        if chunks.isEmpty {
            chunks.append(createDocumentChunk(content: content, path: path, fileHash: fileHash))
        }

        return .success(chunks)
    }

    private func parseHeader(content: String, path: String, fileHash: String) -> ParseResult {
        var chunks: [CodeChunk] = []

        // Parse @interface declarations
        chunks.append(contentsOf: extractMatches(
            regex: Patterns.objcInterface,
            content: content,
            path: path,
            kind: .interface,
            fileHash: fileHash
        ))

        // Parse @protocol declarations
        chunks.append(contentsOf: extractMatches(
            regex: Patterns.objcProtocol,
            content: content,
            path: path,
            kind: .protocol,
            fileHash: fileHash
        ))

        // Parse C function declarations
        chunks.append(contentsOf: extractMatches(
            regex: Patterns.cFuncDecl,
            content: content,
            path: path,
            kind: .function,
            fileHash: fileHash
        ))

        // Parse struct definitions
        chunks.append(contentsOf: extractMatches(
            regex: Patterns.cStructTypedef,
            content: content,
            path: path,
            kind: .struct,
            fileHash: fileHash
        ))

        // If no specific patterns matched, create a document chunk
        if chunks.isEmpty {
            chunks.append(createDocumentChunk(content: content, path: path, fileHash: fileHash))
        }

        return .success(chunks)
    }

    // MARK: - C Parsing

    private func parseC(content: String, path: String, fileHash: String) -> ParseResult {
        var chunks: [CodeChunk] = []

        // Parse function definitions
        chunks.append(contentsOf: extractMatches(
            regex: Patterns.cFunction,
            content: content,
            path: path,
            kind: .function,
            fileHash: fileHash
        ))

        // Parse struct definitions
        chunks.append(contentsOf: extractMatches(
            regex: Patterns.cStruct,
            content: content,
            path: path,
            kind: .struct,
            fileHash: fileHash
        ))

        // Parse typedef structs
        chunks.append(contentsOf: extractMatches(
            regex: Patterns.cStructTypedef,
            content: content,
            path: path,
            kind: .struct,
            fileHash: fileHash
        ))

        // Parse enum definitions
        chunks.append(contentsOf: extractMatches(
            regex: Patterns.cEnum,
            content: content,
            path: path,
            kind: .enum,
            fileHash: fileHash
        ))

        // If no specific patterns matched, create a document chunk
        if chunks.isEmpty {
            chunks.append(createDocumentChunk(content: content, path: path, fileHash: fileHash))
        }

        return .success(chunks)
    }

    // MARK: - C++ Parsing

    private func parseCpp(content: String, path: String, fileHash: String) -> ParseResult {
        var chunks: [CodeChunk] = []

        // Parse class definitions
        chunks.append(contentsOf: extractMatches(
            regex: Patterns.cppClass,
            content: content,
            path: path,
            kind: .class,
            fileHash: fileHash
        ))

        // Parse function definitions (including member functions)
        chunks.append(contentsOf: extractMatches(
            regex: Patterns.cppFunction,
            content: content,
            path: path,
            kind: .function,
            fileHash: fileHash
        ))

        // Parse namespace definitions
        chunks.append(contentsOf: extractMatches(
            regex: Patterns.cppNamespace,
            content: content,
            path: path,
            kind: .namespace,
            fileHash: fileHash
        ))

        // If no specific patterns matched, create a document chunk
        if chunks.isEmpty {
            chunks.append(createDocumentChunk(content: content, path: path, fileHash: fileHash))
        }

        return .success(chunks)
    }

    // MARK: - JSON Parsing

    private func parseJSON(content: String, path: String, fileHash: String) -> ParseResult {
        // For JSON, we treat the whole file as a document
        // and extract top-level keys as symbols
        var symbols: [String] = []

        // Extract top-level keys from JSON objects
        let regex = Patterns.jsonKey
        let range = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, options: [], range: range)

        for match in matches.prefix(20) { // Limit to first 20 keys
            if let keyRange = Range(match.range(at: 1), in: content) {
                symbols.append(String(content[keyRange]))
            }
        }

        let chunk = CodeChunk(
            id: generateChunkId(path: path, content: content),
            path: path,
            content: content,
            startLine: 1,
            endLine: content.components(separatedBy: "\n").count,
            kind: .document,
            symbols: symbols,
            references: [],
            fileHash: fileHash,
            language: "json"
        )

        return .success([chunk])
    }

    // MARK: - YAML Parsing

    private func parseYAML(content: String, path: String, fileHash: String) -> ParseResult {
        // Extract top-level keys from YAML
        var symbols: [String] = []

        let regex = Patterns.yamlKey
        let range = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, options: [], range: range)

        for match in matches.prefix(20) { // Limit to first 20 keys
            if let keyRange = Range(match.range(at: 1), in: content) {
                symbols.append(String(content[keyRange]))
            }
        }

        let chunk = CodeChunk(
            id: generateChunkId(path: path, content: content),
            path: path,
            content: content,
            startLine: 1,
            endLine: content.components(separatedBy: "\n").count,
            kind: .document,
            symbols: symbols,
            references: [],
            fileHash: fileHash,
            language: "yaml"
        )

        return .success([chunk])
    }

    // MARK: - Markdown Parsing

    private func parseMarkdown(content: String, path: String, fileHash: String) -> ParseResult {
        var chunks: [CodeChunk] = []
        var snippets: [InfoSnippet] = []

        let lines = content.components(separatedBy: "\n")
        var currentSection = ""
        var currentSectionStart = 1
        var currentSectionTitle = ""
        var headerStack: [String] = [] // Track header hierarchy for breadcrumb

        for (index, line) in lines.enumerated() {
            let lineNumber = index + 1

            // Check for headers
            if line.hasPrefix("#") {
                // Save previous section if it has content
                if !currentSection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let breadcrumb = headerStack.isEmpty ? nil : headerStack.joined(separator: " > ")

                    // Create CodeChunk for code search
                    let chunkId = generateChunkId(path: path, content: currentSection, startLine: currentSectionStart)
                    let chunk = CodeChunk(
                        id: chunkId,
                        path: path,
                        content: currentSection,
                        startLine: currentSectionStart,
                        endLine: lineNumber - 1,
                        kind: .section,
                        symbols: currentSectionTitle.isEmpty ? [] : [currentSectionTitle],
                        references: [],
                        fileHash: fileHash,
                        breadcrumb: breadcrumb,
                        language: "markdown"
                    )
                    chunks.append(chunk)

                    // Create InfoSnippet for documentation search
                    let snippet = InfoSnippet(
                        path: path,
                        content: currentSection,
                        startLine: currentSectionStart,
                        endLine: lineNumber - 1,
                        breadcrumb: breadcrumb,
                        language: "markdown",
                        chunkId: chunkId,
                        kind: .markdownSection,
                        fileHash: fileHash
                    )
                    snippets.append(snippet)
                }

                // Calculate header level
                let headerLevel = line.prefix(while: { $0 == "#" }).count

                // Update header stack for breadcrumb
                while headerStack.count >= headerLevel {
                    headerStack.removeLast()
                }

                // Start new section
                currentSection = line + "\n"
                currentSectionStart = lineNumber
                currentSectionTitle = line.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
                headerStack.append(currentSectionTitle)
            } else {
                currentSection += line + "\n"
            }
        }

        // Don't forget the last section
        if !currentSection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let breadcrumb = headerStack.isEmpty ? nil : headerStack.joined(separator: " > ")

            // Create CodeChunk
            let chunkId = generateChunkId(path: path, content: currentSection, startLine: currentSectionStart)
            let chunk = CodeChunk(
                id: chunkId,
                path: path,
                content: currentSection,
                startLine: currentSectionStart,
                endLine: lines.count,
                kind: .section,
                symbols: currentSectionTitle.isEmpty ? [] : [currentSectionTitle],
                references: [],
                fileHash: fileHash,
                breadcrumb: breadcrumb,
                language: "markdown"
            )
            chunks.append(chunk)

            // Create InfoSnippet
            let snippet = InfoSnippet(
                path: path,
                content: currentSection,
                startLine: currentSectionStart,
                endLine: lines.count,
                breadcrumb: breadcrumb,
                language: "markdown",
                chunkId: chunkId,
                kind: .markdownSection,
                fileHash: fileHash
            )
            snippets.append(snippet)
        }

        // If no sections found, create a single document chunk
        if chunks.isEmpty {
            let chunk = createDocumentChunk(content: content, path: path, fileHash: fileHash)
            chunks.append(chunk)

            // Also create a documentation snippet for the whole document
            let snippet = InfoSnippet(
                path: path,
                content: content,
                startLine: 1,
                endLine: lines.count,
                breadcrumb: nil,
                language: "markdown",
                chunkId: chunk.id,
                kind: .documentation,
                fileHash: fileHash
            )
            snippets.append(snippet)
        }

        return .successWithSnippets(chunks, snippets)
    }

    // MARK: - Helper Methods

    private func extractMatches(
        regex: NSRegularExpression,
        content: String,
        path: String,
        kind: ChunkKind,
        fileHash: String
    ) -> [CodeChunk] {
        let range = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, options: [], range: range)
        let language = detectLanguage(from: path)

        return matches.compactMap { match -> CodeChunk? in
            guard let matchRange = Range(match.range, in: content) else {
                return nil
            }

            let matchedContent = String(content[matchRange])

            // Calculate line numbers
            let beforeMatch = String(content[..<matchRange.lowerBound])
            let startLine = beforeMatch.components(separatedBy: "\n").count
            let endLine = startLine + matchedContent.components(separatedBy: "\n").count - 1

            // Extract symbol name if captured
            var symbols: [String] = []
            if match.numberOfRanges > 1, let symbolRange = Range(match.range(at: 1), in: content) {
                symbols.append(String(content[symbolRange]))
            }

            // Extract preceding doc comment if present
            let docComment = extractDocComment(before: matchRange.lowerBound, in: content)

            // Build signature from first line of matched content
            let signature = matchedContent.components(separatedBy: "\n").first?
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "{", with: "")
                .trimmingCharacters(in: .whitespaces)

            return CodeChunk(
                id: generateChunkId(path: path, content: matchedContent, startLine: startLine),
                path: path,
                content: matchedContent,
                startLine: startLine,
                endLine: endLine,
                kind: kind,
                symbols: symbols,
                references: [],
                fileHash: fileHash,
                docComment: docComment,
                signature: signature,
                breadcrumb: nil,
                language: language
            )
        }
    }

    private func extractDocComment(before position: String.Index, in content: String) -> String? {
        // Look backwards for doc comments (// or /* style)
        var docLines: [String] = []
        var foundComment = false

        var currentEnd = position

        // Loop to process lines backwards
        while true {
            var lineStart = currentEnd
            var foundNewline = false

            // Scan backwards for newline
            while lineStart > content.startIndex {
                let prevIndex = content.index(before: lineStart)
                if content[prevIndex] == "\n" {
                    foundNewline = true
                    break
                }
                lineStart = prevIndex
            }

            let lineContent = content[lineStart ..< currentEnd]

            // Process the line
            let trimmed = lineContent.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("///") {
                docLines.insert(String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces), at: 0)
                foundComment = true
            } else if trimmed.hasPrefix("//") {
                docLines.insert(String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces), at: 0)
                foundComment = true
            } else if trimmed.isEmpty {
                if foundComment {
                    // Empty line after finding comments - stop collecting
                    break
                }
                // If not foundComment, continue (skips blank lines before comments)
            } else {
                // Non-comment, non-empty line - stop
                break
            }

            if !foundNewline {
                // We reached start of content and processed the last line
                break
            }

            // Move currentEnd to before the newline
            currentEnd = content.index(before: lineStart)
        }

        let result = docLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private func detectLanguage(from path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "m", "mm": return "objective-c"
        case "h": return "c-header"
        case "c": return "c"
        case "cpp", "cc", "cxx", "hpp": return "cpp"
        case "json": return "json"
        case "yaml", "yml": return "yaml"
        case "md", "markdown": return "markdown"
        default: return "unknown"
        }
    }

    private func createDocumentChunk(content: String, path: String, fileHash: String) -> CodeChunk {
        CodeChunk(
            id: generateChunkId(path: path, content: content),
            path: path,
            content: content,
            startLine: 1,
            endLine: content.components(separatedBy: "\n").count,
            kind: .document,
            symbols: [],
            references: [],
            fileHash: fileHash,
            language: detectLanguage(from: path)
        )
    }

    private func generateChunkId(path: String, content: String, startLine: Int = 1) -> String {
        let components = [path, String(startLine), String(content.prefix(100).hashValue)]
        let joined = components.joined(separator: ":")
        let data = Data(joined.utf8)
        let digest = SHA256.hash(data: data)
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}
