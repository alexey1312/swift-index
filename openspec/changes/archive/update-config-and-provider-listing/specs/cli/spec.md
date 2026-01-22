## MODIFIED Requirements

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

#### Scenario: Provider availability source

- **WHEN** provider status is listed
- **THEN** availability is determined by provider `isAvailable()` checks
- **AND** provider metadata comes from a single registry shared with CLI commands
