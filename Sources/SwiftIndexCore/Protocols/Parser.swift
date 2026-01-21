// MARK: - Parser Protocol

import Foundation

/// A parser that extracts code chunks from source files.
///
/// Parsers analyze source files and produce structured chunks
/// that can be indexed and searched. Each parser implementation
/// handles specific file types (Swift, ObjC, JSON, etc.).
public protocol Parser: Sendable {
    /// File extensions this parser can handle.
    var supportedExtensions: Set<String> { get }

    /// Parse a file and extract code chunks.
    ///
    /// - Parameters:
    ///   - content: The file content as a string.
    ///   - path: The file path (used for metadata).
    /// - Returns: Result containing either parsed chunks or an error.
    func parse(content: String, path: String) -> ParseResult
}

/// Result of a parsing operation.
public enum ParseResult: Sendable, Equatable {
    /// Successful parse with extracted chunks.
    case success([CodeChunk])

    /// Parse failure with error details.
    case failure(ParseError)
}

/// Errors that can occur during parsing.
public enum ParseError: Error, Sendable, Equatable {
    /// The file content is not valid for this parser.
    case invalidSyntax(String)

    /// The file extension is not supported.
    case unsupportedExtension(String)

    /// The file content is empty.
    case emptyContent

    /// Generic parsing error.
    case parsingFailed(String)
}
