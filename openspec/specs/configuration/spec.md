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
- `search.enhancement.utility.description_batch_size`: 5
- `search.enhancement.utility.description_batch_mode`: "single"
- `search.enhancement.utility.description_chunks_per_request`: 1
- `watch.debounce_ms`: 500

#### Scenario: All defaults applied

- **WHEN** no configuration is provided
- **THEN** system uses all default values
- **AND** indexing and search work correctly

### Requirement: API Keys via Environment Only

The system SHALL only read API keys from environment variables.

Configuration files SHALL NOT include API key fields (for example `voyage.api_key`, `openai.api_key`, or `api_key_env`).

#### Scenario: API key present in config

- **WHEN** `.swiftindex.toml` includes an API key field
- **THEN** config validation fails with a security warning
- **AND** the error points to the correct key and suggests the env var name

#### Scenario: API key provided via environment

- **WHEN** `VOYAGE_API_KEY` is set in environment
- **THEN** VoyageProvider uses the key
- **AND** config validation passes

---

### Requirement: TOML Lint and Format Checks

The system SHALL validate `.swiftindex.toml` for TOML syntax, formatting, and lint rules.

Lint rules SHALL detect unknown keys, deprecated keys, and invalid value types.

Validation SHALL run whenever configuration is loaded (CLI commands, indexing, search, watch, or MCP server startup).

#### Scenario: TOML formatting issue

- **WHEN** `.swiftindex.toml` has formatting issues
- **THEN** validation reports a formatting diagnostic
- **AND** includes a suggested fix

#### Scenario: Unknown key in config

- **WHEN** `.swiftindex.toml` contains an unsupported key
- **THEN** validation reports the key and its location
- **AND** exits with configuration error code

#### Scenario: Config load triggers validation

- **WHEN** any command loads configuration
- **THEN** TOML formatting and lint checks are executed
- **AND** configuration errors prevent command execution

### Requirement: Description Generation Batch Size Configuration

The system SHALL allow configuring the maximum number of parallel description generation requests via `search.enhancement.utility.description_batch_size`.

The value MUST be a positive integer. If not provided, the system SHALL default to 5.

#### Scenario: Default batch size

- **WHEN** search enhancement is enabled
- **AND** `search.enhancement.utility.description_batch_size` is not configured
- **THEN** description generation runs with a batch size of 5

#### Scenario: Custom batch size

- **WHEN** `search.enhancement.utility.description_batch_size = 10`
- **THEN** description generation runs with a batch size of 10

#### Scenario: Invalid batch size

- **WHEN** `search.enhancement.utility.description_batch_size` is 0 or negative
- **THEN** configuration validation fails
- **AND** an error indicates the value must be positive

---

### Requirement: Description Generation Request Grouping

The system SHALL allow grouping multiple chunks into a single LLM request for description generation when explicitly enabled.

Configuration keys:

- `search.enhancement.utility.description_batch_mode` with allowed values: `single`, `grouped`.
- `search.enhancement.utility.description_chunks_per_request` as a positive integer (default 1).

When `description_batch_mode = grouped`, the system SHALL request a structured JSON array of `{id, description}` and validate it strictly. If parsing fails, the system SHALL fall back to single-chunk requests for the affected batch.

#### Scenario: Grouped request enabled

- **WHEN** `description_batch_mode = grouped`
- **AND** `description_chunks_per_request = 5`
- **THEN** the system sends up to 5 chunks in one request
- **AND** parses a JSON array of descriptions keyed by chunk id

#### Scenario: Grouped request with ID tracking

- **WHEN** `description_batch_mode = grouped`
- **AND** `description_chunks_per_request = 3`
- **AND** chunks have IDs ["a1b2", "c3d4", "e5f6"]
- **THEN** request includes chunk IDs in prompt context
- **AND** response MUST be JSON array with matching IDs
- **AND** format: `[{"id": "a1b2", "description": "..."}, ...]`

#### Scenario: Grouped request invalid response

- **WHEN** grouped request returns invalid JSON
- **THEN** the system falls back to single-chunk requests for that batch
- **AND** still returns descriptions for valid chunks

#### Scenario: Invalid grouping configuration

- **WHEN** `description_chunks_per_request` is 0 or negative
- **THEN** configuration validation fails
- **AND** an error indicates the value must be positive

---

### Requirement: Description Generation Progress Reporting

The system SHALL report progress during description generation via callback mechanism.

#### Scenario: Progress callback during batch processing

- **WHEN** `generateBatch()` completes a batch of chunks
- **THEN** progress callback is invoked with (completed, total, file)
- **AND** callback is optional (nil = no reporting)

#### Scenario: CLI progress display

- **WHEN** description generation is active
- **THEN** Noora displays nested progress under main progress bar
- **AND** shows completed/total chunks and current filename

---
