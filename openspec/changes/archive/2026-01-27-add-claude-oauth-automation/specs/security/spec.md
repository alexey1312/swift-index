## ADDED Requirements

### Requirement: Keychain Credential Storage

The system SHALL provide secure storage for OAuth tokens using Keychain through Security.framework on Apple platforms.

The system SHALL use the following Keychain attributes:

- Service: `com.swiftindex.oauth`
- Account: `claude-code-oauth-token`
- Accessibility: `kSecAttrAccessibleWhenUnlocked`

The system SHALL provide operations for:

- Save token to Keychain
- Retrieve token from Keychain
- Delete token from Keychain

**Platform Support:** Apple platforms with Security.framework (macOS, iOS, tvOS, watchOS). Detection via `#if canImport(Security)`. On other platforms (Linux, Windows), the system SHALL gracefully skip Keychain operations and rely on environment variables.

#### Scenario: Save OAuth token

- **WHEN** calling `KeychainManager.saveClaudeCodeToken(token)`
- **THEN** the token is securely stored in macOS Keychain
- **AND** if an existing token exists, it is updated

#### Scenario: Retrieve OAuth token

- **WHEN** calling `KeychainManager.getClaudeCodeToken()`
- **THEN** returns the stored token if it exists
- **OR** returns nil if no token is stored

#### Scenario: Delete OAuth token

- **WHEN** calling `KeychainManager.deleteClaudeCodeToken()`
- **THEN** the token is removed from Keychain
- **AND** no error is raised if token doesn't exist

#### Scenario: Keychain access denied

- **WHEN** Keychain is locked or access is denied
- **THEN** operation throws `KeychainError` with descriptive message
- **AND** error includes instructions to unlock Keychain

#### Scenario: Non-Apple platform

- **WHEN** running on platform without Security.framework (Linux, Windows)
- **THEN** Keychain operations are skipped (compile-time check: `#if canImport(Security)`)
- **AND** system falls back to environment variables
- **AND** `auth` commands show platform-specific help messages

---

### Requirement: Claude Code OAuth Management

The system SHALL provide OAuth token management for Claude Code Pro/Max users.

The system SHALL detect if `claude` CLI is available and use it for automatic token generation.

The system SHALL support manual token input as fallback when CLI is unavailable.

The system SHALL validate tokens before storing by checking Anthropic API availability.

#### Scenario: Check CLI availability

- **WHEN** calling `ClaudeCodeAuthManager.isCLIAvailable()`
- **THEN** returns true if `claude --version` succeeds
- **OR** returns false if command not found

#### Scenario: Automatic OAuth token setup

- **WHEN** calling `ClaudeCodeAuthManager.setupOAuthToken()`
- **AND** `claude` CLI is available
- **THEN** runs `claude setup-token` as subprocess
- **AND** parses token from command output
- **AND** validates token against Anthropic API
- **AND** saves to Keychain if valid
- **AND** returns true on success

#### Scenario: Token parsing failure

- **WHEN** `claude setup-token` output doesn't contain valid token
- **THEN** throws `ClaudeCodeAuthError.tokenParsingFailed`
- **AND** error message suggests manual input

#### Scenario: Token format validation

- **WHEN** calling `ClaudeCodeAuthManager.validateTokenFormat(token)`
- **THEN** validates token matches pattern: `sk-ant-oauth-[\w-]{20,}`
- **AND** checks token has required prefix `sk-ant-oauth-`
- **AND** checks token has minimum 20 characters after prefix
- **AND** throws `ClaudeCodeAuthError.invalidToken` if format invalid
- **NOTE** This is format-only validation, not API validation

#### Scenario: Get stored token

- **WHEN** calling `ClaudeCodeAuthManager.getToken()`
- **THEN** retrieves token from Keychain via `KeychainManager`

#### Scenario: Delete token

- **WHEN** calling `ClaudeCodeAuthManager.deleteToken()`
- **THEN** removes token from Keychain
- **AND** logs deletion for audit trail

---

### Requirement: Authentication Source Priority

The system SHALL check authentication sources in the following priority order (highest to lowest):

1. `SWIFTINDEX_ANTHROPIC_API_KEY` environment variable (explicit project override)
2. `CLAUDE_CODE_OAUTH_TOKEN` environment variable (auto-set by Claude Code CLI)
3. `ANTHROPIC_API_KEY` environment variable (standard API key)
4. Keychain OAuth Token (via `KeychainManager.getClaudeCodeToken()` - managed by SwiftIndex)

The system SHALL use the first available token from the priority chain.

**Rationale:** Environment variables have priority over Keychain to support testing, CI/CD, and project-specific overrides. Keychain serves as a managed fallback for users without explicit env vars.

#### Scenario: Keychain token available (lowest priority)

- **GIVEN** Keychain contains OAuth token "keychain-token"
- **AND** no environment variables are set
- **WHEN** creating Anthropic LLM provider
- **THEN** uses "keychain-token" from Keychain (fallback)

#### Scenario: Environment variable overrides Keychain

- **GIVEN** Keychain contains OAuth token "keychain-token"
- **AND** `SWIFTINDEX_ANTHROPIC_API_KEY=override-key` is set
- **WHEN** creating Anthropic LLM provider
- **THEN** uses "override-key" (env var has priority over Keychain)

#### Scenario: OAuth env var priority

- **GIVEN** Keychain contains OAuth token "keychain-token"
- **AND** `CLAUDE_CODE_OAUTH_TOKEN=oauth-env-token` is set (auto-exported by Claude Code CLI)
- **AND** `ANTHROPIC_API_KEY=api-key` is set
- **AND** `SWIFTINDEX_ANTHROPIC_API_KEY` is not set
- **WHEN** creating Anthropic LLM provider
- **THEN** uses "oauth-env-token" (higher priority than generic API key and Keychain)

#### Scenario: Standard API key priority

- **GIVEN** Keychain contains OAuth token "keychain-token"
- **AND** `ANTHROPIC_API_KEY=api-key` is set
- **AND** `CLAUDE_CODE_OAUTH_TOKEN` is not set
- **AND** `SWIFTINDEX_ANTHROPIC_API_KEY` is not set
- **WHEN** creating Anthropic LLM provider
- **THEN** uses "api-key" (env var has priority over Keychain)

#### Scenario: Fallback to Keychain

- **GIVEN** Keychain contains OAuth token "keychain-token"
- **AND** all environment variables are not set
- **WHEN** creating Anthropic LLM provider
- **THEN** uses "keychain-token" (managed fallback)

#### Scenario: No token available

- **GIVEN** all sources return nil/empty
- **WHEN** attempting to use Anthropic provider
- **THEN** provider initialization fails gracefully
- **AND** shows clear error message with setup instructions
