## ADDED Requirements

### Requirement: Auth Command

The system SHALL provide `swiftindex auth` command for managing Claude Code OAuth tokens.

The command SHALL have subcommands:

- `auth status` — check token status and validity
- `auth login` — authenticate and store OAuth token
- `auth logout` — remove token from Keychain

#### Scenario: Auth status with valid token

- **WHEN** running `swiftindex auth status`
- **AND** Keychain contains a valid OAuth token
- **THEN** displays:
  - "✓ Token found in Keychain"
  - "✓ Token is valid"
  - Token preview (first 10 characters)

#### Scenario: Auth status with invalid token

- **WHEN** running `swiftindex auth status`
- **AND** Keychain contains an invalid OAuth token
- **THEN** displays:
  - "✓ Token found in Keychain"
  - "✗ Token validation failed"
  - Instructions to re-authenticate

#### Scenario: Auth status with no token

- **WHEN** running `swiftindex auth status`
- **AND** Keychain does not contain a token
- **THEN** displays:
  - "✗ No token found in Keychain"
  - Instructions to run `swiftindex auth login`

#### Scenario: Auth login automatic flow

- **WHEN** running `swiftindex auth login`
- **AND** `claude` CLI is available
- **THEN** runs `claude setup-token` automatically
- **AND** displays instructions to follow browser authentication
- **AND** saves token to Keychain on success
- **AND** displays "✓ OAuth token saved to Keychain"

#### Scenario: Auth login with existing token

- **WHEN** running `swiftindex auth login`
- **AND** Keychain already contains a valid token
- **THEN** displays "✓ Token already exists in Keychain"
- **AND** displays "✓ Token is valid"
- **AND** suggests using `--force` to re-authenticate

#### Scenario: Auth login force re-authentication

- **WHEN** running `swiftindex auth login --force`
- **AND** Keychain contains an existing token
- **THEN** generates new token without prompting
- **AND** replaces existing token in Keychain

#### Scenario: Auth login manual mode

- **WHEN** running `swiftindex auth login --manual`
- **THEN** displays:
  - "Manual token input mode"
  - "1. Run: claude setup-token"
  - "2. Copy the generated token"
  - Prompt: "Paste your token (press Enter when done):"
- **AND** validates pasted token
- **AND** saves to Keychain if valid

#### Scenario: Auth login CLI not found

- **WHEN** running `swiftindex auth login`
- **AND** `claude` CLI is not available
- **THEN** displays:
  - "✗ Claude Code CLI not found"
  - Installation instructions: "npm install -g @anthropic-ai/claude-code"
  - Alternative: "Or use: swiftindex auth login --manual"
- **AND** exits with error code

#### Scenario: Auth login validation failure

- **WHEN** running `swiftindex auth login`
- **AND** token validation fails
- **THEN** displays "✗ Token validation failed"
- **AND** token is NOT saved to Keychain
- **AND** exits with error code

#### Scenario: Auth logout

- **WHEN** running `swiftindex auth logout`
- **AND** Keychain contains a token
- **THEN** removes token from Keychain
- **AND** displays "✓ Token removed from Keychain"

#### Scenario: Auth logout with no token

- **WHEN** running `swiftindex auth logout`
- **AND** Keychain does not contain a token
- **THEN** displays "✓ No token to remove"
- **AND** exits successfully

#### Scenario: Auth with verbose flag

- **WHEN** running `swiftindex auth status --verbose`
- **THEN** displays detailed debug information including:
  - Keychain service and account names
  - Token validation HTTP requests/responses
  - Provider availability checks

---

## MODIFIED Requirements

### Requirement: Init Command

The system SHALL provide `swiftindex init` command to create config file.

The command SHALL use Noora components for interactive prompts:

- `singleChoicePrompt` for provider/model selection
- `yesOrNoChoicePrompt` for yes/no questions
- `textPrompt` for custom model input

The command SHALL detect TTY and fall back to defaults when running non-interactively.

The command SHALL use `--provider` / `--model` values as preselected defaults in the interactive flow.

#### Scenario: Interactive mode selection

- **GIVEN** running `swiftindex init` in a TTY
- **WHEN** the wizard starts
- **THEN** shows mode selection prompt:
  ```
  ┌ Setup
  │
  ◆ How would you like to configure SwiftIndex?
  │ ● Configure interactively (recommended)
  │ ○ Use defaults (MLX + no LLM enhancement)
  └
  ```

#### Scenario: Embedding provider selection

- **GIVEN** user selected "Configure interactively"
- **WHEN** provider step displays
- **THEN** shows provider options:
  ```
  ┌ Embedding Provider
  │
  ◆ Select embedding provider
  │ ● MLX (Apple Silicon, fastest)
  │ ○ Swift Embeddings (CPU, no Metal required)
  │ ○ Ollama (local server)
  │ ○ Voyage (cloud API, requires VOYAGE_API_KEY)
  │ ○ OpenAI (cloud API, requires OPENAI_API_KEY)
  └
  ```
