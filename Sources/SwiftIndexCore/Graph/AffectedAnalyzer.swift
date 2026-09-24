// MARK: - AffectedAnalyzer

import Foundation

/// A test file that a change can break, and how the change reaches it.
public struct AffectedTest: Sendable, Equatable, Codable {
    public enum Reason: String, Sendable, Codable {
        /// The test file itself changed.
        case changed
        /// A symbol in the test reaches a changed symbol through the graph.
        case graph
        /// The test imports the module of a changed file.
        case importsModule = "import"
    }

    public let path: String
    public let reason: Reason

    public init(path: String, reason: Reason) {
        self.path = path
        self.reason = reason
    }
}

/// Finds the tests to run for a set of changed files.
///
/// Walks graph edges backwards from every symbol in the changed files, then adds
/// tests that import a changed module. The import rule catches tests that reach
/// the change only through edges the resolver could not type.
public enum AffectedAnalyzer {
    static let traversedKinds: [EdgeKind] = [.calls, .initializes, .references, .inherits, .conforms, .overrides]

    /// Tests affected by `changedPaths`, sorted by path.
    ///
    /// - Parameters:
    ///   - changedPaths: Changed files, absolute or relative to `projectRoot`.
    ///   - store: Index store with the symbol graph.
    ///   - depth: Maximum number of reverse hops.
    public static func affectedTests(
        changedPaths: [String],
        store: GRDBChunkStore,
        projectRoot: String,
        depth: Int = 4
    ) async throws -> [AffectedTest] {
        let root = FileCollector.canonicalPath(projectRoot)
        let changed = Set(changedPaths.map { absolutePath($0, root: root) })

        var results: [String: AffectedTest.Reason] = [:]
        for path in changed where isTestPath(path) {
            results[path] = .changed
        }

        var frontier: [String] = []
        for path in changed {
            try await frontier.append(contentsOf: store.symbolIDs(forPath: path))
        }
        var visited = Set(frontier)
        for _ in 0 ..< depth where !frontier.isEmpty {
            let edges = try await store.neighbours(
                of: frontier,
                incoming: true,
                kinds: traversedKinds,
                minConfidence: 0.5
            )
            frontier = []
            for edge in edges where visited.insert(edge.sourceID).inserted {
                frontier.append(edge.sourceID)
                if isTestPath(edge.sourcePath), results[edge.sourcePath] == nil {
                    results[edge.sourcePath] = .graph
                }
            }
        }

        let modules = Set(changed.compactMap { GraphBuilder.inferModule(path: $0, projectRoot: root) })
        for path in try await store.paths(importingAnyOf: Array(modules)) where isTestPath(path) {
            if results[path] == nil {
                results[path] = .importsModule
            }
        }

        return results
            .map { AffectedTest(path: $0.key, reason: $0.value) }
            .sorted { $0.path < $1.path }
    }

    /// Whether a path belongs to a test target.
    public static func isTestPath(_ path: String) -> Bool {
        path.contains("/Tests/") || path.hasSuffix("Tests.swift") || path.hasSuffix("Test.swift")
    }

    private static func absolutePath(_ path: String, root: String) -> String {
        let absolute = path.hasPrefix("/") ? path : (root as NSString).appendingPathComponent(path)
        return FileCollector.canonicalPath((absolute as NSString).standardizingPath)
    }
}
