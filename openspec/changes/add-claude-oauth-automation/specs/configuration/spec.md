## MODIFIED Requirements

### Requirement: Environment Variable Override

The system SHALL support environment variable overrides with `SWIFTINDEX_` prefix.

Supported environment variables:

- `SWIFTINDEX_PROVIDER` — default provider name
- `SWIFTINDEX_MLX_MODEL` — MLX model ID
- `SWIFTINDEX_OLLAMA_HOST` — Ollama server URL
- `SWIFTINDEX_OLLAMA_MODEL` — Ollama model name
- `HF_TOKEN` — HuggingFace token (standard)
- `VOYAGE_API_KEY` — Voyage API key
- `OPENAI_API_KEY` — OpenAI API key
- `SWIFTINDEX_ANTHROPIC_API_KEY` — project-specific Anthropic API key (highest priority)
- `CLAUDE_CODE_OAUTH_TOKEN` — Claude Code OAuth token (priority over ANTHROPIC_API_KEY)
- `ANTHROPIC_API_KEY` — standard Anthropic API key (lowest env var priority)

**Anthropic Authentication Priority (highest to lowest):**

1. `SWIFTINDEX_ANTHROPIC_API_KEY` (project-specific override)
2. `CLAUDE_CODE_OAUTH_TOKEN` (OAuth token from environment)
3. `ANTHROPIC_API_KEY` (standard API key)
4. Keychain OAuth Token (via `KeychainManager.getClaudeCodeToken()` - macOS only)

#### Scenario: Environment overrides config

- **WHEN** `SWIFTINDEX_PROVIDER=ollama` is set
- **AND** config file has `provider.default = "mlx"`
- **THEN** system uses "ollama" as provider

#### Scenario: API key from environment

- **WHEN** `VOYAGE_API_KEY` is set in environment
- **THEN** VoyageProvider uses the key

#### Scenario: OAuth token environment variable

- **WHEN** `CLAUDE_CODE_OAUTH_TOKEN=oauth-env-token` is set
- **AND** `ANTHROPIC_API_KEY=api-key` is set
- **AND** Keychain contains token "keychain-token"
- **THEN** system uses "oauth-env-token" (env var has priority over Keychain)

#### Scenario: Project-specific key overrides OAuth

- **WHEN** `SWIFTINDEX_ANTHROPIC_API_KEY=project-key` is set
- **AND** `CLAUDE_CODE_OAUTH_TOKEN=oauth-token` is set
- **AND** `ANTHROPIC_API_KEY=api-key` is set
- **THEN** system uses "project-key" (highest priority)

#### Scenario: Keychain fallback

- **WHEN** all Anthropic environment variables are unset
- **AND** Keychain contains OAuth token "keychain-token"
- **AND** running on macOS
- **THEN** system uses "keychain-token" from Keychain

#### Scenario: Standard API key fallback

- **WHEN** `SWIFTINDEX_ANTHROPIC_API_KEY` is not set
- **AND** `CLAUDE_CODE_OAUTH_TOKEN` is not set
- **AND** Keychain is empty
- **AND** `ANTHROPIC_API_KEY=fallback-key` is set
- **THEN** system uses "fallback-key"
