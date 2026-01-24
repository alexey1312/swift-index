## ADDED Requirements

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

## MODIFIED Requirements

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
