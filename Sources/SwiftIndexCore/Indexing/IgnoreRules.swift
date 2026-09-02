// MARK: - IgnoreRules

import Foundation

/// A compiled set of path-exclusion rules.
///
/// Replaces the previous `filePath.contains(pattern)` test, which was wrong in both
/// directions: glob patterns such as `*.xcodeproj` never matched anything (no literal
/// `*` appears in a path), while a bare name like `Pods` excluded every file in a
/// project that merely lived under a directory containing that substring.
///
/// Rules are compiled once and matched against the **repo-relative** path, so a
/// project's own location on disk cannot influence what gets indexed.
public struct IgnoreRules: Sendable {
    /// Directory or file names excluded outright, matched per path component.
    private let literalNames: Set<String>

    /// Suffix patterns from `*.ext`-style globs.
    private let suffixes: [String]

    /// Anything genuinely glob-shaped, precompiled.
    private let globs: [NSRegularExpression]

    /// `.gitignore`-derived rules, evaluated in order (later wins, `!` negates).
    private let gitignore: [GitignoreRule]

    // MARK: - Construction

    /// Builds rules from configured exclude patterns and, optionally, `.gitignore`.
    ///
    /// - Parameters:
    ///   - patterns: Exclude patterns from configuration.
    ///   - rootPath: Project root, used to read `.gitignore` and relativize paths.
    ///   - respectGitignore: Whether to also honour the root `.gitignore`.
    public init(patterns: [String], rootPath: String, respectGitignore: Bool) {
        var names = Set<String>()
        var suffixList: [String] = []
        var globList: [NSRegularExpression] = []

        for pattern in patterns {
            let trimmed = pattern.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if trimmed.hasPrefix("*."), !trimmed.dropFirst(2).contains(where: Self.isGlobCharacter) {
                // `*.xcodeproj` — the common case, and the one that silently never
                // matched before.
                suffixList.append(String(trimmed.dropFirst()))
            } else if trimmed.contains(where: Self.isGlobCharacter) {
                if let regex = Self.compileGlob(trimmed) {
                    globList.append(regex)
                }
            } else {
                names.insert(trimmed)
            }
        }

        literalNames = names
        suffixes = suffixList
        globs = globList
        gitignore = respectGitignore ? Self.loadGitignore(rootPath: rootPath) : []
    }

    // MARK: - Matching

    /// Whether a path should be excluded.
    ///
    /// - Parameters:
    ///   - relativePath: Path relative to the project root.
    ///   - isDirectory: Whether the path is a directory.
    public func isIgnored(relativePath: String, isDirectory: Bool) -> Bool {
        let components = relativePath.split(separator: "/").map(String.init)

        // Cheapest first: an exact component name.
        for component in components where literalNames.contains(component) {
            return true
        }

        if let last = components.last {
            for suffix in suffixes where last.hasSuffix(suffix) {
                return true
            }
        }

        let range = NSRange(relativePath.startIndex ..< relativePath.endIndex, in: relativePath)
        for glob in globs where glob.firstMatch(in: relativePath, range: range) != nil {
            return true
        }

        // `.gitignore`: last matching rule wins, so negations can re-include.
        var ignored = false
        for rule in gitignore where rule.matches(relativePath: relativePath, isDirectory: isDirectory) {
            ignored = !rule.isNegated
        }
        return ignored
    }

    // MARK: - Helpers

    private static func isGlobCharacter(_ character: Character) -> Bool {
        character == "*" || character == "?" || character == "["
    }

    /// Compiles a glob into an anchored regular expression.
    ///
    /// `**` crosses directory separators, `*` does not, `?` is a single non-separator.
    static func compileGlob(_ pattern: String) -> NSRegularExpression? {
        var regex = "^"
        var index = pattern.startIndex

        while index < pattern.endIndex {
            let character = pattern[index]
            switch character {
            case "*":
                let next = pattern.index(after: index)
                if next < pattern.endIndex, pattern[next] == "*" {
                    regex += ".*"
                    index = pattern.index(after: next)
                    // Swallow a following slash so `**/x` also matches a bare `x`.
                    if index < pattern.endIndex, pattern[index] == "/" {
                        regex += "/?"
                        index = pattern.index(after: index)
                    }
                    continue
                }
                regex += "[^/]*"
            case "?":
                regex += "[^/]"
            default:
                regex += NSRegularExpression.escapedPattern(for: String(character))
            }
            index = pattern.index(after: index)
        }

        regex += "$"
        return try? NSRegularExpression(pattern: regex)
    }

    /// Parses the root `.gitignore`, ignoring comments and blank lines.
    ///
    /// This implements the common subset only: comments, negation, directory-only
    /// rules, anchoring and `**`. It deliberately does not read `.git/info/exclude`
    /// or a global `core.excludesFile`.
    private static func loadGitignore(rootPath: String) -> [GitignoreRule] {
        let path = (rootPath as NSString).appendingPathComponent(".gitignore")
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            return []
        }

        return contents
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { GitignoreRule(line: String($0)) }
    }
}

// MARK: - GitignoreRule

/// A single `.gitignore` line.
struct GitignoreRule: Sendable {
    let isNegated: Bool
    private let directoryOnly: Bool
    private let regex: NSRegularExpression?
    private let bareName: String?

    init?(line rawLine: String) {
        var line = rawLine.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, !line.hasPrefix("#") else { return nil }

        isNegated = line.hasPrefix("!")
        if isNegated {
            line.removeFirst()
        }

        directoryOnly = line.hasSuffix("/")
        if directoryOnly {
            line.removeLast()
        }

        let anchored = line.hasPrefix("/")
        if anchored {
            line.removeFirst()
        }
        guard !line.isEmpty else { return nil }

        if !anchored, !line.contains("/"), !line.contains("*"), !line.contains("?") {
            // `build` — matches that name at any depth. Handled without a regex
            // because it is by far the most common form.
            bareName = line
            regex = nil
        } else {
            bareName = nil
            let pattern = anchored ? line : "**/" + line
            regex = IgnoreRules.compileGlob(pattern)
        }
    }

    func matches(relativePath: String, isDirectory: Bool) -> Bool {
        if directoryOnly, !isDirectory {
            return false
        }

        if let bareName {
            return relativePath.split(separator: "/").contains { $0 == bareName }
        }

        guard let regex else { return false }
        let range = NSRange(relativePath.startIndex ..< relativePath.endIndex, in: relativePath)
        if regex.firstMatch(in: relativePath, range: range) != nil {
            return true
        }

        // A rule matching a directory also excludes everything beneath it.
        var prefix = ""
        for component in relativePath.split(separator: "/").dropLast() {
            prefix += prefix.isEmpty ? String(component) : "/" + String(component)
            let prefixRange = NSRange(prefix.startIndex ..< prefix.endIndex, in: prefix)
            if regex.firstMatch(in: prefix, range: prefixRange) != nil {
                return true
            }
        }
        return false
    }
}
