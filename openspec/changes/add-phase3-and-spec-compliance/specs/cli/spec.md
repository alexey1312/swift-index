# cli Specification Delta

## MODIFIED Requirements

### Requirement: Install Commands

The system SHALL provide **separate** install commands for AI assistant integration.

Commands:

- `swiftindex install-claude-code` — configure Claude Code
- `swiftindex install-cursor` — configure Cursor
- `swiftindex install-codex` — configure Codex

Each command SHALL be a separate subcommand (not a target argument).

#### Scenario: Install Claude Code

- **WHEN** running `swiftindex install-claude-code`
- **THEN** finds swiftindex binary path
- **AND** adds MCP server config to `~/.claude.json`:
  ```json
  {
    "mcpServers": {
      "swiftindex": {
        "type": "stdio",
        "command": "/path/to/swiftindex",
        "args": ["serve"]
      }
    }
  }
  ```
- **AND** shows success message

#### Scenario: Install Cursor

- **WHEN** running `swiftindex install-cursor`
- **THEN** finds swiftindex binary path
- **AND** adds MCP server config to `~/.cursor/mcp.json`:
  ```json
  {
    "mcpServers": {
      "swiftindex": {
        "command": "/path/to/swiftindex",
        "args": ["serve"]
      }
    }
  }
  ```
- **AND** shows success message

#### Scenario: Install Codex

- **WHEN** running `swiftindex install-codex`
- **THEN** finds swiftindex binary path
- **AND** adds MCP server config to `~/.codex/config.toml`:
  ```toml
  [mcp_servers.swiftindex]
  command = "/path/to/swiftindex"
  args = ["serve"]
  ```
- **AND** shows success message

#### Scenario: Already installed

- **WHEN** running install when already configured
- **THEN** shows "already installed" message
- **AND** offers to reinstall with `--force` flag

#### Scenario: Dry run

- **WHEN** running install with `--dry-run` flag
- **THEN** shows what would be written
- **AND** does not modify any files
