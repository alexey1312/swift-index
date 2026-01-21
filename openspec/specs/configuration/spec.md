# configuration Specification

## Purpose

TBD - created by archiving change add-swiftindex-core. Update Purpose after archive.

## Requirements

### Requirement: TOML Configuration File

The system SHALL support configuration via `.swiftindex.toml` file in project root.

The configuration file SHALL support the following sections:

- `[provider]` — embedding provider settings
- `[mlx]` — MLX-specific settings
- `[ollama]` — Ollama-specific settings
- `[swift_embeddings]` — swift-embeddings settings
- `[voyage]` — Voyage API settings
- `[openai]` — OpenAI API settings
- `[index]` — indexing settings
- `[chunking]` — chunking parameters
- `[search]` — search parameters
- `[watch]` — watch mode settings
- `[cache]` — cache settings

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

The system SHALL support global user configuration at `~/.config/swiftindex/config.toml`.

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

- `SWIFTINDEX_PROVIDER` — default provider name
- `SWIFTINDEX_MLX_MODEL` — MLX model ID
- `SWIFTINDEX_OLLAMA_HOST` — Ollama server URL
- `SWIFTINDEX_OLLAMA_MODEL` — Ollama model name
- `HF_TOKEN` — HuggingFace token (standard)
- `VOYAGE_API_KEY` — Voyage API key
- `OPENAI_API_KEY` — OpenAI API key

#### Scenario: Environment overrides config

- **WHEN** `SWIFTINDEX_PROVIDER=ollama` is set
- **AND** config file has `provider.default = "mlx"`
- **THEN** system uses "ollama" as provider

#### Scenario: API key from environment

- **WHEN** `VOYAGE_API_KEY` is set in environment
- **THEN** VoyageProvider uses the key
- **AND** config file `api_key_env` is ignored

---

### Requirement: CLI Flag Override

The system SHALL support CLI flags that override all other configuration sources.

#### Scenario: CLI flag overrides environment

- **WHEN** user runs `swiftindex search --provider mlx "query"`
- **AND** `SWIFTINDEX_PROVIDER=ollama` is set
- **THEN** system uses "mlx" as provider

---

### Requirement: Configuration Priority Merge

The system SHALL merge configuration with the following priority (highest to lowest):

1. CLI flags
2. Environment variables
3. Project config (`.swiftindex.toml`)
4. Global config (`~/.config/swiftindex/config.toml`)
5. Built-in defaults

#### Scenario: Full priority chain

- **WHEN** value exists at multiple levels
- **THEN** highest priority value is used
- **AND** lower priority values are ignored

#### Scenario: Partial override

- **WHEN** CLI provides `--provider`
- **AND** config provides `search.limit`
- **THEN** both values are used in merged config

---

### Requirement: Configuration Validation

The system SHALL validate configuration values and report errors clearly.

#### Scenario: Invalid provider name

- **WHEN** config has `provider.default = "unknown"`
- **THEN** system reports error with valid options
- **AND** exits with non-zero code

#### Scenario: Invalid numeric value

- **WHEN** config has `search.default_limit = -5`
- **THEN** system reports "limit must be positive"

---

### Requirement: Default Configuration Values

The system SHALL provide sensible defaults for all configuration options.

Default values:

- `provider.default`: "mlx"
- `provider.fallback`: ["mlx", "ollama", "swift-embeddings", "voyage", "openai"]
- `mlx.model_id`: "mlx-community/bge-small-en-v1.5-4bit"
- `mlx.batch_size`: 32
- `ollama.model`: "nomic-embed-text"
- `ollama.host`: "http://localhost:11434"
- `index.include`: ["**/*.swift"]
- `index.exclude`: ["**/Pods/**", "**/DerivedData/**", "**/.build/**"]
- `chunking.target_size`: 2048
- `chunking.overlap`: 0.10
- `search.default_limit`: 10
- `search.semantic_weight`: 0.7
- `watch.debounce_ms`: 500

#### Scenario: All defaults applied

- **WHEN** no configuration is provided
- **THEN** system uses all default values
- **AND** indexing and search work correctly
