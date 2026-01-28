import Crypto
import Foundation
import Logging

/// Manages Claude Code OAuth authentication flow
///
/// SwiftIndex integrates with Claude Code Pro/Max OAuth tokens:
/// - Automatic: Runs `claude setup-token` subprocess
/// - Manual: Prompts user to paste token from terminal
/// - Validation: Checks token via Anthropic API before saving
///
/// Usage:
/// ```swift
/// // Check CLI availability
/// if await ClaudeCodeAuthManager.isCLIAvailable() {
///     // Automatic flow
///     let token = try await ClaudeCodeAuthManager.setupOAuthToken(manual: false)
/// } else {
///     // Manual fallback
///     let token = try await ClaudeCodeAuthManager.setupOAuthToken(manual: true)
/// }
/// ```
///
/// Token Format:
/// - Pattern: `sk-ant-oauth-[a-zA-Z0-9_-]{20,}`
/// - Example: `sk-ant-oauth-abc123_xyz789-abcdefghijklmnopqrst`
public enum ClaudeCodeAuthManager {
    /// Logger instance for OAuth authentication operations
    private static let logger = Logger(label: "com.swiftindex.oauth")

    /// OAuth token format pattern
    ///
    /// Supports both formats:
    /// - Legacy: `sk-ant-oauth-` followed by 20+ characters
    /// - New:    `sk-ant-oat01-` followed by 20+ characters
    /// Used for both parsing CLI output and validating user input
    private static let tokenPattern = #"sk-ant-oa(uth|t\d+)-[\w-]{20,}"#

    // MARK: - CLI Detection

    /// Check if Claude Code CLI is available in PATH
    ///
    /// - Returns: true if `claude` command exists
    public static func isCLIAvailable() async -> Bool {
        #if os(macOS) || os(Linux)
            do {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
                process.arguments = ["claude"]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()

                try process.run()
                process.waitUntilExit()

                return process.terminationStatus == 0
            } catch {
                // Log the failure - this might indicate system issues beyond "CLI not found"
                logger.debug(
                    "CLI availability check failed",
                    metadata: [
                        "command": .string("claude"),
                        "error": .string(error.localizedDescription),
                    ]
                )
                return false
            }
        #else
            return false
        #endif
    }

    // MARK: - Token Parsing

    /// Parse OAuth token from `claude setup-token` output
    ///
    /// - Parameter output: CLI stdout/stderr combined
    /// - Returns: Extracted OAuth token
    /// - Throws: ClaudeCodeAuthError.parsingFailed if no token found
    ///
    /// Token Extraction Strategy:
    /// 1. Search for pattern: `sk-ant-oauth-[a-zA-Z0-9_-]{20,}`
    /// 2. Multi-line parsing (token can appear on any line)
    /// 3. If multiple matches, use first one
    /// 4. Validate extracted token before returning
    static func parseToken(from output: String) throws -> String {
        let regex = try NSRegularExpression(pattern: tokenPattern, options: [])

        let range = NSRange(output.startIndex ..< output.endIndex, in: output)
        guard let match = regex.firstMatch(in: output, options: [], range: range) else {
            throw ClaudeCodeAuthError.parsingFailed
        }

        let tokenRange = Range(match.range, in: output)!
        let token = String(output[tokenRange])

        // Validate format before returning
        try validateTokenFormat(token)

        return token
    }

    // MARK: - Token Validation

    /// Validate OAuth token format
    ///
    /// - Parameter token: Token string to validate
    /// - Throws: ClaudeCodeAuthError.invalidToken if format invalid
    ///
    /// Format Requirements:
    /// - Prefix: `sk-ant-oauth-` (legacy) or `sk-ant-oat01-` (new)
    /// - Minimum length: 20 characters after prefix
    /// - Allowed characters: alphanumeric, underscore, dash
    public static func validateTokenFormat(_ token: String) throws {
        guard !token.isEmpty else {
            throw ClaudeCodeAuthError.invalidToken
        }

        // Check prefix (supports both legacy and new format)
        guard token.hasPrefix("sk-ant-oa") else {
            throw ClaudeCodeAuthError.invalidToken
        }

        // Check allowed characters and full pattern (with anchors for exact match)
        let pattern = "^" + tokenPattern + "$"
        let regex = try NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(token.startIndex ..< token.endIndex, in: token)
        guard regex.firstMatch(in: token, options: [], range: range) != nil else {
            throw ClaudeCodeAuthError.invalidToken
        }
    }

