import Foundation
import Logging
import NIOPosix

/// Manages graceful shutdown by listening for POSIX signals.
///
/// Ensures that long-running tasks (like indexing or MCP server)
/// can flush buffers and release resources before the process terminates.
public actor GracefulShutdownManager {
    // MARK: - Properties

    private var isShuttingDown = false
    private let logger: Logger
    private var cancellationHandlers: [() -> Void] = []

    // MARK: - Initialization

    public init(logger: Logger) {
        self.logger = logger
    }

    // MARK: - Public API

    /// Starts listening for SIGINT and SIGTERM signals.
    public func start() {
        Task { [weak self] in
            let signalStream = AsyncStream<Int32> { continuation in
                let signalQueue = DispatchQueue(label: "com.swiftindex.signals")
                let signals = [SIGINT, SIGTERM]

                for sig in signals {
                    // Ignore the default signal behavior
                    signal(sig, SIG_IGN)

                    let source = DispatchSource.makeSignalSource(signal: sig, queue: signalQueue)
                    source.setEventHandler {
                        continuation.yield(sig)
                    }
                    source.resume()
                }
            }

            for await sig in signalStream {
                await self?.handleSignal(sig)
            }
        }
    }

    /// Registers a handler to be called when shutdown is initiated.
    public func onShutdown(_ handler: @escaping @Sendable () -> Void) {
        cancellationHandlers.append(handler)
    }

    /// Returns whether a shutdown is currently in progress.
    public func shouldExit() -> Bool {
        isShuttingDown
    }

    // MARK: - Private Helpers

    private func handleSignal(_ sig: Int32) {
        guard !isShuttingDown else { return }
        isShuttingDown = true

        let signalName = sig == SIGINT ? "SIGINT (Ctrl+C)" : "SIGTERM"
        logger.info("Received \(signalName), initiating graceful shutdown...")

        // Execute all registered cancellation handlers
        for handler in cancellationHandlers {
            handler()
        }

        // If we're still running after a grace period, force exit
        Task {
            try? await Task.sleep(nanoseconds: 5 * 1_000_000_000) // 5 seconds
            logger.warning("Graceful shutdown timed out, forcing exit")
            exit(128 + sig)
        }
    }
}
