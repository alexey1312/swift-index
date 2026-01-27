// MARK: - Index Command Helper Types

import Foundation
import Logging
import Noora
import SwiftIndexCore

// MARK: - Indexing Context

struct IndexingContext: Sendable {
    let indexManager: IndexManager
    let parser: HybridParser
    let embeddingBatcher: EmbeddingBatcher
    let descriptionGenerator: DescriptionGenerator?
    let descriptionState: DescriptionGenerationState
    let descriptionProgress: DescriptionProgressCallback?
    let projectPath: String
    let logger: Logger
}

// MARK: - Progress Rendering

final class StickyProgressRenderer: Rendering, @unchecked Sendable {
    private let renderer = Renderer()
    private let terminal: Terminaling
    private let lock = NSLock()
    private var lastProgressLine: String?

    init(terminal: Terminaling) {
        self.terminal = terminal
    }

    func render(_ input: String, standardPipeline: StandardPipelining) {
        lock.lock()
        lastProgressLine = input
        renderer.render(input, standardPipeline: standardPipeline)
        lock.unlock()
    }

    func log(_ line: String, standardPipeline: StandardPipelining) {
        lock.lock()
        if terminal.isInteractive, lastProgressLine != nil {
            renderer.render("", standardPipeline: standardPipeline)
        }
        standardPipeline.write(content: line + "\n")
        if terminal.isInteractive, let lastProgressLine {
            renderer.render(lastProgressLine, standardPipeline: standardPipeline)
        }
        lock.unlock()
    }
}

// MARK: - Progress Log Handler

struct ProgressLogHandler: LogHandler, @unchecked Sendable {
    private let label: String
    private let progressRenderer: StickyProgressRenderer
    private let terminal: Terminaling
    private let dateFormatter: DateFormatter
    private let dateLock = NSLock()

    var logLevel: Logger.Level = .info
    var metadata: Logger.Metadata = [:]

    init(label: String, progressRenderer: StickyProgressRenderer, terminal: Terminaling) {
        self.label = label
        self.progressRenderer = progressRenderer
        self.terminal = terminal
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        dateFormatter = formatter
    }

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    // swiftlint:disable:next function_parameter_count
    func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        guard level >= logLevel else { return }

        dateLock.lock()
        let timestamp = dateFormatter.string(from: Date())
        dateLock.unlock()
        var rendered = "\(timestamp) \(level) \(label): \(message)"

        let combinedMetadata = self.metadata.merging(metadata ?? [:]) { _, new in new }
        if !combinedMetadata.isEmpty {
            let meta = combinedMetadata
                .map { "\($0.key)=\($0.value)" }
                .sorted()
                .joined(separator: " ")
            rendered += " \(meta)"
        }
        let pipeline: StandardPipelining = terminal.isInteractive ? StandardOutputPipeline() : StandardErrorPipeline()
        progressRenderer.log(rendered, standardPipeline: pipeline)
    }
}

// MARK: - Description Generation State

actor DescriptionGenerationState {
    private var isEnabled = true

    func disable(reason _: String) -> Bool {
        guard isEnabled else { return false }
        isEnabled = false
        return true
    }

    func isActive() -> Bool { isEnabled }
}

// MARK: - Indexing Statistics

struct IndexingStats: Sendable {
    var filesProcessed: Int = 0
    var filesSkipped: Int = 0
    var chunksIndexed: Int = 0
    var chunksReused: Int = 0
    var snippetsIndexed: Int = 0
    var descriptionsGenerated: Int = 0
    var errors: Int = 0
}

/// Thread-safe wrapper for indexing statistics during parallel processing.
final class AtomicIndexingStats: @unchecked Sendable {
    private let lock = NSLock()
    private var _filesProcessed: Int = 0
    private var _filesSkipped: Int = 0
    private var _chunksIndexed: Int = 0
    private var _chunksReused: Int = 0
    private var _snippetsIndexed: Int = 0
    private var _descriptionsGenerated: Int = 0
    private var _errors: Int = 0

    var filesProcessed: Int {
        lock.lock()
        defer { lock.unlock() }
        return _filesProcessed
    }

    var filesSkipped: Int {
        lock.lock()
        defer { lock.unlock() }
        return _filesSkipped
    }

    var chunksIndexed: Int {
        lock.lock()
        defer { lock.unlock() }
        return _chunksIndexed
    }

    var chunksReused: Int {
        lock.lock()
        defer { lock.unlock() }
        return _chunksReused
    }

    var snippetsIndexed: Int {
        lock.lock()
        defer { lock.unlock() }
        return _snippetsIndexed
    }

    var descriptionsGenerated: Int {
        lock.lock()
        defer { lock.unlock() }
        return _descriptionsGenerated
    }

    var errors: Int {
        lock.lock()
        defer { lock.unlock() }
        return _errors
    }

    func incrementFilesProcessed() {
        lock.lock()
        _filesProcessed += 1
        lock.unlock()
    }

    func incrementFilesSkipped() {
        lock.lock()
        _filesSkipped += 1
        lock.unlock()
    }

    func addChunksIndexed(_ count: Int) {
        lock.lock()
        _chunksIndexed += count
        lock.unlock()
    }

    func addChunksReused(_ count: Int) {
        lock.lock()
        _chunksReused += count
        lock.unlock()
    }

    func addSnippetsIndexed(_ count: Int) {
        lock.lock()
        _snippetsIndexed += count
        lock.unlock()
    }

    func addDescriptionsGenerated(_ count: Int) {
        lock.lock()
        _descriptionsGenerated += count
        lock.unlock()
    }

    func incrementErrors() {
        lock.lock()
        _errors += 1
        lock.unlock()
    }

    func snapshot() -> IndexingStats {
        lock.lock()
        defer { lock.unlock() }
        return IndexingStats(
            filesProcessed: _filesProcessed,
            filesSkipped: _filesSkipped,
            chunksIndexed: _chunksIndexed,
            chunksReused: _chunksReused,
            snippetsIndexed: _snippetsIndexed,
            descriptionsGenerated: _descriptionsGenerated,
            errors: _errors
        )
    }
}

// MARK: - File Index Result

struct FileIndexResult: Sendable {
    let chunksIndexed: Int
    let chunksReused: Int
    let snippetsIndexed: Int
    let descriptionsGenerated: Int
    let skipped: Bool

    init(
        chunksIndexed: Int,
        chunksReused: Int,
        snippetsIndexed: Int = 0,
        descriptionsGenerated: Int = 0,
        skipped: Bool
    ) {
        self.chunksIndexed = chunksIndexed
        self.chunksReused = chunksReused
        self.snippetsIndexed = snippetsIndexed
        self.descriptionsGenerated = descriptionsGenerated
        self.skipped = skipped
    }
}
