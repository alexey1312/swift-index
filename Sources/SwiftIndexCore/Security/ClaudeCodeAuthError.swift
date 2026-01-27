import Foundation

/// Errors that can occur during Claude Code OAuth authentication
///
/// SwiftIndex manages OAuth tokens via `claude setup-token` CLI command.
/// This enum covers failure scenarios in the OAuth flow.
public enum ClaudeCodeAuthError: Error, Equatable {
    /// Claude Code CLI not found in PATH
    ///
    /// User must install Claude Code CLI or use manual token input
    case cliNotFound

    /// CLI execution failed (non-zero exit code)
    case cliExecutionFailed(exitCode: Int32, output: String? = nil)

    /// Failed to parse OAuth token from CLI output
    ///
    /// Occurs when:
    /// - Token format changed in new CLI version
    /// - Output doesn't match expected pattern (sk-ant-oauth-...)
    case parsingFailed

    /// Invalid token format
    ///
    /// Token must match pattern: sk-ant-oauth-[a-zA-Z0-9_-]{20,}
    case invalidToken

    /// Token validation failed (Anthropic API returned error)
    case validationFailed(message: String)

    /// Validation timeout (took longer than configured limit)
    case validationTimeout
}

extension ClaudeCodeAuthError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .cliNotFound:
            """
            Claude Code CLI not found. Install it with:
              https://docs.anthropic.com/claude-code/getting-started

            Alternative: Use manual mode with --manual flag
            """

        case let .cliExecutionFailed(exitCode, output):
            if let output, !output.isEmpty {
                """
                Claude CLI execution failed with exit code \(exitCode)

                CLI output:
                \(output)
                """
            } else {
                "Claude CLI execution failed with exit code \(exitCode)"
            }

        case .parsingFailed:
            """
            Failed to parse OAuth token from CLI output.
            Expected format: sk-ant-oauth-...

            Try manual mode: swiftindex auth login --manual
            """

        case .invalidToken:
            """
            Invalid OAuth token format.
            Expected: sk-ant-oauth-[alphanumeric-_]{20,}
            """

        case let .validationFailed(message):
            "Token validation failed: \(message)"

        case .validationTimeout:
            "Token validation timed out after 15 seconds"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .cliNotFound:
            "Install Claude Code CLI or use --manual mode"

        case .cliExecutionFailed:
            "Check Claude CLI installation and permissions"

        case .parsingFailed:
            "Use manual mode to input token directly"

        case .invalidToken:
            "Generate new token with: claude setup-token"

        case .validationFailed:
            "Check API key validity and network connectivity"

        case .validationTimeout:
            "Check network connectivity and retry"
        }
    }
}
