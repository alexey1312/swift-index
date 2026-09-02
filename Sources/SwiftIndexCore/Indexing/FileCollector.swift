// MARK: - FileCollector

import Foundation
import Logging

/// A file discovered during collection, with the stat data needed for change detection.
public struct FileEntry: Sendable, Equatable {
    public let path: String
    public let size: Int64
    public let modifiedNanoseconds: Int64

    public init(path: String, size: Int64, modifiedNanoseconds: Int64) {
        self.path = path
        self.size = size
        self.modifiedNanoseconds = modifiedNanoseconds
    }
}

/// Walks a project and returns the files that should be indexed.
///
/// This is the single implementation. It previously existed in three copies — the CLI
/// indexer, the MCP `index_codebase` tool and the file watcher — which meant the
/// watcher and the indexer could disagree about which files were in scope, so a file
/// the watcher fired on might never be indexed (and vice versa).
public enum FileCollector {
    /// Collects indexable files under `path`.
    ///
    /// Excluded *directories* are pruned rather than walked and filtered per file, so
    /// large build trees such as `.build/` cost one check instead of thousands.
    ///
    /// - Parameters:
    ///   - path: Project root.
    ///   - config: Effective configuration.
    ///   - parser: Parser used to decide which extensions are indexable.
    ///   - logger: Logger for diagnostics.
    /// - Returns: Sorted entries with size and modification time.
    public static func collect(
        at path: String,
        config: Config,
        parser: HybridParser,
        logger: Logger = Logger(label: "FileCollector")
    ) throws -> [FileEntry] {
        let root = URL(fileURLWithPath: path).standardizedFileURL
        let rootPath = root.path
        let rules = IgnoreRules(
            patterns: config.excludePatterns,
            rootPath: rootPath,
            respectGitignore: config.respectGitignore
        )

        let allowedExtensions = indexableExtensions(config: config, parser: parser)

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isDirectoryKey,
                .fileSizeKey,
                .contentModificationDateKey,
            ],
            options: [.skipsHiddenFiles]
        ) else {
            throw ParseError.parsingFailed("Could not enumerate directory: \(path)")
        }

        var entries: [FileEntry] = []

        for case let url as URL in enumerator {
            let relative = Self.relativePath(of: url, from: rootPath)
            guard !relative.isEmpty else { continue }

            let values = try? url.resourceValues(forKeys: [
                .isRegularFileKey,
                .isDirectoryKey,
                .fileSizeKey,
                .contentModificationDateKey,
            ])

            if values?.isDirectory == true {
                if rules.isIgnored(relativePath: relative, isDirectory: true) {
                    // Prune: never descend into an excluded tree.
                    enumerator.skipDescendants()
                }
                continue
            }

            guard values?.isRegularFile == true else { continue }
            if rules.isIgnored(relativePath: relative, isDirectory: false) {
                continue
            }

            let ext = url.pathExtension.lowercased()
            guard allowedExtensions.contains(ext) else { continue }

            let size = Int64(values?.fileSize ?? 0)
            if size > Int64(config.maxFileSize) {
                logger.debug("Skipping large file: \(url.path) (\(size) bytes)")
                continue
            }

            entries.append(FileEntry(
                path: url.path,
                size: size,
                modifiedNanoseconds: Self.nanoseconds(from: values?.contentModificationDate)
            ))
        }

        return entries.sorted { $0.path < $1.path }
    }

    /// Convenience wrapper returning paths only.
    public static func collectFiles(
        at path: String,
        config: Config,
        parser: HybridParser,
        logger: Logger = Logger(label: "FileCollector")
    ) throws -> [String] {
        try collect(at: path, config: config, parser: parser, logger: logger).map(\.path)
    }

    /// The extension set that both the indexer and the watcher should use.
    ///
    /// `config.includeExtensions` is empty by default, which means "everything the
    /// parser supports" rather than "every file on disk".
    public static func indexableExtensions(config: Config, parser: HybridParser) -> Set<String> {
        let configured = Set(
            config.includeExtensions
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased() }
                .filter { !$0.isEmpty }
        )
        return configured.isEmpty ? parser.supportedExtensions : configured
    }

    // MARK: - Helpers

    /// Path of `url` relative to the project root.
    static func relativePath(of url: URL, from rootPath: String) -> String {
        let standardized = url.standardizedFileURL.path
        guard standardized.hasPrefix(rootPath) else { return standardized }
        let trimmed = standardized.dropFirst(rootPath.count)
        return String(trimmed.drop(while: { $0 == "/" }))
    }

    /// Modification time in nanoseconds.
    ///
    /// APFS timestamps are nanosecond-resolution; rounding to seconds would make a
    /// stat-based change check report false positives on stable files.
    static func nanoseconds(from date: Date?) -> Int64 {
        guard let date else { return 0 }
        return Int64((date.timeIntervalSince1970 * 1_000_000_000).rounded())
    }
}
