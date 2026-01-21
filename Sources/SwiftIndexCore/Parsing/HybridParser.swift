// MARK: - HybridParser

import Foundation

/// A router that delegates parsing to the appropriate specialized parser.
///
/// The HybridParser determines the best parser for each file based on its
/// extension and routes the parsing request accordingly:
///
/// - `.swift` files → `SwiftSyntaxParser` (100% AST accuracy)
/// - `.m`, `.mm`, `.h` files → `TreeSitterParser` (Objective-C)
/// - `.c`, `.cpp`, etc. → `TreeSitterParser` (C/C++)
/// - `.json`, `.yaml` → `TreeSitterParser` (data formats)
/// - `.md` → `TreeSitterParser` (Markdown)
/// - Unknown extensions → `PlainTextParser` (fallback)
public struct HybridParser: Parser, Sendable {
    // MARK: - Parsers

    private let swiftParser: SwiftSyntaxParser
    private let treeSitterParser: TreeSitterParser
    private let plainTextParser: PlainTextParser

    // MARK: - Parser Protocol

    public var supportedExtensions: Set<String> {
        var extensions = swiftParser.supportedExtensions
        extensions.formUnion(treeSitterParser.supportedExtensions)
        // PlainTextParser handles everything else
        return extensions
    }

    // MARK: - Initialization

    /// Creates a hybrid parser with default configuration.
    public init() {
        swiftParser = SwiftSyntaxParser()
        treeSitterParser = TreeSitterParser()
        plainTextParser = PlainTextParser()
    }

    /// Creates a hybrid parser with custom parsers.
    ///
    /// - Parameters:
    ///   - swiftParser: Parser for Swift files.
    ///   - treeSitterParser: Parser for non-Swift code files.
    ///   - plainTextParser: Fallback parser for unknown file types.
    public init(
        swiftParser: SwiftSyntaxParser,
        treeSitterParser: TreeSitterParser,
        plainTextParser: PlainTextParser
    ) {
        self.swiftParser = swiftParser
        self.treeSitterParser = treeSitterParser
        self.plainTextParser = plainTextParser
    }

    // MARK: - Parsing

    public func parse(content: String, path: String) -> ParseResult {
        let ext = (path as NSString).pathExtension.lowercased()

        // Route to appropriate parser based on extension
        if swiftParser.supportedExtensions.contains(ext) {
            return swiftParser.parse(content: content, path: path)
        }

        if treeSitterParser.supportedExtensions.contains(ext) {
            return treeSitterParser.parse(content: content, path: path)
        }

        // Fallback to plain text parser for unknown extensions
        return plainTextParser.parse(content: content, path: path)
    }

    // MARK: - Language Detection

    /// Detects the language of a file based on its extension.
    ///
    /// - Parameter path: The file path.
    /// - Returns: The detected language, or `.unknown` if not recognized.
    public static func detectLanguage(for path: String) -> Language {
        let ext = (path as NSString).pathExtension.lowercased()

        switch ext {
        case "swift":
            return .swift
        case "m", "mm":
            return .objectiveC
        case "h":
            // Could be C, C++, or ObjC header
            return .header
        case "c":
            return .c
        case "cpp", "cc", "cxx":
            return .cpp
        case "hpp":
            return .cppHeader
        case "json":
            return .json
        case "yaml", "yml":
            return .yaml
        case "md", "markdown":
            return .markdown
        default:
            return .unknown
        }
    }

    /// Checks if a file extension is supported by any parser.
    ///
    /// - Parameter path: The file path.
    /// - Returns: `true` if the file can be parsed with syntax awareness.
    public func isSupported(path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return supportedExtensions.contains(ext)
    }
}

// MARK: - Language Enum

/// Represents programming languages and file types supported by the parser.
public enum Language: String, Sendable, CaseIterable {
    case swift
    case objectiveC = "objc"
    case c
    case cpp
    case header
    case cppHeader
    case json
    case yaml
    case markdown
    case unknown

    /// Human-readable name for the language.
    public var displayName: String {
        switch self {
        case .swift: "Swift"
        case .objectiveC: "Objective-C"
        case .c: "C"
        case .cpp: "C++"
        case .header: "Header"
        case .cppHeader: "C++ Header"
        case .json: "JSON"
        case .yaml: "YAML"
        case .markdown: "Markdown"
        case .unknown: "Unknown"
        }
    }

    /// File extensions associated with this language.
    public var extensions: Set<String> {
        switch self {
        case .swift: ["swift"]
        case .objectiveC: ["m", "mm"]
        case .c: ["c"]
        case .cpp: ["cpp", "cc", "cxx"]
        case .header: ["h"]
        case .cppHeader: ["hpp"]
        case .json: ["json"]
        case .yaml: ["yaml", "yml"]
        case .markdown: ["md", "markdown"]
        case .unknown: []
        }
    }
}
