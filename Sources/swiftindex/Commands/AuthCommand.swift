// MARK: - Auth Command

import AppKit
import ArgumentParser
import Foundation
import Logging
import Noora
import SwiftIndexCore

/// Command to manage Claude Code OAuth authentication.
///
/// Usage:
///   swiftindex auth status       Check authentication status
///   swiftindex auth login        Authenticate with Claude Code
///   swiftindex auth logout       Remove stored credentials
struct AuthCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "auth",
        abstract: "Manage Claude Code OAuth authentication",
        discussion: """
        Manage OAuth tokens for Claude Code integration with SwiftIndex.

        Subcommands:
          status  - Show authentication status and token source
          login   - Authenticate and store OAuth token in Keychain
          logout  - Remove stored OAuth token

        OAuth tokens are stored securely in macOS Keychain and used
        automatically for search enhancement features (query expansion,
        result synthesis).

        Authentication priority (highest to lowest):
          1. SWIFTINDEX_ANTHROPIC_API_KEY (env var, project-specific)
          2. CLAUDE_CODE_OAUTH_TOKEN (env var, auto-set by Claude Code CLI)
          3. ANTHROPIC_API_KEY (env var, standard API key)
          4. Keychain OAuth Token (managed via 'auth' commands)
        """,
        subcommands: [
            StatusCommand.self,
            LoginCommand.self,
            LogoutCommand.self,
        ]
    )
}

// MARK: - Status Subcommand

extension AuthCommand {
    struct StatusCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Show authentication status",
            discussion: """
            Displays the current authentication status including:
            - Whether an OAuth token is stored in Keychain
            - Token preview (first 10 characters)
            - Active authentication source (Keychain vs environment variables)
            - Token format validation

            This command helps troubleshoot authentication issues and
            verify which credentials are being used for API calls.
            """
        )

        @Flag(
            name: .shortAndLong,
            help: "Enable verbose debug output"
        )
        var verbose: Bool = false

        @Flag(
            name: .long,
            help: "Validate token format (does not test API connectivity)"
        )
        var validate: Bool = false

        mutating func run() async throws {
            let logger = CLIUtils.makeLogger(verbose: verbose)
            try runOnApplePlatforms(logger: logger)
        }

        private func runOnApplePlatforms(logger: Logger) throws {
            print("Authentication Status")
            print("─────────────────────\n")

            // Check environment variables first (higher priority)
            let envSources = [
                (
                    "SWIFTINDEX_ANTHROPIC_API_KEY",
                    ProcessInfo.processInfo.environment["SWIFTINDEX_ANTHROPIC_API_KEY"]
                ),
                ("CLAUDE_CODE_OAUTH_TOKEN", ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"]),
                ("ANTHROPIC_API_KEY", ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]),
            ]

            var activeSource: String?
            var activeToken: String?

            for (name, value) in envSources {
                if let token = value, !token.isEmpty {
                    activeSource = name
                    activeToken = token
                    break
                }
            }

            // Check Keychain if no env vars
            if activeSource == nil {
                do {
                    let keychainToken = try KeychainManager.getClaudeCodeToken()
                    activeSource = "Keychain"
                    activeToken = keychainToken
                } catch KeychainError.notFound {
                    // Expected - no token stored
                } catch KeychainError.keychainLocked {
                    print("⚠️  Keychain Status: Locked")
                    print("\nUnlock Keychain to check token status:")
                    print("  security unlock-keychain ~/Library/Keychains/login.keychain-db\n")
                } catch {
                    print("⚠️  Failed to check Keychain: \(error.localizedDescription)\n")
                }
            }

            // Display results
            if let source = activeSource, let token = activeToken {
                print("✓ Authenticated")
                print("  Source: \(source)")
                print("  Token:  \(tokenPreview(token))")

                // Validate if requested
                if validate {
                    print("\nValidating token format...")
                    do {
                        try ClaudeCodeAuthManager.validateTokenFormat(token)
                        print("✓ Token format is valid")
                    } catch {
                        print("✗ Token format validation failed: \(error.localizedDescription)")
                    }
                }
            } else {
                print("✗ Not authenticated")
                print("\nNo OAuth token found in Keychain or environment variables.")
                print("\nTo authenticate, run:")
                print("  swiftindex auth login")
                print("\nOr set environment variable:")
                print("  export ANTHROPIC_API_KEY=your-api-key")
            }
        }

        private func tokenPreview(_ token: String) -> String {
            let prefixLength = min(10, token.count)
            return String(token.prefix(prefixLength)) + "***"
        }
    }
}

// MARK: - Login Subcommand

