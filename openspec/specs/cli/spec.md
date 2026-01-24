# cli Specification

## Purpose

TBD - created by archiving change add-swiftindex-core. Update Purpose after archive.

## Requirements

### Requirement: CLI Application Structure

The system SHALL provide `swiftindex` CLI built with swift-argument-parser.

Command structure:

- `swiftindex index` — index codebase
- `swiftindex search <query>` — search indexed codebase
- `swiftindex watch` — watch mode with auto-sync
- `swiftindex providers` — list embedding providers
- `swiftindex install-claude-code` — configure Claude Code
- `swiftindex install-codex` — configure Codex
- `swiftindex install-cursor` — configure Cursor
- `swiftindex init` — create config file
- `swiftindex stats` — show index statistics
- `swiftindex clear` — clear index

#### Scenario: Show help

- **WHEN** running `swiftindex --help`
- **THEN** displays all commands with descriptions

#### Scenario: Show version

- **WHEN** running `swiftindex --version`
- **THEN** displays version number

---

### Requirement: Index Command

The system SHALL provide `swiftindex index` command for indexing.

Options:

- `--path <path>` — project path (default: current directory)
- `--provider <name>` — force specific provider
- `--include-tests` — include test files
- `--rebuild` — clear and rebuild index
- `--verbose` — show detailed progress

#### Scenario: Index current directory

- **WHEN** running `swiftindex index` in project directory
- **THEN** indexes current directory
- **AND** shows progress and statistics

#### Scenario: Index specific path

- **WHEN** running `swiftindex index --path /path/to/project`
- **THEN** indexes specified path

#### Scenario: Index with rebuild

- **WHEN** running `swiftindex index --rebuild`
- **THEN** clears existing index
- **AND** performs full re-index

#### Scenario: Index output

- **WHEN** indexing completes
- **THEN** shows:
  - Files indexed count
  - Chunks created count
  - Duration
  - Provider used

---

### Requirement: Search Command

The system SHALL provide `swiftindex search` command for searching.

Options:

- `<query>` — search query (required)
- `--limit <n>` — max results (default: 10)
- `--semantic-weight <f>` — weight 0-1 (default: 0.7)
- `--path <path>` — project path
- `--filter <glob>` — file filter pattern
- `--json` — output as JSON

#### Scenario: Basic search

- **WHEN** running `swiftindex search "authentication"`
- **THEN** displays matching code chunks
- **AND** shows file paths and line numbers

#### Scenario: Search with limit

- **WHEN** running `swiftindex search "auth" --limit 5`
- **THEN** shows at most 5 results

#### Scenario: Search JSON output

- **WHEN** running `swiftindex search "auth" --json`
- **THEN** outputs results as JSON array

#### Scenario: Search result display

- **WHEN** displaying results
- **THEN** shows:
  - File path with line numbers
  - Relevance score
  - Code snippet with syntax highlighting

---

### Requirement: Watch Command

The system SHALL provide `swiftindex watch` command for continuous sync.

Options:

- `--path <path>` — project path
- `--debounce <ms>` — debounce delay (default: 500)
- `--verbose` — show file change events

#### Scenario: Start watch mode

- **WHEN** running `swiftindex watch`
- **THEN** performs initial sync
- **AND** starts watching for changes

#### Scenario: Watch detects changes

- **WHEN** file is modified during watch
- **THEN** shows "change: <path>"
- **AND** re-indexes changed file

#### Scenario: Watch exit

- **WHEN** pressing Ctrl+C during watch
- **THEN** stops watcher gracefully
- **AND** shows summary

---

### Requirement: Providers Command

The system SHALL provide `swiftindex providers` command to check provider status.

#### Scenario: List providers

- **WHEN** running `swiftindex providers`
- **THEN** shows all providers with status:
  - `✓` — available
  - `○` — unavailable
  - Model name and dimension

#### Scenario: Provider details

- **WHEN** provider is available
- **THEN** shows model ID and cache location

---

### Requirement: Install Commands

The system SHALL provide install commands for AI assistant integration with configurable scope.

Commands:

- `swiftindex install-claude-code [--global]`
- `swiftindex install-codex [--global]`
- `swiftindex install-cursor [--global]`

Options:

- `--global` — write to user-level config instead of project-local

