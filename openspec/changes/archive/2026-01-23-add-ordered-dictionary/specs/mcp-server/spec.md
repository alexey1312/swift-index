## ADDED Requirements

### Requirement: Tool List Ordering

The system SHALL return MCP tools in deterministic order that preserves the registration order in `tools/list` responses.

#### Scenario: Registration order preserved

- **WHEN** tools are registered in a known order
- **THEN** `tools/list` returns tools in that same order

#### Scenario: Re-register preserves order

- **WHEN** a tool is registered with a name that already exists
- **THEN** the tool definition is replaced
- **AND** its position in the `tools/list` order does not change
