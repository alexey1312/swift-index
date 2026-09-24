// MARK: - DeadCodeFinder

import Foundation

/// Finds declarations that nothing in the project refers to.
///
/// The graph sees only Swift source, so the finder is conservative. It skips every
/// symbol a caller outside the graph can reach: public API, overrides, protocol
/// requirements and witnesses, `@objc` and other entry-point attributes, and tests.
/// A result is a candidate for review, not proof.
public enum DeadCodeFinder {
    /// Names that the runtime or a standard protocol calls without a visible edge.
    public static let exemptNames: Set<String> = [
        "init", "deinit", "main", "run", "body", "makeBody", "id", "description",
        "debugDescription", "errorDescription", "failureReason", "recoverySuggestion",
        "hash", "encode", "rawValue", "allCases", "callAsFunction", "CodingKeys",
        "makeIterator", "next", "setUp", "tearDown", "validate", "previews",
    ]

    /// Symbols with no incoming edge, in path and line order.
    public static func find(in store: GRDBChunkStore, limit: Int = 100) async throws -> [SymbolNode] {
        try await store.unreferencedSymbols(exemptNames: exemptNames, limit: limit)
    }

    /// One line per symbol: `path:line kind qualifiedName`.
    public static func format(_ symbols: [SymbolNode], projectRoot: String? = nil) -> String {
        guard !symbols.isEmpty else {
            return "No unreferenced symbols found."
        }
        let prefix = projectRoot.map { $0.hasSuffix("/") ? $0 : $0 + "/" }
        var lines = ["unreferenced[\(symbols.count)] (candidates, verify before deleting):"]
        for symbol in symbols {
            var path = symbol.path
            if let prefix, path.hasPrefix(prefix) {
                path.removeFirst(prefix.count)
            }
            lines.append("  \(path):\(symbol.startLine) \(symbol.kind.rawValue) \(symbol.qualifiedName)")
        }
        return lines.joined(separator: "\n")
    }
}
