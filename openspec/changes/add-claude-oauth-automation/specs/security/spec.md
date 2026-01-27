## ADDED Requirements

### Requirement: Keychain Credential Storage

The system SHALL provide secure storage for OAuth tokens using macOS Keychain through Security.framework.

The system SHALL use the following Keychain attributes:

- Service: `com.swiftindex.oauth`
- Account: `claude-code-oauth-token`
- Accessibility: `kSecAttrAccessibleWhenUnlocked`

The system SHALL provide operations for:

- Save token to Keychain
- Retrieve token from Keychain
- Delete token from Keychain

**Platform Support:** macOS only. On non-macOS platforms, the system SHALL gracefully skip Keychain operations and rely on environment variables.

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

#### Scenario: Non-macOS platform

- **WHEN** running on Linux or Windows
- **THEN** Keychain operations are skipped
- **AND** system falls back to environment variables

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

#### Scenario: Token validation

- **WHEN** calling `ClaudeCodeAuthManager.validateToken(token)`
- **THEN** creates test `AnthropicLLMProvider` with token
- **AND** calls `isAvailable()` to check API access
- **AND** returns true if API responds successfully
- **OR** returns false if API returns 401/403 or times out

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

1. Keychain OAuth Token (via `KeychainManager.getClaudeCodeToken()`)
2. `SWIFTINDEX_ANTHROPIC_API_KEY` environment variable
3. `CLAUDE_CODE_OAUTH_TOKEN` environment variable
4. `ANTHROPIC_API_KEY` environment variable

The system SHALL use the first available token from the priority chain.

#### Scenario: Keychain token available

- **GIVEN** Keychain contains OAuth token
- **AND** no environment variables are set
- **WHEN** creating Anthropic LLM provider
- **THEN** uses Keychain token

#### Scenario: Environment variable overrides Keychain

- **GIVEN** Keychain contains OAuth token "keychain-token"
- **AND** `SWIFTINDEX_ANTHROPIC_API_KEY=override-key` is set
- **WHEN** creating Anthropic LLM provider
- **THEN** uses "override-key" instead of Keychain token

#### Scenario: OAuth env var priority

- **GIVEN** Keychain is empty
- **AND** `CLAUDE_CODE_OAUTH_TOKEN=oauth-env-token` is set
- **AND** `ANTHROPIC_API_KEY=api-key` is set
- **WHEN** creating Anthropic LLM provider
- **THEN** uses "oauth-env-token" (higher priority than ANTHROPIC_API_KEY)

#### Scenario: Fallback chain

- **GIVEN** Keychain is empty
- **AND** `SWIFTINDEX_ANTHROPIC_API_KEY` is not set
- **AND** `CLAUDE_CODE_OAUTH_TOKEN` is not set
- **AND** `ANTHROPIC_API_KEY=fallback-key` is set
- **WHEN** creating Anthropic LLM provider
- **THEN** uses "fallback-key"

#### Scenario: No token available

- **GIVEN** all sources return nil/empty
- **WHEN** attempting to use Anthropic provider
- **THEN** provider initialization fails gracefully
- **AND** shows clear error message with setup instructions
