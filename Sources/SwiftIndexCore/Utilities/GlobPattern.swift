// MARK: - GlobPattern

import Foundation

/// Translates glob patterns into regular expressions.
///
/// A single-pass scanner rather than a sequence of string substitutions. Substitution
/// cannot work here: replacing `**/` with `(.*/)?` introduces `.`, `*` and `?`
/// characters that the *later* substitutions for `*` and `?` then rewrite, so
/// `**/file.swift` compiled to `^(.[^/]*/).file\.swift$` — a pattern that requires a
/// directory component and matches almost nothing.
///
/// ## Syntax
///
/// - `*` — any run of characters except the path separator
/// - `**` — any run of characters including separators
/// - `**/` — zero or more leading directories
/// - `?` — exactly one character, not a separator
/// - `[abc]`, `[a-z]`, `[!abc]` — a character class, negated with a leading `!`
/// - everything else is literal
public enum GlobPattern {
    /// How a compiled pattern is anchored against a path.
    public enum Anchoring {
        /// The pattern must match the entire path.
        ///
        /// Used where paths are already normalized relative to a known root, so a
        /// pattern means exactly what it says.
        case fullPath

        /// The pattern may match after any number of leading directories.
        ///
        /// Lets `*.swift` match `/src/file.swift`, which is what a user filtering
        /// search results by extension expects.
        case anyDirectoryPrefix
    }

    /// Compiles a glob into a regular expression.
    ///
    /// - Parameters:
    ///   - pattern: The glob pattern.
    ///   - anchoring: Whether an implicit directory prefix is allowed.
    /// - Returns: The compiled expression, or nil if the pattern is malformed.
    public static func compile(_ pattern: String, anchoring: Anchoring) -> NSRegularExpression? {
        guard let source = regex(for: pattern, anchoring: anchoring) else { return nil }
        return try? NSRegularExpression(pattern: source)
    }

    /// Builds the anchored regular-expression source for a glob.
    ///
    /// - Returns: The expression source, or nil when the pattern is malformed — an
    ///   unterminated character class being the only way to write one.
    static func regex(for pattern: String, anchoring: Anchoring) -> String? {
        guard let body = body(of: pattern) else { return nil }

        // A pattern that already begins with `**/` carries its own optional prefix,
        // and one rooted with `/` is explicitly absolute; neither should get another.
        let needsPrefix = anchoring == .anyDirectoryPrefix
            && !pattern.hasPrefix("/")
            && !pattern.hasPrefix("**/")

        return "^" + (needsPrefix ? "(?:.*/)?" : "") + body + "$"
    }

    /// Converts the pattern to regex source, one character at a time.
    private static func body(of pattern: String) -> String? {
        var body = ""
        var index = pattern.startIndex

        while index < pattern.endIndex {
            switch pattern[index] {
            case "*":
                index = appendWildcard(from: pattern, at: index, to: &body)
                continue

            case "?":
                body += "[^/]"

            case "[":
                guard let next = appendCharacterClass(from: pattern, at: index, to: &body) else {
                    return nil
                }
                index = next
                continue

            default:
                // Escaping every literal is what keeps `.` from becoming "any
                // character" and `(`, `+`, `[` from being read as regex syntax.
                body += NSRegularExpression.escapedPattern(for: String(pattern[index]))
            }

            index = pattern.index(after: index)
        }

        return body
    }

    /// Emits a character class and returns the index after its closing bracket.
    ///
    /// - Returns: nil when the class is unterminated, so a malformed pattern is
    ///   reported rather than silently reinterpreted as literal text.
    private static func appendCharacterClass(
        from pattern: String,
        at index: String.Index,
        to body: inout String
    ) -> String.Index? {
        var cursor = pattern.index(after: index)
        var contents = ""
        var negated = false

        // Glob spells negation `!`, regex spells it `^`.
        if cursor < pattern.endIndex, pattern[cursor] == "!" {
            negated = true
            cursor = pattern.index(after: cursor)
        }

        while cursor < pattern.endIndex, pattern[cursor] != "]" {
            let character = pattern[cursor]
            // Ranges pass through; anything with meaning inside a regex class is escaped.
            if character == "-" || character.isLetter || character.isNumber {
                contents.append(character)
            } else {
                contents += "\\" + String(character)
            }
            cursor = pattern.index(after: cursor)
        }

        guard cursor < pattern.endIndex, !contents.isEmpty else { return nil }

        body += "[" + (negated ? "^" : "") + contents + "]"
        return pattern.index(after: cursor)
    }

    /// Emits the regex for `*`, `**` or `**/` and returns the next index to scan.
    private static func appendWildcard(
        from pattern: String,
        at index: String.Index,
        to body: inout String
    ) -> String.Index {
        let next = pattern.index(after: index)

        guard next < pattern.endIndex, pattern[next] == "*" else {
            body += "[^/]*"
            return next
        }

        var after = pattern.index(after: next)

        // `**/` means "zero or more directories", so the separator is part of the
        // optional group — otherwise `**/file.swift` could not match `file.swift`.
        if after < pattern.endIndex, pattern[after] == "/" {
            body += "(?:.*/)?"
            after = pattern.index(after: after)
        } else {
            body += ".*"
        }

        return after
    }
}
