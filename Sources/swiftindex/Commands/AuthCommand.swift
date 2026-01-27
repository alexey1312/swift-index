// MARK: - Auth Command

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

        Platform support: Apple platforms with Security.framework
        (macOS, iOS, tvOS, watchOS). Other platforms use environment
        variables only.
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

            #if canImport(Security)
                try runOnApplePlatforms(logger: logger)
            #else
                try runOnNonApplePlatforms()
            #endif
        }

        #if canImport(Security)
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
                    if let keychainToken = try? KeychainManager.getClaudeCodeToken() {
                        activeSource = "Keychain"
                        activeToken = keychainToken
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
        #endif

        private func runOnNonApplePlatforms() throws {
            print("Authentication Status")
            print("─────────────────────\n")
            print("⚠️  Keychain authentication not available on this platform")
            print("\nSupported platforms: macOS, iOS, tvOS, watchOS")
            print("Current platform: \(platformName())")
            print("\nUse environment variables instead:")
            print("  export ANTHROPIC_API_KEY=your-api-key")
            print("  export CLAUDE_CODE_OAUTH_TOKEN=your-oauth-token")
        }

        private func tokenPreview(_ token: String) -> String {
            let prefixLength = min(10, token.count)
            return String(token.prefix(prefixLength)) + "***"
        }

        private func platformName() -> String {
            #if os(Linux)
                return "Linux"
            #elseif os(Windows)
                return "Windows"
            #else
                return "Unknown"
            #endif
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

            By default, this command runs the automatic OAuth flow:
              1. Checks if 'claude' CLI is installed
              2. Runs 'claude setup-token' to generate OAuth token
              3. Validates the token format
              4. Stores token in Keychain

            Use --manual flag to manually enter a token (useful when
            'claude' CLI is unavailable or in non-interactive environments).

            Use --force to overwrite existing tokens.
            """
        )

        @Flag(
            name: .shortAndLong,
            help: "Overwrite existing token without prompting"
        )
        var force: Bool = false

        @Flag(
            name: .long,
            help: "Manual token input mode (skip automatic OAuth flow)"
        )
        var manual: Bool = false

        @Flag(
            name: .shortAndLong,
            help: "Enable verbose debug output"
        )
        var verbose: Bool = false

        mutating func run() async throws {
            let logger = CLIUtils.makeLogger(verbose: verbose)
            let ui = Noora()

            #if canImport(Security)
                try await runOnApplePlatforms(logger: logger, ui: ui)
            #else
                try runOnNonApplePlatforms()
            #endif
        }

        #if canImport(Security)
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

                var token: String?

                // Manual mode or automatic fallback
                if manual {
                    token = try await manualTokenInput(ui: ui)
                } else {
                    // Try automatic flow first
                    if await ClaudeCodeAuthManager.isCLIAvailable() {
                        print("Running automatic OAuth flow...")
                        print("A browser window will open for authentication.\n")

                        do {
                            token = try await ClaudeCodeAuthManager.setupOAuthToken()
                            print("✓ OAuth token generated successfully")
                        } catch {
                            print("✗ Automatic flow failed: \(error.localizedDescription)")

                            // Fallback to manual
                            if ui.yesOrNoChoicePrompt(
                                question: "Try manual token input?",
                                defaultAnswer: true
                            ) {
                                token = try await manualTokenInput(ui: ui)
                            } else {
                                throw ExitCode.failure
                            }
                        }
                    } else {
                        print("⚠️  'claude' CLI not found")
                        print("\nTo install Claude Code CLI:")
                        print("  npm install -g @anthropic-ai/claude-code")
                        print("\nOr use manual mode:")
                        print("  swiftindex auth login --manual\n")

                        if ui.yesOrNoChoicePrompt(
                            question: "Continue with manual token input?",
                            defaultAnswer: true
                        ) {
                            token = try await manualTokenInput(ui: ui)
                        } else {
                            throw ExitCode.failure
                        }
                    }
                }

                guard let finalToken = token else {
                    print("✗ No token provided")
                    throw ExitCode.failure
                }

                // Validate token format
                print("\nValidating token format...")
                do {
                    try ClaudeCodeAuthManager.validateTokenFormat(finalToken)
                    print("✓ Token format is valid")
                } catch {
                    print("✗ Validation failed: \(error.localizedDescription)")
                    print("\nThe token format is invalid. Please check and try again.")
                    throw ExitCode.failure
                }

                // Save token
                do {
                    try? ClaudeCodeAuthManager.deleteToken() // Clear old token first
                    try ClaudeCodeAuthManager.saveToken(finalToken)
                    print("✓ Token saved successfully")
                    print("\nAuthentication complete! You can now use search enhancement features.")
                } catch {
                    print("✗ Failed to save token: \(error.localizedDescription)")
                    throw ExitCode.failure
                }
            }
        #endif

        private func runOnNonApplePlatforms() throws {
            print("Claude Code OAuth Login")
            print("───────────────────────\n")
            print("⚠️  Keychain authentication not available on this platform")
            print("\nSupported platforms: macOS, iOS, tvOS, watchOS")
            print("\nUse environment variables instead:")
            print("  1. Run: claude setup-token")
            print("  2. Copy the generated token")
            print("  3. Set: export CLAUDE_CODE_OAUTH_TOKEN=<token>")
        }

        #if canImport(Security)
            private func manualTokenInput(ui: Noora) async throws -> String {
                print("\nManual Token Input")
                print("──────────────────")
                print("1. Run: claude setup-token")
                print("2. Copy the generated OAuth token")
                print("3. Paste it below\n")

                let token = ui.textPrompt(
                    title: nil,
                    prompt: "OAuth Token",
                    description: "Paste your Claude Code OAuth token",
                    collapseOnAnswer: true,
                    renderer: Renderer(),
                    validationRules: []
                )
                return token
            }
        #endif

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

            #if canImport(Security)
                try runOnApplePlatforms(logger: logger)
            #else
                try runOnNonApplePlatforms()
            #endif
        }

        #if canImport(Security)
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
        #endif

        private func runOnNonApplePlatforms() throws {
            print("⚠️  Keychain authentication not available on this platform")
            print("\nTo clear credentials, unset environment variables:")
            print("  unset ANTHROPIC_API_KEY")
            print("  unset CLAUDE_CODE_OAUTH_TOKEN")
        }
    }
}
