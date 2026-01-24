## ADDED Requirements

### Requirement: Embedding Configuration

The system SHALL support configuration of the embedding provider, model, dimension, and batching parameters via TOML and environment variables.

#### Scenario: Configure Gemini Provider

- **WHEN** config file contains `[embedding]` section with `provider = "gemini"`
- **THEN** the system uses the Google Gemini embedding provider
- **AND** reads `GEMINI_API_KEY` from the environment

### Requirement: Search Enhancement Configuration

The system SHALL support enabling LLM-powered search enhancements and selecting the LLM provider.

#### Scenario: Configure Gemini LLM

- **WHEN** config file contains `[search.enhancement.utility]` with `provider = "gemini"`
- **THEN** the system uses the Google Gemini REST API
- **AND** reads `GEMINI_API_KEY` from the environment

#### Scenario: Configure Gemini CLI

- **WHEN** config file contains `[search.enhancement.utility]` with `provider = "gemini-cli"`
- **THEN** the system invokes the `gemini` command-line tool