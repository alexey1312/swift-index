// MARK: - Update Checker

import Foundation

// MARK: - Key-Value Store Protocol

/// Protocol for key-value storage operations.
/// Allows dependency injection for testing.
protocol KeyValueStore: Sendable {
    func date(forKey key: String) -> Date?
    func set(_ date: Date, forKey key: String)
    func string(forKey key: String) -> String?
    func set(_ string: String?, forKey key: String)
}

// MARK: - UserDefaults Conformance

/// UserDefaults is thread-safe, so @unchecked Sendable is appropriate.
extension UserDefaults: KeyValueStore, @unchecked @retroactive Sendable {
    func date(forKey key: String) -> Date? {
        object(forKey: key) as? Date
    }

    func set(_ date: Date, forKey key: String) {
        set(date as Any, forKey: key)
    }

    func set(_ string: String?, forKey key: String) {
        if let string {
            set(string as Any, forKey: key)
        } else {
            removeObject(forKey: key)
        }
    }
}

// MARK: - GitHub API Response

/// Response from GitHub releases API.
private struct GitHubRelease: Decodable {
    let tagName: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
    }
}

// MARK: - Update Checker

/// Cache keys for update checker.
private enum CacheKeys {
    static let lastCheckDate = "com.swiftindex.updateChecker.lastCheckDate"
    static let latestVersion = "com.swiftindex.updateChecker.latestVersion"
}

/// Default key-value store.
private let defaultStore: KeyValueStore = UserDefaults.standard

/// Interval between update checks (1 hour).
private let checkInterval: TimeInterval = 3600

/// Checks for available updates from GitHub releases.
///
/// Uses caching to avoid checking on every invocation.
/// Displays a notification if a newer version is available.
/// Silently fails on network errors or timeouts (doesn't block CLI).
///
/// - Parameter store: Key-value store for caching results.
///
/// Example output (TTY):
/// ```
/// ╭──────────────────────────────────────────────────────────────
/// │
/// │   🚀 Update Available: v0.2.0
/// │      Current version: v0.1.0
/// │
/// │   To update:
/// │   brew upgrade swiftindex
/// │   https://github.com/alexey1312/swift-index/releases
/// │
/// ╰──────────────────────────────────────────────────────────────
/// ```
func checkForUpdate(store: KeyValueStore = defaultStore) async {
    let currentVersion = SwiftIndex.configuration.version

    // Skip if running development build
    guard currentVersion != "VERSION_PLACEHOLDER" else {
        return
    }

    // Check cache - skip network request if checked recently
    if let lastCheck = store.date(forKey: CacheKeys.lastCheckDate),
       Date().timeIntervalSince(lastCheck) < checkInterval
    {
        // Use cached version if available
        if let cachedVersion = store.string(forKey: CacheKeys.latestVersion) {
            let normalizedCurrent = normalizeVersion(currentVersion)
            let normalizedLatest = normalizeVersion(cachedVersion)

            if isVersionGreater(normalizedLatest, than: normalizedCurrent) {
                displayUpdateNotification(
                    currentVersion: currentVersion,
                    latestVersion: cachedVersion
                )
            }
        }
        return
    }

    // Fetch latest version from GitHub
    let urlString = "https://api.github.com/repos/alexey1312/swift-index/releases/latest"
    guard let url = URL(string: urlString) else {
        return
    }

    // Configure ephemeral session with 10 second timeout
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 10
    config.timeoutIntervalForResource = 10
    let session = URLSession(configuration: config)

    do {
        let (data, response) = try await session.data(from: url)

        // Check for successful response
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            return
        }

        // Parse response
        let decoder = JSONDecoder()
        let release = try decoder.decode(GitHubRelease.self, from: data)
        let latestVersion = release.tagName

        // Update cache
        store.set(Date(), forKey: CacheKeys.lastCheckDate)
        store.set(latestVersion, forKey: CacheKeys.latestVersion)

        // Compare versions
        let normalizedCurrent = normalizeVersion(currentVersion)
        let normalizedLatest = normalizeVersion(latestVersion)

        guard isVersionGreater(normalizedLatest, than: normalizedCurrent) else {
            return
        }

        // Display update notification
        displayUpdateNotification(
            currentVersion: currentVersion,
            latestVersion: latestVersion
        )
    } catch {
        // Silent fail - don't block CLI on network issues
        return
    }
}

// MARK: - Version Comparison

/// Compares two version arrays lexicographically.
/// Returns true if `lhs` is greater than `rhs`.
private func isVersionGreater(_ lhs: [Int], than rhs: [Int]) -> Bool {
    let maxLength = max(lhs.count, rhs.count)
    for i in 0 ..< maxLength {
        let left = i < lhs.count ? lhs[i] : 0
        let right = i < rhs.count ? rhs[i] : 0
        if left > right { return true }
        if left < right { return false }
    }
    return false
}

/// Normalizes version string for comparison.
/// Handles both "v0.1.0" and "0.1.0" formats.
private func normalizeVersion(_ version: String) -> [Int] {
    let cleaned = version.hasPrefix("v") ? String(version.dropFirst()) : version
    return cleaned.split(separator: ".").compactMap { Int($0) }
}

// MARK: - Notification Display

/// Displays the update notification.
/// Uses box-drawing characters for TTY, plain text otherwise.
private func displayUpdateNotification(currentVersion: String, latestVersion: String) {
    let isTTY = isatty(STDOUT_FILENO) != 0

    if isTTY {
        displayTTYNotification(currentVersion: currentVersion, latestVersion: latestVersion)
    } else {
        displayPlainNotification(currentVersion: currentVersion, latestVersion: latestVersion)
    }
}

/// TTY notification with Unicode box-drawing characters.
private func displayTTYNotification(currentVersion: String, latestVersion: String) {
    let boxWidth = 62
    let topBorder = "╭" + String(repeating: "─", count: boxWidth)
    let bottomBorder = "╰" + String(repeating: "─", count: boxWidth)
    let emptyLine = "│"

    print("")
    print(topBorder)
    print(emptyLine)
    print("│   🚀 Update Available: \(latestVersion)")
    print("│      Current version: \(currentVersion)")
    print(emptyLine)
    print("│   To update:")
    print("│   brew upgrade swiftindex")
    print("│   https://github.com/alexey1312/swift-index/releases")
    print(emptyLine)
    print(bottomBorder)
    print("")
}

/// Plain text notification for non-TTY environments (pipes, CI).
private func displayPlainNotification(currentVersion: String, latestVersion: String) {
    print("")
    print("swiftindex \(latestVersion) is available. You are on \(currentVersion).")
    print("To update: brew upgrade swiftindex")
    print("https://github.com/alexey1312/swift-index/releases")
    print("")
}
