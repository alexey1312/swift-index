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

        // Check every component, not just the last. A pattern like `*.xcodeproj`
        // names a directory, and its contents must be excluded too. The collector
        // gets this for free by pruning the directory, but the watcher only ever
        // sees file paths — so a last-component-only test let every file inside a
        // matched directory through, and the two disagreed about scope.
        for component in components {
            for suffix in suffixes where component.hasSuffix(suffix) {
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

    /// Compiles a glob against the full relative path.
    ///
    /// Uses `.fullPath` anchoring, unlike search's `GlobMatcher`: ignore patterns are
    /// matched against paths already made relative to the project root, so an
    /// implicit "any leading directory" prefix would make a rule far broader than
    /// written. Callers that need containment walk ancestor prefixes explicitly.
    static func compileGlob(_ pattern: String) -> NSRegularExpression? {
        GlobPattern.compile(pattern, anchoring: .fullPath)
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
        let components = relativePath.split(separator: "/").map(String.init)

        if let bareName {
            // A trailing-slash rule such as `Generated/` excludes the directory *and*
            // everything beneath it, so when testing a file only ancestors count.
            // Matching just the directory entry made the watcher accept files the
            // collector had pruned, and reconciliation then treated them as deleted.
            let candidates = (directoryOnly && !isDirectory) ? Array(components.dropLast()) : components
            return candidates.contains(bareName)
        }

        guard let regex else { return false }

        if !directoryOnly || isDirectory, matches(regex, relativePath) {
            return true
        }

        // Walk ancestor prefixes so a rule matching a directory covers its contents.
        var prefix = ""
        for component in components.dropLast() {
            prefix += prefix.isEmpty ? component : "/" + component
            if matches(regex, prefix) {
                return true
            }
        }
        return false
    }

    private func matches(_ regex: NSRegularExpression, _ path: String) -> Bool {
        let range = NSRange(path.startIndex ..< path.endIndex, in: path)
        return regex.firstMatch(in: path, range: range) != nil
    }
}
