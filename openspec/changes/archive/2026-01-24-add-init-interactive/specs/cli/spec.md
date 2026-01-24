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
  │ ● Claude Code CLI (requires 'claude' command)
  │ ○ Codex CLI (requires 'codex' command)
  │ ○ Ollama (uses local server)
  │ ○ OpenAI (requires OPENAI_API_KEY)
  └
  ```

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
