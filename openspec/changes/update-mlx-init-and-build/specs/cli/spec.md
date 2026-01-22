## MODIFIED Requirements

### Requirement: Init Command

The system SHALL provide `swiftindex init` command to create config file.

#### Scenario: Create config

- **WHEN** running `swiftindex init`
- **THEN** creates `.swiftindex.toml` in current directory
- **AND** includes MLX defaults as active values
- **AND** includes commented examples for other providers and parameter meanings

#### Scenario: Config exists

- **WHEN** running init with existing config
- **THEN** asks to overwrite
- **AND** shows diff if different

#### Scenario: MLX prerequisites missing

- **WHEN** running `swiftindex init` with MLX defaults
- **AND** MetalToolchain is not installed
- **THEN** prompts the user to install MetalToolchain
- **AND** if the user declines, offers to switch to Swift Embeddings defaults
- **AND** if the user switches, writes config with Swift Embeddings defaults
- **AND** if the user declines the switch, exits with a clear error
