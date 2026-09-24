// MARK: - Explore Models

import Foundation

/// How much source one `explore` answer may contain.
///
/// Agent hosts move a tool result above roughly 25K characters into a file, and the
/// agent then spends another call to read it. Every tier stays below that limit.
public struct ExploreBudget: Sendable, Equatable {
    public let characters: Int
    public let files: Int

    /// Absolute ceiling for any answer.
    public static let hardCap = 24500

    public init(characters: Int, files: Int) {
        self.characters = min(characters, Self.hardCap)
        self.files = max(files, 1)
    }

    /// Budget for an index of `fileCount` files. A larger project needs more context
    /// to show one flow.
    public static func forIndex(fileCount: Int) -> ExploreBudget {
        switch fileCount {
        case ..<200: ExploreBudget(characters: 13000, files: 4)
        case ..<2000: ExploreBudget(characters: 18000, files: 6)
        default: ExploreBudget(characters: 24000, files: 8)
        }
    }
}

/// Settings for one `explore` call.
public struct ExploreOptions: Sendable {
    /// Upper limit on files. The budget tier applies when this is nil or larger.
    public var maxFiles: Int?
    /// Replaces the tier chosen from the index size.
    public var budget: ExploreBudget?
    /// Project root, used to print relative paths.
    public var projectRoot: String?
    /// Files known to differ from the index.
    public var dirtyPaths: Set<String>

    public init(
        maxFiles: Int? = nil,
        budget: ExploreBudget? = nil,
        projectRoot: String? = nil,
        dirtyPaths: Set<String> = []
    ) {
        self.maxFiles = maxFiles
        self.budget = budget
        self.projectRoot = projectRoot
        self.dirtyPaths = dirtyPaths
    }
}

/// A file selected for an `explore` answer.
public struct ExploreFile: Sendable {
    public let path: String
    public let score: Double
    /// Whether the file holds a symbol on the call path between the top seeds.
    public let onSpine: Bool
    /// Ranked symbols in the file, best first.
    public let symbols: [(symbol: SymbolNode, score: Double)]
    /// Line ranges of matched chunks without graph symbols, e.g. Markdown.
    public let chunkRanges: [ClosedRange<Int>]
    /// Every symbol declared in the file, used to reduce a type to its signatures.
    public let declarations: [SymbolNode]
}

/// The blast radius of the top symbol.
public struct ExploreImpact: Sendable {
    public let symbolName: String
    public let symbols: Int
    public let files: Int
    public let tests: Int
}

/// Everything the renderer needs besides file contents.
public struct ExplorePlan: Sendable {
    public let query: String
    public let files: [ExploreFile]
    /// Qualified names along the call path between the top seeds.
    public let spine: [String]
    public let impact: ExploreImpact?
    /// Call-site lines per symbol id, used to window long bodies.
    public let callSites: [String: [Int]]
    public let budget: ExploreBudget
}

/// The rendered answer.
public struct ExploreResult: Sendable {
    public let text: String
    public let plan: ExplorePlan
}