- **AND** preselects value from `--provider` if provided

#### Scenario: Model selection

- **GIVEN** user selected a provider
- **WHEN** model step displays
- **THEN** shows provider-specific model options:
  ```
  ┌ Embedding Model
  │
  ◆ Select model for MLX
  │ ● Qwen3-Embedding-0.6B (1024 dim, recommended)
  │ ○ Qwen3-Embedding-4B (2048 dim, higher quality)
  │ ○ Qwen3-Embedding-8B (4096 dim, best quality)
  │ ○ Custom...
  └
  ```
- **AND** "Custom..." triggers text input for model name
- **AND** preselects value from `--model` if provided

#### Scenario: LLM enhancement configuration

- **GIVEN** model is selected
- **WHEN** LLM enhancement step displays
- **THEN** shows yes/no prompt:
  ```
  ┌ Search Enhancement
  │
  ◇ Enable LLM-powered search enhancement?
  │ Query expansion and result synthesis using LLM
  │ (y/n)
  └
  ```
- **IF** user selects yes
- **THEN** shows provider selection:
  ```
  ┌ LLM Provider
  │
  ◆ Select LLM provider for search enhancement
  │ ● MLX (local, Apple Silicon)
  │ ○ Claude Code OAuth (Pro/Max - secure, auto-managed)
  │ ○ Claude Code CLI (requires 'claude' command)
  │ ○ Codex CLI (requires 'codex' command)
  │ ○ Ollama (uses local server)
  │ ○ OpenAI (requires OPENAI_API_KEY)
  └
  ```

#### Scenario: Claude Code OAuth selection

- **GIVEN** user selected "Claude Code OAuth" as LLM provider
- **WHEN** OAuth setup begins
- **THEN** checks for existing token in Keychain
- **IF** existing token found
  - **THEN** prompts: "Use existing token? (y/n)"
  - **IF** yes: validates existing token
  - **IF** no or invalid: continues to OAuth flow

#### Scenario: OAuth automatic flow

- **GIVEN** user selected "Claude Code OAuth"
- **AND** no valid token in Keychain
- **WHEN** checking CLI availability
- **AND** `claude` CLI is available
- **THEN** displays:
  - "Running 'claude setup-token'..."
  - "Follow the instructions in your browser to authenticate."
- **AND** runs `claude setup-token` subprocess
- **AND** parses and validates token
- **AND** saves to Keychain on success
- **AND** displays "✓ OAuth token saved to Keychain"

#### Scenario: OAuth manual fallback

- **GIVEN** user selected "Claude Code OAuth"
- **AND** automatic flow failed or CLI unavailable
- **WHEN** system offers manual input
- **THEN** displays:
  - "Manual token input mode"
  - "Run 'claude setup-token' in terminal and copy the token"
  - Prompt: "Paste your Claude Code OAuth token:"
- **AND** validates pasted token
- **AND** saves to Keychain if valid
- **OR** falls back to LLM provider selection if user declines

#### Scenario: OAuth validation failure during init

- **GIVEN** user selected "Claude Code OAuth"
- **WHEN** token validation fails
- **THEN** displays "✗ Token validation failed - token may be invalid"
- **AND** offers manual input: "Enter token manually instead? (y/n)"
- **IF** user declines
  - **THEN** sets LLM provider to "none"
  - **AND** continues with wizard

#### Scenario: Config exists

- **GIVEN** `.swiftindex.toml` already exists
- **AND** `--force` is NOT provided
- **WHEN** running `swiftindex init`
- **THEN** shows confirmation prompt:
  ```
  ┌ Configuration exists
  │
  ◇ .swiftindex.toml already exists. Overwrite?
  │ (y/n)
  └
  ```
- **IF** user selects no
- **THEN** exits without changes

#### Scenario: Use defaults mode

- **GIVEN** user selected "Use defaults" on first screen
- **THEN** writes config with:
  - provider = "mlx"
  - model = "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ"
  - search.enhancement.enabled = false
- **AND** skips all other prompts

#### Scenario: Non-TTY fallback

- **WHEN** running `swiftindex init` without TTY (CI, pipes)
- **THEN** uses defaults without prompts
- **AND** prints "Using default configuration (non-interactive mode)"

#### Scenario: Metal toolchain missing

- **GIVEN** user selected MLX provider
- **AND** Metal toolchain is not available
- **WHEN** validating selection
- **THEN** shows warning and offers alternatives:
  ```
  ┌ Warning
  │
  ◇ Metal toolchain not found. MLX requires Metal shader tools.
  │ Switch to Swift Embeddings instead?
  │ (y/n)
  └
  ```

#### Scenario: Init guidance

- **WHEN** config is successfully created
- **THEN** prints next steps including:
  - Review and customize `.swiftindex.toml`
  - Run `swiftindex index` to build the index
  - Add `AGENTS.md` / `CLAUDE.md` for AI assistant guidance
- **AND** links to documentation
