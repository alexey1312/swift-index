## MODIFIED Requirements

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