extension AuthCommand {
    struct LoginCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "login",
            abstract: "Authenticate with Claude Code OAuth",
            discussion: """
            Authenticates with Claude Code and stores the OAuth token
            securely in macOS Keychain.

            Steps to get your token:
              1. Open a NEW terminal window
              2. Run: claude setup-token
              3. Authorize in browser
              4. Copy the token (sk-ant-oauth-...) from CLI output
              5. Paste here when prompted

            Known issue: 'claude setup-token' callback may hang due to
            IPv6/IPv4 mismatch (github.com/anthropics/claude-code/issues/9376).
            Run it in a separate terminal and copy the token manually.

            Use --force to overwrite existing tokens.
            """
        )

        @Flag(
            name: .shortAndLong,
            help: "Overwrite existing token without prompting"
        )
        var force: Bool = false

        @Flag(
            name: .shortAndLong,
            help: "Enable verbose debug output"
        )
        var verbose: Bool = false

        mutating func run() async throws {
            let logger = CLIUtils.makeLogger(verbose: verbose)
            let ui = Noora()
            try await runOnApplePlatforms(logger: logger, ui: ui)
        }

        private func runOnApplePlatforms(logger: Logger, ui: Noora) async throws {
            print("Claude Code OAuth Login")
            print("───────────────────────\n")

            // Check for existing token
            if let existingToken = try? ClaudeCodeAuthManager.getToken(), !force {
                print("✓ Already authenticated")
                print("  Token: \(tokenPreview(existingToken))")
                print("\nTo replace token, use --force flag:")
                print("  swiftindex auth login --force")
                return
            }

            // Check CLI availability
            guard await ClaudeCodeAuthManager.isCLIAvailable() else {
                print("⚠️  'claude' CLI not found")
                print("\nTo install Claude Code CLI:")
                print("  npm install -g @anthropic-ai/claude-code")
                throw ExitCode.failure
            }

            // Manual flow is default due to IPv6/IPv4 callback issues
            print("To get your OAuth token:")
            print("")
            print("  1. Open a NEW terminal window")
            print("  2. Run: claude setup-token")
            print("  3. Authorize in browser")
            print("  4. Copy the token (sk-ant-oauth-...) from CLI output")
            print("")
            print("If callback hangs, see: github.com/anthropics/claude-code/issues/9376")
            print("")

            let token = ui.textPrompt(
                title: nil,
                prompt: "OAuth Token",
                description: "Paste your token here",
                collapseOnAnswer: true,
                renderer: Renderer(),
                validationRules: [NonEmptyValidationRule(error: "Token cannot be empty")]
            )

            // Validate token format
            print("\nValidating token format...")
            do {
                try ClaudeCodeAuthManager.validateTokenFormat(token)
                print("✓ Token format is valid")
            } catch {
                print("✗ Validation failed: \(error.localizedDescription)")
                throw ExitCode.failure
            }

            // Save token
            try saveToken(token, logger: logger)
        }

        private func saveToken(_ token: String, logger: Logger) throws {
            // Clear old token first (if exists)
            do {
                try ClaudeCodeAuthManager.deleteToken()
            } catch KeychainError.notFound {
                // Expected - no old token to delete
            } catch KeychainError.keychainLocked {
                print("✗ Keychain is locked. Cannot save token.")
                print("\nUnlock Keychain with:")
                print("  security unlock-keychain ~/Library/Keychains/login.keychain-db")
                throw ExitCode.failure
            } catch {
                // Log but continue - old token might still be overwritten
                logger.warning("Failed to delete old token: \(error.localizedDescription)")
            }

            do {
                try ClaudeCodeAuthManager.saveToken(token)
                print("✓ Token saved successfully")
                print("\nAuthentication complete! You can now use search enhancement features.")
            } catch KeychainError.keychainLocked {
                print("✗ Keychain is locked. Cannot save token.")
                print("\nUnlock Keychain with:")
                print("  security unlock-keychain ~/Library/Keychains/login.keychain-db")
                throw ExitCode.failure
            } catch {
                print("✗ Failed to save token: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }

        private func tokenPreview(_ token: String) -> String {
            let prefixLength = min(10, token.count)
            return String(token.prefix(prefixLength)) + "***"
        }
    }
}

// MARK: - Logout Subcommand

extension AuthCommand {
    struct LogoutCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "logout",
            abstract: "Remove stored OAuth token",
            discussion: """
            Removes the OAuth token from macOS Keychain.

            This command is idempotent - it will not fail if no token
            is currently stored.

            After logout, you can authenticate again using:
              swiftindex auth login

            Or configure environment variables:
              export ANTHROPIC_API_KEY=your-api-key
            """
        )

        @Flag(
            name: .shortAndLong,
            help: "Enable verbose debug output"
        )
        var verbose: Bool = false

        mutating func run() async throws {
            let logger = CLIUtils.makeLogger(verbose: verbose)
            try runOnApplePlatforms(logger: logger)
        }

        private func runOnApplePlatforms(logger: Logger) throws {
            print("Logging out...")

            do {
                try ClaudeCodeAuthManager.deleteToken()
                print("✓ OAuth token removed from Keychain")
                print("\nYou can authenticate again using:")
                print("  swiftindex auth login")
            } catch KeychainError.notFound {
                // Idempotent - not an error if token doesn't exist
                print("✓ No token to remove (already logged out)")
            } catch {
                print("✗ Failed to remove token: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }
    }
}