#### Scenario: Install Claude Code (project-local default)

- **WHEN** running `swiftindex install-claude-code`
- **THEN** detects Swift project
- **AND** creates `.mcp.json` in current directory with MCP server config
- **AND** shows success message with config location

#### Scenario: Install Claude Code (global)

- **WHEN** running `swiftindex install-claude-code --global`
- **THEN** adds MCP server to `~/.claude.json`
- **AND** shows success message with global config location

#### Scenario: Install Codex (project-local default)

- **WHEN** running `swiftindex install-codex`
- **THEN** adds MCP server to `~/.codex/config.toml` with `cwd` set to current directory

#### Scenario: Install Codex (global)

- **WHEN** running `swiftindex install-codex --global`
- **THEN** adds to `~/.codex/config.toml`

#### Scenario: Install Cursor (project-local default)

- **WHEN** running `swiftindex install-cursor`
- **THEN** adds MCP server to `.cursor/mcp.json` in the current directory
- **AND** configures the `swiftindex` MCP server with `type = "stdio"`

#### Scenario: Install Cursor (global)

- **WHEN** running `swiftindex install-cursor --global`
- **THEN** adds MCP server to `~/.cursor/mcp.json`
- **AND** configures the `swiftindex` MCP server with `type = "stdio"`

#### Scenario: Already installed

- **WHEN** running install when already configured
- **THEN** shows "already installed" message
- **AND** offers to reinstall

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

### Requirement: Stats Command

The system SHALL provide `swiftindex stats` command for index statistics.

#### Scenario: Show stats

- **WHEN** running `swiftindex stats`
- **THEN** displays:
  - Total files indexed
  - Total chunks
  - Index size on disk
  - Last indexed time
  - Provider used
  - Breakdown by file type

---

### Requirement: Clear Command

The system SHALL provide `swiftindex clear` command to remove index.

#### Scenario: Clear index

- **WHEN** running `swiftindex clear`
- **THEN** asks for confirmation
- **AND** removes index directory

#### Scenario: Clear with force

- **WHEN** running `swiftindex clear --force`
- **THEN** removes without confirmation

---

### Requirement: Global Options

The system SHALL support global options across all commands.

Global options:

- `--config <path>` — custom config file
- `--verbose` / `-v` — verbose output
- `--quiet` / `-q` — suppress output
- `--no-color` — disable colored output

#### Scenario: Custom config

- **WHEN** running with `--config custom.toml`
- **THEN** uses custom config file

#### Scenario: Verbose mode

- **WHEN** running with `--verbose`
- **THEN** shows detailed progress and debug info

---

### Requirement: Exit Codes

The system SHALL use standard exit codes.

Exit codes:

- `0` — success
- `1` — general error
- `2` — configuration error
- `3` — index not found
- `4` — provider unavailable

#### Scenario: Successful command

- **WHEN** command completes successfully
- **THEN** exits with code 0

#### Scenario: Error exit

- **WHEN** command fails
- **THEN** exits with appropriate error code
- **AND** shows error message to stderr

### Requirement: Config Lint and Format Commands

The system SHALL provide commands to lint and format `.swiftindex.toml`.

Commands:

- `swiftindex config lint [--config <path>]`
- `swiftindex config format [--config <path>]`

The system SHALL run lint/format validation on any CLI command that reads configuration.

#### Scenario: Lint default config file

- **WHEN** running `swiftindex config lint`
- **THEN** CLI validates `.swiftindex.toml`
- **AND** prints formatting and lint diagnostics
- **AND** exits with configuration error code on failure

#### Scenario: Format config file

- **WHEN** running `swiftindex config format`
- **THEN** CLI rewrites `.swiftindex.toml` with canonical formatting
- **AND** reports the files changed

#### Scenario: Any command validates config

- **WHEN** running `swiftindex search` (or any command that loads config)
- **THEN** CLI runs TOML lint/format validation
- **AND** fails fast on configuration errors

### Requirement: Install Gemini CLI Configuration

The system SHALL provide a command to configure the project for the Google Gemini CLI assistant.

#### Scenario: Install for Gemini

- **WHEN** user runs `swiftindex install-gemini`
- **THEN** it checks for Gemini CLI configuration location
- **AND** creates or updates the configuration to register the `swiftindex serve` MCP server
