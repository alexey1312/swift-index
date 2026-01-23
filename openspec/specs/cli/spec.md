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
- **THEN** creates `.mcp.json` in current directory

#### Scenario: Install Codex (global)

- **WHEN** running `swiftindex install-codex --global`
- **THEN** adds to `~/.codex/config.yaml`

#### Scenario: Install Cursor (project-local default)

- **WHEN** running `swiftindex install-cursor`
- **THEN** creates `.mcp.json` in current directory

#### Scenario: Install Cursor (global)

- **WHEN** running `swiftindex install-cursor --global`
- **THEN** adds MCP server to Cursor settings

#### Scenario: Already installed

- **WHEN** running install when already configured
- **THEN** shows "already installed" message
- **AND** offers to reinstall

### Requirement: Init Command

The system SHALL provide `swiftindex init` command to create config file.

#### Scenario: Create config

- **WHEN** running `swiftindex init`
- **THEN** creates `.swiftindex.toml` in current directory
- **AND** includes commented default values
- **AND** omits API key fields
- **AND** points to environment variables for API keys

#### Scenario: Init guidance for assistants

- **WHEN** running `swiftindex init`
- **THEN** CLI prints brief recommendations for `AGENTS.md` and `CLAUDE.md`
- **AND** links to documentation with sample content

#### Scenario: Config exists

- **WHEN** running init with existing config
- **THEN** asks to overwrite
- **AND** shows diff if different

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
