## ADDED Requirements

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

## MODIFIED Requirements

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
