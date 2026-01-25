## ADDED Requirements

### Requirement: Protocol Conformance Extraction

The system SHALL extract protocol conformances and inherited types from type declarations.

Supported constructs:

- Class declarations (`class`)
- Struct declarations (`struct`)
- Enum declarations (`enum`)
- Actor declarations (`actor`)
- Extension declarations (`extension`)

#### Scenario: Extract class conformances

- **WHEN** parsing `class User: Codable, Identifiable`
- **THEN** extracted conformances are `["Codable", "Identifiable"]`

#### Scenario: Extract struct inheritance

- **WHEN** parsing `struct Config: BaseConfig`
- **THEN** extracted conformances are `["BaseConfig"]`

#### Scenario: Extract extension conformances

- **WHEN** parsing `extension User: Sendable`
- **THEN** extracted conformances are `["Sendable"]`
