## MODIFIED Requirements

### Requirement: MLX Embedding Provider

The system SHALL support MLX-based embeddings as primary provider for Apple Silicon with configurable model and dimension.

Supported models:

- `mlx-community/bge-small-en-v1.5-4bit` (384 dim, **default** - memory-safe)
- `mlx-community/bge-large-en-v1.5-4bit` (1024 dim)
- `mlx-community/nomic-embed-text-v1.5-4bit` (768 dim)

Configuration:

- Provider MUST read `embeddingModel` from config when specified
- Provider MUST read `embeddingDimension` from config when specified
- Provider MUST use default `bge-small-en-v1.5-4bit` (384 dim) when not configured

#### Scenario: MLX uses config model

- **WHEN** config specifies `embedding_model = "mlx-community/nomic-embed-text-v1.5-4bit"`
- **AND** config specifies `embedding_dimension = 768`
- **THEN** MLXEmbeddingProvider uses specified model and dimension
- **AND** does not use hardcoded defaults

#### Scenario: MLX uses safe defaults

- **WHEN** config does not specify model
- **THEN** MLXEmbeddingProvider uses `bge-small-en-v1.5-4bit`
- **AND** dimension is 384
- **AND** memory allocation stays within Metal buffer limits

#### Scenario: MLX available with cached model

- **WHEN** model is cached at `~/.cache/huggingface/hub/`
- **THEN** `isAvailable()` returns true
- **AND** embedding completes without network

#### Scenario: MLX unavailable without model

- **WHEN** model is not cached
- **THEN** `isAvailable()` returns false
- **AND** provider chain falls back to next provider

#### Scenario: MLX embedding generation

- **WHEN** calling `embed(["authentication code"])` with MLX
- **THEN** returns vector of correct dimension matching config
- **AND** execution uses Metal GPU acceleration

---

## ADDED Requirements

### Requirement: Code-Optimized Embedding Models

The system SHALL support code-optimized embedding models for better Swift code search.

Recommended models for code:

- `jinaai/jina-embeddings-v2-base-code` (768 dim, Apache 2.0, code-optimized)
- `Salesforce/SFR-Embedding-Code-400M_R` (high quality, larger)

#### Scenario: Code model recommendation

- **WHEN** user runs `swiftindex init` for Swift project
- **THEN** config comments recommend code-optimized models
- **AND** default remains `bge-small-en-v1.5-4bit` for memory safety

#### Scenario: Jina code model usage

- **WHEN** config specifies `embedding_model = "jinaai/jina-embeddings-v2-base-code"`
- **THEN** system uses Jina model for code-aware embeddings
- **AND** search results are optimized for code semantics
