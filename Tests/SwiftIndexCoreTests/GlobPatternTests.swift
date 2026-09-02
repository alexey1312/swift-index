import Foundation
@testable import SwiftIndexCore
import Testing

@Suite("GlobPattern Tests")
struct GlobPatternTests {
    private func matches(
        _ path: String,
        _ pattern: String,
        anchoring: GlobPattern.Anchoring = .anyDirectoryPrefix
    ) -> Bool {
        guard let regex = GlobPattern.compile(pattern, anchoring: anchoring) else { return false }
        let range = NSRange(path.startIndex ..< path.endIndex, in: path)
        return regex.firstMatch(in: path, range: range) != nil
    }

    // MARK: - Regression: substitution-order corruption

    @Test("Wildcards introduced by ** are not rewritten again")
    func noSubstitutionCorruption() {
        // The previous implementation applied string substitutions in sequence, so the
        // `.*` emitted for `**/` was rewritten by the later rule for `*`, and the `?`
        // of the optional group by the rule for `?`. `**/file.swift` compiled to
        // `^(.[^/]*/).file\.swift$`, which matched almost nothing.
        #expect(GlobPattern.regex(for: "**/file.swift", anchoring: .fullPath)
            == #"^(?:.*/)?file\.swift$"#)
    }

    @Test("Literal regex metacharacters are escaped")
    func metacharactersEscaped() {
        // A dot must stay a dot, and brackets/parens must not open regex syntax.
        #expect(matches("/src/file.swift", "*.swift"))
        #expect(!matches("/src/fileXswift", "*.swift"))
        #expect(matches("/src/a+b(c).swift", "**/a+b(c).swift"))
    }

    // MARK: - Semantics

    @Test("A single star does not cross path separators")
    func singleStar() {
        #expect(matches("/src/file.swift", "*.swift"))
        #expect(!matches("/src/deep/file.swift", "src/*.swift"))
        #expect(matches("/src/file.swift", "src/*.swift"))
    }

    @Test("A double star crosses path separators")
    func doubleStar() {
        #expect(matches("/src/deep/nested/file.swift", "**/file.swift"))
        #expect(matches("/file.swift", "**/file.swift"))
        #expect(matches("/src/utils/helpers.swift", "**/utils/*.swift"))
        #expect(!matches("/src/models/user.swift", "**/utils/*.swift"))
    }

    @Test("A question mark matches exactly one non-separator character")
    func questionMark() {
        #expect(matches("/src/file1.swift", "/src/file?.swift"))
        #expect(!matches("/src/file10.swift", "/src/file?.swift"))
        #expect(!matches("/src/a/b.swift", "/src/a?b.swift"))
    }

    // MARK: - Character classes

    @Test("Character classes match a set of characters")
    func characterClasses() {
        #expect(matches("/src/file1.swift", "**/file[0-9].swift"))
        #expect(!matches("/src/fileA.swift", "**/file[0-9].swift"))
        #expect(matches("/src/fileA.swift", "**/file[ABC].swift"))
    }

    @Test("A leading ! negates a character class")
    func negatedCharacterClass() {
        #expect(matches("/src/fileA.swift", "**/file[!0-9].swift"))
        #expect(!matches("/src/file1.swift", "**/file[!0-9].swift"))
    }

    @Test("An unterminated character class is rejected")
    func unterminatedClassRejected() {
        // Reported as malformed rather than silently reinterpreted as a literal `[`,
        // so a mistyped pattern surfaces instead of quietly matching nothing.
        #expect(GlobPattern.compile("[invalid", anchoring: .fullPath) == nil)
        #expect(GlobPattern.compile("[]", anchoring: .fullPath) == nil)
    }

    // MARK: - Anchoring

    @Test("fullPath anchoring adds no implicit directory prefix")
    func fullPathAnchoring() {
        // Ignore rules match repo-relative paths, so a pattern means exactly what it
        // says; a lenient prefix would silently widen every rule.
        #expect(matches("file.swift", "*.swift", anchoring: .fullPath))
        #expect(!matches("src/file.swift", "*.swift", anchoring: .fullPath))
        #expect(matches("src/file.swift", "src/*.swift", anchoring: .fullPath))
    }

    @Test("anyDirectoryPrefix lets a bare pattern match at any depth")
    func anyDirectoryPrefixAnchoring() {
        // Search filters run against absolute paths, where users expect "*.swift" to
        // mean "any Swift file".
        #expect(matches("/a/b/c/file.swift", "*.swift"))
        #expect(matches("file.swift", "*.swift"))
    }

    @Test("An absolute pattern stays absolute")
    func absolutePatternNotWidened() {
        #expect(matches("/src/file.swift", "/src/*.swift"))
        // Without the guard, an implicit prefix would let this match at any depth.
        #expect(!matches("/vendor/src/file.swift", "/src/*.swift"))
    }
}