    // MARK: - Token Management (Keychain Integration)

    /// Get OAuth token from Keychain
    ///
    /// - Returns: OAuth token if available
    /// - Throws: KeychainError if token not found or Keychain locked
    public static func getToken() throws -> String {
        try KeychainManager.getClaudeCodeToken()
    }

    /// Save OAuth token to Keychain
    ///
    /// - Parameter token: OAuth token to save
    /// - Throws: KeychainError if save fails
    public static func saveToken(_ token: String) throws {
        try KeychainManager.saveClaudeCodeToken(token)
    }

    /// Delete OAuth token from Keychain
    ///
    /// - Throws: KeychainError if token not found
    public static func deleteToken() throws {
        try KeychainManager.deleteClaudeCodeToken()
    }

    // MARK: - OAuth Flow (CLI-based)

    #if os(macOS) || os(Linux)

        /// Run automatic OAuth flow via `claude setup-token`
        ///
        /// - Returns: OAuth token
        /// - Throws: ClaudeCodeAuthError if CLI fails or token parsing fails
        ///
        /// Process:
        /// 1. Run `claude setup-token` subprocess
        /// 2. Wait for completion (user authenticates in browser)
        /// 3. Parse token from stdout/stderr
        /// 4. Validate token format
        /// 5. Return token (caller handles Keychain save)
        public static func runAutomaticFlow() async throws -> String {
            // Check CLI availability first
            guard await isCLIAvailable() else {
                throw ClaudeCodeAuthError.cliNotFound
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["claude", "setup-token"]

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            try process.run()

            // Wait for process with timeout (30 seconds - reduced due to IPv6/IPv4 callback issues)
            // If browser auth takes longer, user should use manual mode
            let timeoutSeconds: TimeInterval = 30
            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                if process.isRunning {
                    logger.warning("OAuth flow timed out after \(timeoutSeconds) seconds, terminating process")
                    process.terminate()
                }
            }

            process.waitUntilExit()
            timeoutTask.cancel() // Cancel timeout if process finished

            // Combine stdout and stderr (token may appear in either)
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            let output = (String(data: outputData, encoding: .utf8) ?? "") +
                "\n" +
                (String(data: errorData, encoding: .utf8) ?? "")

            // Check for timeout (process terminated by signal = our SIGTERM from timeout)
            // Known issue: Claude Code CLI may bind callback to IPv6 only
            if process.terminationReason == .uncaughtSignal {
                logger.error(
                    "OAuth flow timeout - likely IPv6 callback issue",
                    metadata: [
                        "error_id": .string("oauth_flow_timeout"),
                        "github_issue": .string("anthropics/claude-code#9376"),
                    ]
                )
                throw ClaudeCodeAuthError.oauthFlowTimeout
            }

            // Check exit code
            guard process.terminationStatus == 0 else {
                let combinedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)

                // Log the full CLI output for debugging
                logger.error(
                    "Claude CLI execution failed",
                    metadata: [
                        "exit_code": .string("\(process.terminationStatus)"),
                        "output": .string(combinedOutput),
                        "error_id": .string("claude_cli_failed"),
                    ]
                )

                throw ClaudeCodeAuthError.cliExecutionFailed(
                    exitCode: process.terminationStatus,
                    output: combinedOutput
                )
            }

            // Parse and validate token
            return try parseToken(from: output)
        }

        /// Alias for `runAutomaticFlow()` for backward compatibility
        public static func setupOAuthToken() async throws -> String {
            try await runAutomaticFlow()
        }

    #endif
}
