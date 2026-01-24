## ADDED Requirements

### Requirement: Install Gemini CLI Configuration

The system SHALL provide a command to configure the project for the Google Gemini CLI assistant.

#### Scenario: Install for Gemini

- **WHEN** user runs `swiftindex install-gemini`
- **THEN** it checks for Gemini CLI configuration location
- **AND** creates or updates the configuration to register the `swiftindex serve` MCP server
