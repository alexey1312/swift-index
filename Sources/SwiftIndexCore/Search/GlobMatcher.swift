// MARK: - Glob Pattern Matcher with LRU Cache

import Foundation

/// A thread-safe glob pattern matcher with LRU caching of compiled regular expressions.
///
/// `GlobMatcher` caches compiled `NSRegularExpression` patterns to avoid the overhead
/// of repeated compilation. This is particularly beneficial when filtering search results
/// where the same glob pattern is applied to many paths.
///
/// ## Performance
///
/// `NSRegularExpression` compilation costs ~0.1-0.5ms per pattern. For a search returning
/// 100 results, caching eliminates 99 redundant compilations, saving 10-50ms per search.
///
/// ## Usage
///
/// ```swift
/// let matcher = GlobMatcher()
/// let matches = await matcher.matches("/src/foo/bar.swift", pattern: "src/**/*.swift")
/// ```
///
/// ## Supported Patterns
///
/// - `*` - matches any characters except path separator
/// - `**` - matches any characters including path separators (recursive)
/// - `**/` - matches zero or more directories
/// - `?` - matches any single character
/// - `.` - literal dot (escaped automatically)
public actor GlobMatcher {
    /// Cached compiled regular expressions.
    private var cache: [String: NSRegularExpression] = [:]

    /// Access order for LRU eviction (most recently used at the end).
    private var accessOrder: [String] = []

    /// Maximum number of patterns to cache.
    private let maxSize: Int

    /// Creates a new GlobMatcher with the specified cache size.
    ///
    /// - Parameter maxSize: Maximum patterns to cache (default: 100).
    public init(maxSize: Int = 100) {
        self.maxSize = maxSize
    }

    /// Checks if a path matches a glob pattern.
    ///
    /// - Parameters:
    ///   - path: The file path to check.
    ///   - pattern: The glob pattern to match against.
    /// - Returns: `true` if the path matches the pattern.
    public func matches(_ path: String, pattern: String) -> Bool {
        guard let regex = getOrCompile(pattern) else {
            return false
        }
        let range = NSRange(path.startIndex..., in: path)
        return regex.firstMatch(in: path, range: range) != nil
    }

    /// Returns the current number of cached patterns.
    public var cacheCount: Int {
        cache.count
    }

    /// Clears the pattern cache.
    public func clearCache() {
        cache.removeAll()
        accessOrder.removeAll()
    }

    // MARK: - Private

    /// Gets a cached regex or compiles and caches a new one.
    private func getOrCompile(_ pattern: String) -> NSRegularExpression? {
        if let cached = cache[pattern] {
            // Move to end of access order (mark as recently used)
            if let index = accessOrder.firstIndex(of: pattern) {
                accessOrder.remove(at: index)
            }
            accessOrder.append(pattern)
            return cached
        }

        // Convert glob to regex
        let regexPattern = globToRegex(pattern)

        guard let regex = try? NSRegularExpression(pattern: regexPattern) else {
            return nil
        }

        // Evict LRU if at capacity
        if cache.count >= maxSize, let lruKey = accessOrder.first {
            accessOrder.removeFirst()
            cache.removeValue(forKey: lruKey)
        }

        // Cache the new pattern
        cache[pattern] = regex
        accessOrder.append(pattern)

        return regex
    }

    /// Converts a glob pattern to a regular expression.
    private func globToRegex(_ pattern: String) -> String {
        let regexPattern = pattern
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "**/", with: "(.*/)?")
            .replacingOccurrences(of: "**", with: ".*")
            .replacingOccurrences(of: "*", with: "[^/]*")
            .replacingOccurrences(of: "?", with: ".")

        return "^" + regexPattern + "$"
    }
}
