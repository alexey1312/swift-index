import Foundation
@testable import SwiftIndexCore
import Testing

@Suite("FileCollector and IgnoreRules Tests")
struct FileCollectorTests {
    // MARK: - Harness

    private struct Project {
        let root: URL

        init() throws {
            root = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("swiftindex-collect-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        @discardableResult
        func write(_ relativePath: String, _ contents: String = "func x() {}") throws -> String {
            let url = root.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: url, atomically: true, encoding: .utf8)
            return url.path
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func collect(_ project: Project, config: Config = Config()) throws -> [String] {
        try FileCollector
            .collectFiles(at: project.root.path, config: config, parser: HybridParser())
            .map { FileCollector.relativePath(of: URL(fileURLWithPath: $0), from: project.root.path) }
    }

    // MARK: - Glob patterns (regression: these never matched before)

    @Test("Glob exclude patterns actually match")
    func globPatternsMatch() throws {
        let project = try Project()
        defer { project.cleanup() }

        try project.write("Sources/App.swift")
        try project.write("App.xcodeproj/project.swift")

        let files = try collect(project)

        // `*.xcodeproj` is in the default excludes but could never match under the
        // old `filePath.contains(pattern)` test — no path contains a literal '*'.
        #expect(files.contains("Sources/App.swift"))
        #expect(!files.contains { $0.hasPrefix("App.xcodeproj/") })
    }

    @Test("A project living under a path named like an exclude is still indexed")
    func substringDoesNotExcludeProject() throws {
        let project = try Project()
        defer { project.cleanup() }

        // "Pods" is a default exclude. A file *inside* a Pods directory must be
        // excluded, but a directory merely containing the substring must not be.
        try project.write("Podsfile-helpers/App.swift")
        try project.write("Pods/Vendor.swift")

        let files = try collect(project)

        #expect(files.contains("Podsfile-helpers/App.swift"))
        #expect(!files.contains("Pods/Vendor.swift"))
    }

    // MARK: - .gitignore

    @Test("Root .gitignore excludes matching files")
    func gitignoreRespected() throws {
        let project = try Project()
        defer { project.cleanup() }

        try project.write(".gitignore", "Generated/\n*.tmp.swift\n")
        try project.write("Sources/Real.swift")
        try project.write("Generated/Fake.swift")
        try project.write("Sources/Scratch.tmp.swift")

        let files = try collect(project)

        #expect(files.contains("Sources/Real.swift"))
        #expect(!files.contains("Generated/Fake.swift"))
        #expect(!files.contains("Sources/Scratch.tmp.swift"))
    }

    @Test("Negation re-includes a file excluded by a file pattern")
    func gitignoreNegation() throws {
        let project = try Project()
        defer { project.cleanup() }

        try project.write(".gitignore", "*.gen.swift\n!Keep.gen.swift\n")
        try project.write("Sources/Drop.gen.swift")
        try project.write("Sources/Keep.gen.swift")

        let files = try collect(project)

        #expect(!files.contains("Sources/Drop.gen.swift"))
        #expect(files.contains("Sources/Keep.gen.swift"))
    }

    @Test("Negation cannot resurrect a file under an excluded directory")
    func gitignoreNegationUnderExcludedDirectory() throws {
        let project = try Project()
        defer { project.cleanup() }

        // Matches git: "It is not possible to re-include a file if a parent
        // directory of that file is excluded." Excluded directories are pruned
        // rather than walked, so patterns for files inside them never apply.
        try project.write(".gitignore", "Generated/\n!Generated/Keep.swift\n")
        try project.write("Generated/Drop.swift")
        try project.write("Generated/Keep.swift")

        let files = try collect(project)

        #expect(!files.contains("Generated/Drop.swift"))
        #expect(!files.contains("Generated/Keep.swift"))
    }

    @Test("respect_gitignore = false disables gitignore handling")
    func gitignoreCanBeDisabled() throws {
        let project = try Project()
        defer { project.cleanup() }

        try project.write(".gitignore", "Generated/\n")
        try project.write("Generated/Fake.swift")

        var config = Config()
        config.respectGitignore = false

        let files = try collect(project, config: config)
        #expect(files.contains("Generated/Fake.swift"))
    }

    // MARK: - Size and extension filters

    @Test("Files above max_file_size are skipped")
    func testMaxFileSize() throws {
        let project = try Project()
        defer { project.cleanup() }

        try project.write("Sources/Small.swift")
        try project.write("Sources/Huge.swift", String(repeating: "// padding\n", count: 5000))

        var config = Config()
        config.maxFileSize = 1000

        let files = try collect(project, config: config)
        #expect(files.contains("Sources/Small.swift"))
        #expect(!files.contains("Sources/Huge.swift"))
    }

    @Test("Stat data is populated for change detection")
    func entriesCarryStatData() throws {
        let project = try Project()
        defer { project.cleanup() }
        try project.write("Sources/App.swift", "func app() {}")

        let entries = try FileCollector.collect(
            at: project.root.path,
            config: Config(),
            parser: HybridParser()
        )

        #expect(entries.count == 1)
        #expect(entries[0].size > 0)
        #expect(entries[0].modifiedNanoseconds > 0)
    }

    // MARK: - Glob compilation

    @Test("Glob semantics: * does not cross separators, ** does")
    func globSemantics() {
        func matches(_ pattern: String, _ path: String) -> Bool {
            guard let regex = IgnoreRules.compileGlob(pattern) else { return false }
            let range = NSRange(path.startIndex ..< path.endIndex, in: path)
            return regex.firstMatch(in: path, range: range) != nil
        }

        #expect(matches("*.swift", "file.swift"))
        #expect(!matches("*.swift", "src/file.swift"))
        #expect(matches("**/file.swift", "src/deep/file.swift"))
        #expect(matches("**/file.swift", "file.swift"))
        #expect(matches("**/utils/*.swift", "src/utils/helpers.swift"))
        #expect(!matches("**/utils/*.swift", "src/utils/deep/helpers.swift"))
    }
}
