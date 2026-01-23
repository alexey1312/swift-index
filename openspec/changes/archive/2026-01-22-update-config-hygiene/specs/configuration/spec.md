## ADDED Requirements

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

## MODIFIED Requirements

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
