// MARK: - FileWatcher

import Foundation
import Logging

/// Watches a directory for file changes and reports events.
///
/// Uses FSEvents for efficient file system monitoring on macOS.
/// Supports debouncing to batch rapid changes.
///
/// ## Usage
///
/// ```swift
/// let watcher = FileWatcher(path: "/path/to/project")
/// for await event in watcher.events {
///     switch event {
///     case .created(let path):
///         print("Created: \(path)")
///     case .modified(let path):
///         print("Modified: \(path)")
///     case .deleted(let path):
///         print("Deleted: \(path)")
///     }
/// }
/// ```
public actor FileWatcher {
    // MARK: - Types

    /// Types of file system events.
    public enum Event: Sendable, Equatable {
        case created(String)
        case modified(String)
        case deleted(String)

        /// The path associated with this event.
        public var path: String {
            switch self {
            case let .created(path), let .modified(path), let .deleted(path):
                path
            }
        }
    }

    // MARK: - Properties

    /// The directory being watched.
    public let watchPath: String

    /// Debounce interval in milliseconds.
    public let debounceMs: Int

    /// File extensions to watch (empty means all).
    public let extensions: Set<String>

    /// Paths to exclude from watching.
    public let excludePatterns: [String]

    /// Logger for debugging.
    private let logger: Logger

    /// Whether the watcher is currently active.
    private var isWatching: Bool = false

    /// Whether shutdown has been initiated (prevents new callback tasks).
    private var isShuttingDown: Bool = false

    /// Count of in-flight callback tasks (must reach 0 before releasing stream).
    private var activeCallbackCount: Int = 0

    /// Continuation for coordinated shutdown (resumed when activeCallbackCount reaches 0).
    private var shutdownContinuation: CheckedContinuation<Void, Never>?

    /// Pending events waiting to be debounced.
    private var pendingEvents: [String: Event] = [:]

    /// Task handling debounce.
    private var debounceTask: Task<Void, Never>?

    /// Continuation for the async stream.
    private var eventContinuation: AsyncStream<Event>.Continuation?

    /// The dispatch source for FSEvents.
    private var eventStream: FSEventStreamRef?

    // MARK: - Initialization

    /// Creates a file watcher for the specified directory.
    ///
    /// - Parameters:
    ///   - path: Directory to watch.
    ///   - debounceMs: Time to wait before emitting events. Default is 500.
    ///   - extensions: File extensions to watch. Empty means all.
    ///   - excludePatterns: Paths containing these strings are ignored.
    ///   - logger: Logger for debugging.
    public init(
        path: String,
        debounceMs: Int = 500,
        extensions: Set<String> = [],
        excludePatterns: [String] = [".git", ".build", "DerivedData"],
        logger: Logger = Logger(label: "FileWatcher")
    ) {
        watchPath = (path as NSString).standardizingPath
        self.debounceMs = debounceMs
        self.extensions = extensions
        self.excludePatterns = excludePatterns
        self.logger = logger
    }

    // MARK: - Public Methods

    /// Starts watching and returns an async stream of events.
    ///
    /// - Returns: An async stream of file system events.
    public nonisolated func start() -> AsyncStream<Event> {
        AsyncStream<Event> { continuation in
            Task {
                await self.setupContinuation(continuation)
                await self.startWatching()
            }
        }
    }

    /// Stops watching for file changes.
    ///
    /// This method performs a graceful shutdown:
    /// 1. Signals shutdown to prevent new callback tasks
    /// 2. Waits for in-flight callback tasks to complete
    /// 3. Releases FSEventStream resources safely
    public func stop() async {
        guard isWatching else { return }

        // 1. Signal shutdown - prevents new callback tasks from being created
        isShuttingDown = true
        isWatching = false
        debounceTask?.cancel()
        debounceTask = nil

        // 2. Wait for in-flight callbacks to complete
        if activeCallbackCount > 0 {
            logger.debug("Waiting for \(activeCallbackCount) in-flight callbacks")
            await withCheckedContinuation { continuation in
                shutdownContinuation = continuation
            }
        }

        // 3. Now safe to release stream - no callbacks can access it
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            eventStream = nil
        }

        eventContinuation?.finish()
        eventContinuation = nil

        // Reset shutdown state for potential reuse
        isShuttingDown = false

        logger.info("FileWatcher stopped")
    }

    // MARK: - Private Methods

    private func setupContinuation(_ continuation: AsyncStream<Event>.Continuation) {
        eventContinuation = continuation

        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task {
                await self.stop()
            }
        }
    }

    private func startWatching() {
        guard !isWatching else { return }
        isWatching = true

        logger.info("FileWatcher starting", metadata: [
            "path": "\(watchPath)",
            "debounceMs": "\(debounceMs)",
        ])

        // Use DispatchSource for file monitoring
        startDispatchSourceWatcher()
    }

    private func startDispatchSourceWatcher() {
        // Create FSEventStream callback context
        let callback: FSEventStreamCallback = { _, contextInfo, numEvents, eventPaths, eventFlags, _ in
            guard let contextInfo else { return }

            // Safely extract paths from the C string array
            // eventPaths is UnsafeMutableRawPointer pointing to char** (array of C strings)
            let pathsPtr = eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
            var paths: [String] = []
            paths.reserveCapacity(numEvents)

            for i in 0 ..< numEvents {
                let cString = pathsPtr[i]
                paths.append(String(cString: cString))
            }

            let context = Unmanaged<FileWatcherContext>.fromOpaque(contextInfo).takeUnretainedValue()

            // Check if watcher is still alive
            guard let watcher = context.watcher else { return }

            for i in 0 ..< numEvents {
                let path = paths[i]
                let flags = eventFlags[i]

                Task { [weak watcher] in
                    guard let watcher else { return }

                    // Check shutdown flag before processing - prevents new work during shutdown
                    guard await !watcher.isShuttingDown else { return }

                    // Track this callback task for graceful shutdown
                    await watcher.incrementActiveCount()
                    defer {
                        Task { await watcher.decrementActiveCount() }
                    }

                    await watcher.handleEvent(path: path, flags: flags)
                }
            }
        }

        // Create context
        let context = FileWatcherContext(watcher: self)
        let contextPtr = Unmanaged.passRetained(context).toOpaque()

        let releaseCallback: CFAllocatorReleaseCallBack = { ptr in
            guard let ptr else { return }
            Unmanaged<FileWatcherContext>.fromOpaque(ptr).release()
        }

        var streamContext = FSEventStreamContext(
            version: 0,
            info: contextPtr,
            retain: nil,
            release: releaseCallback,
            copyDescription: nil
        )

        // Create FSEventStream
        let pathsToWatch = [watchPath] as CFArray

        guard let stream = FSEventStreamCreate(
            nil,
            callback,
            &streamContext,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            CFTimeInterval(Double(debounceMs) / 1000.0),
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        ) else {
            logger.error("Failed to create FSEventStream")
            return
        }

        eventStream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(stream)

        logger.info("FSEventStream started")
    }

    private func handleEvent(path: String, flags: FSEventStreamEventFlags) {
        // Check if path should be excluded
        for pattern in excludePatterns {
            if path.contains(pattern) {
                return
            }
        }

        // Check extension filter
        if !extensions.isEmpty {
            let ext = (path as NSString).pathExtension
            if !extensions.contains(ext) {
                return
            }
        }

        // Determine event type
        let event: Event
        if flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0 {
            event = .created(path)
        } else if flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0 {
            event = .deleted(path)
        } else if flags & UInt32(kFSEventStreamEventFlagItemModified) != 0 {
            event = .modified(path)
        } else if flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 {
            // Renamed files appear as both removed and created
            if FileManager.default.fileExists(atPath: path) {
                event = .created(path)
            } else {
                event = .deleted(path)
            }
        } else {
            return
        }

        // Add to pending events (debounce by path)
        pendingEvents[path] = event

        // Schedule debounce flush
        scheduleDebounceFlush()
    }

    private func scheduleDebounceFlush() {
        // Cancel existing task
        debounceTask?.cancel()

        // Schedule new flush
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(debounceMs))

            guard !Task.isCancelled else { return }

            flushPendingEvents()
        }
    }

    private func flushPendingEvents() {
        guard !pendingEvents.isEmpty else { return }

        let events = pendingEvents.values
        pendingEvents.removeAll()

        for event in events {
            eventContinuation?.yield(event)
        }

        logger.debug("Flushed \(events.count) events")
    }

    // MARK: - Shutdown Coordination

    /// Increment the count of active callback tasks.
    private func incrementActiveCount() {
        activeCallbackCount += 1
    }

    /// Decrement the count of active callback tasks.
    /// Resumes shutdown continuation when count reaches zero.
    private func decrementActiveCount() {
        activeCallbackCount -= 1
        if activeCallbackCount == 0, let continuation = shutdownContinuation {
            shutdownContinuation = nil
            continuation.resume()
        }
    }
}

// MARK: - FileWatcherContext

/// Helper class to bridge Swift actor with C callback.
private final class FileWatcherContext: @unchecked Sendable {
    weak var watcher: FileWatcher?

    init(watcher: FileWatcher) {
        self.watcher = watcher
    }
}
