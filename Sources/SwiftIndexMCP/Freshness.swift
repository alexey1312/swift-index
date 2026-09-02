// MARK: - Freshness

import Foundation
import SwiftIndexCore

/// What a session knows about how stale an index is.
public struct StalenessInfo: Sendable, Equatable {
    /// Paths known to differ from what is indexed.
    public var dirtyPaths: Set<String> = []

    /// Files removed from the index during reconciliation.
    public var removedFiles: Int = 0

    /// Files re-indexed during reconciliation.
    public var refreshedFiles: Int = 0

    /// Whether reconciliation deferred work because the delta was too large.
    public var deferredCatchUp: Bool = false

    /// Nothing to report.
    public static let clean = StalenessInfo()

    public var isClean: Bool {
        dirtyPaths.isEmpty && !deferredCatchUp
    }
}

/// Renders staleness compactly for tool output.
///
/// A warning banner per result would be both wasteful and redundant: the model needs
/// one instruction, not twenty. Instead the ranks of affected results are listed, and
/// a clean index costs nothing at all.
public enum StalenessRenderer {
    /// TOON block, or `nil` when the index is fresh.
    public static func toon(_ info: StalenessInfo, resultPaths: [String]) -> String? {
        guard !info.isClean else { return nil }

        let ranks = resultPaths.enumerated()
            .filter { info.dirtyPaths.contains($0.element) }
            .map { String($0.offset + 1) }

        var lines = ["stale{n,ranks,sync}:"]
        lines.append("  \(info.dirtyPaths.count),[\(ranks.joined(separator: ","))],\(info.deferredCatchUp ? 1 : 0)")
        if !ranks.isEmpty {
            lines.append("  \"listed ranks may be outdated — Read those files directly\"")
        }
        return lines.joined(separator: "\n")
    }

    /// Human-readable footer, or `nil` when the index is fresh.
    public static func human(_ info: StalenessInfo, resultPaths: [String]) -> String? {
        guard !info.isClean else { return nil }

        let affected = resultPaths.filter { info.dirtyPaths.contains($0) }.count
        var message = "\n⚠ \(info.dirtyPaths.count) file(s) changed since indexing"
        if affected > 0 {
            message += "; \(affected) result(s) above may be outdated — read those files directly"
        }
        if info.deferredCatchUp {
            message += ". A large change set was deferred; run index_codebase to catch up"
        }
        return message
    }
}
