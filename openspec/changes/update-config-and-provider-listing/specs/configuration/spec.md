## MODIFIED Requirements

### Requirement: TOML Configuration File

The system SHALL support configuration via `.swiftindex.toml` file in project root.

The configuration file SHALL support the following sections:

- `[embedding]` — embedding provider settings
- `[search]` — search parameters
- `[indexing]` — indexing settings
- `[storage]` — index and cache paths
- `[api_keys]` — provider API keys
- `[watch]` — watch mode settings
- `[logging]` — logging settings

#### Scenario: Load project config

- **WHEN** `.swiftindex.toml` exists in project root
- **THEN** configuration is loaded from the file
- **AND** missing fields use default values

#### Scenario: Missing config file

- **WHEN** `.swiftindex.toml` does not exist
- **THEN** system uses built-in defaults
- **AND** no error is raised

---

### Requirement: Global User Configuration

The system SHALL support global user configuration at `~/.swiftindex.toml`.

#### Scenario: Global config exists

- **WHEN** global config file exists
- **THEN** it provides defaults for all projects
- **AND** project config overrides global values

#### Scenario: Global config missing

- **WHEN** global config does not exist
- **THEN** built-in defaults are used

---

### Requirement: Environment Variable Override

The system SHALL support environment variable overrides with `SWIFTINDEX_` prefix.

Supported environment variables:

- `SWIFTINDEX_EMBEDDING_PROVIDER` — embedding provider name
- `SWIFTINDEX_EMBEDDING_MODEL` — embedding model ID
- `SWIFTINDEX_VOYAGE_API_KEY` — Voyage API key
- `SWIFTINDEX_OPENAI_API_KEY` — OpenAI API key
- `SWIFTINDEX_LOG_LEVEL` — logging level
- `VOYAGE_API_KEY` — Voyage API key (fallback)
- `OPENAI_API_KEY` — OpenAI API key (fallback)

#### Scenario: Environment overrides config

- **WHEN** `SWIFTINDEX_EMBEDDING_PROVIDER=ollama` is set
- **AND** config file has `embedding.provider = "mlx"`
- **THEN** system uses "ollama" as provider

#### Scenario: API key from environment

- **WHEN** `VOYAGE_API_KEY` is set in environment
- **THEN** VoyageProvider uses the key
- **AND** config file `api_keys.voyage` is ignored
