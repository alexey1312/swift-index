// MARK: - PlainTextParser

import Crypto
import Foundation

/// A parser for plain text files using simple line-based chunking.
///
/// This parser is used as a fallback for file types that don't have
/// specialized parsers. It creates chunks based on line boundaries
/// and respects a configurable maximum chunk size.
public struct PlainTextParser: Parser, Sendable {
    // MARK: - Configuration

    /// Maximum number of characters per chunk.
    public let maxChunkSize: Int

    /// Number of characters to overlap between chunks.
    public let overlapSize: Int

    // MARK: - Parser Protocol

    public var supportedExtensions: Set<String> {
        [] // Accepts any extension as fallback
    }

    // MARK: - Initialization

    /// Creates a plain text parser with the specified configuration.
    ///
    /// - Parameters:
    ///   - maxChunkSize: Maximum characters per chunk. Default is 2000.
    ///   - overlapSize: Characters to overlap between chunks. Default is 200.
    public init(maxChunkSize: Int = 2000, overlapSize: Int = 200) {
        self.maxChunkSize = maxChunkSize
        self.overlapSize = overlapSize
    }

    // MARK: - Parsing

    public func parse(content: String, path: String, fileHash: String) -> ParseResult {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(.emptyContent)
        }

        let lines = content.components(separatedBy: "\n")

        // For small files, create a single chunk
        if content.count <= maxChunkSize {
            let chunk = createChunk(
                content: content,
                path: path,
                startLine: 1,
                endLine: lines.count,
                fileHash: fileHash
            )
            return .success([chunk])
        }

        // For larger files, split into chunks at line boundaries
        var chunks: [CodeChunk] = []
        var currentContent = ""
        var currentStartLine = 1
        var currentLineNumber = 1

        for (index, line) in lines.enumerated() {
            let lineWithNewline = index < lines.count - 1 ? line + "\n" : line

            // Check if adding this line would exceed the limit
            if currentContent.count + lineWithNewline.count > maxChunkSize, !currentContent.isEmpty {
                // Create chunk from accumulated content
                let chunk = createChunk(
                    content: currentContent,
                    path: path,
                    startLine: currentStartLine,
                    endLine: currentLineNumber - 1,
                    fileHash: fileHash
                )
                chunks.append(chunk)

                // Start new chunk with overlap
                let overlapContent = extractOverlap(from: currentContent)
                currentContent = overlapContent + lineWithNewline
                currentStartLine = max(1, currentLineNumber - countLines(in: overlapContent))
            } else {
                currentContent += lineWithNewline
            }

            currentLineNumber += 1
        }

        // Don't forget the last chunk
        if !currentContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let chunk = createChunk(
                content: currentContent,
                path: path,
                startLine: currentStartLine,
                endLine: lines.count,
                fileHash: fileHash
            )
            chunks.append(chunk)
        }

        return .success(chunks)
    }

    // MARK: - Private Helpers

    private func createChunk(
        content: String,
        path: String,
        startLine: Int,
        endLine: Int,
        fileHash: String
    ) -> CodeChunk {
        let chunkId = generateChunkId(
            path: path,
            startLine: startLine,
            content: content
        )

        return CodeChunk(
            id: chunkId,
            path: path,
            content: content,
            startLine: startLine,
            endLine: endLine,
            kind: .unknown,
            symbols: [],
            references: [],
            fileHash: fileHash
        )
    }

    private func extractOverlap(from content: String) -> String {
        guard overlapSize > 0, content.count > overlapSize else {
            return ""
        }

        // Take the last overlapSize characters
        let startIndex = content.index(content.endIndex, offsetBy: -overlapSize)
        let overlap = String(content[startIndex...])

        // Try to start at a line boundary
        if let lineStart = overlap.lastIndex(of: "\n") {
            return String(overlap[overlap.index(after: lineStart)...])
        }

        return overlap
    }

    private func countLines(in content: String) -> Int {
        content.components(separatedBy: "\n").count
    }

    private func generateChunkId(path: String, startLine: Int, content: String) -> String {
        let components = [path, String(startLine), String(content.prefix(50).hashValue)]
        let joined = components.joined(separator: ":")
        let data = Data(joined.utf8)
        let digest = SHA256.hash(data: data)
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}
