# embedding Specification

## Purpose

TBD - created by archiving change add-swiftindex-core. Update Purpose after archive.

## Requirements

### Requirement: Embedding Provider Protocol

The system SHALL define a unified `EmbeddingProvider` protocol for all embedding backends.

Protocol requirements:

- `name: String` — provider identifier
- `dimension: Int` — embedding vector dimension
- `isAvailable() async -> Bool` — availability check
- `embed(_ texts: [String]) async throws -> [[Float]]` — batch embedding

#### Scenario: Provider conforms to protocol

- **WHEN** implementing new provider
- **THEN** it must implement all protocol requirements
- **AND** can be used interchangeably in provider chain

---

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

### Requirement: Ollama Embedding Provider

The system SHALL support Ollama as fallback embedding provider.

Supported models:

- `nomic-embed-text` (768 dim, default)
- `mxbai-embed-large` (1024 dim)
- `bge-large` (1024 dim)

#### Scenario: Ollama available

- **WHEN** Ollama server running at configured host
- **AND** model is pulled
- **THEN** `isAvailable()` returns true

#### Scenario: Ollama server not running

- **WHEN** Ollama server is not running
- **THEN** `isAvailable()` returns false
- **AND** provider chain falls back

#### Scenario: Ollama embedding generation

- **WHEN** calling `embed(texts)` with Ollama
- **THEN** makes HTTP request to `/api/embeddings`
- **AND** returns embedding vectors

---

### Requirement: Swift Embeddings Provider

The system SHALL support pure Swift embeddings as always-available fallback.

Supported models:

- `sentence-transformers/all-MiniLM-L6-v2` (384 dim, default)

#### Scenario: Swift embeddings always available

- **WHEN** checking availability
- **THEN** `isAvailable()` always returns true
- **AND** no external dependencies required

#### Scenario: Swift embeddings generation

- **WHEN** calling `embed(texts)` with SwiftEmbeddings
- **THEN** uses MLTensor for computation
- **AND** returns embeddings (slower but guaranteed)

---

### Requirement: Voyage Embedding Provider

The system SHALL support Voyage AI as cloud embedding provider.

Supported models:

- `voyage-code-3` (1024 dim, optimized for code)
- `voyage-3` (1024 dim, general purpose)

#### Scenario: Voyage available with API key

- **WHEN** `VOYAGE_API_KEY` environment variable is set
- **THEN** `isAvailable()` returns true

#### Scenario: Voyage unavailable without API key

- **WHEN** `VOYAGE_API_KEY` is not set
- **THEN** `isAvailable()` returns false

#### Scenario: Voyage embedding generation

- **WHEN** calling `embed(texts)` with Voyage
- **THEN** makes HTTPS request to Voyage API
- **AND** returns code-optimized embeddings

---

### Requirement: OpenAI Embedding Provider

The system SHALL support OpenAI as cloud embedding provider.

Supported models:

- `text-embedding-3-small` (1536 dim)
- `text-embedding-3-large` (3072 dim)

#### Scenario: OpenAI available with API key

- **WHEN** `OPENAI_API_KEY` environment variable is set
- **THEN** `isAvailable()` returns true

#### Scenario: OpenAI embedding generation

- **WHEN** calling `embed(texts)` with OpenAI
- **THEN** makes HTTPS request to OpenAI API
- **AND** returns embeddings

---

### Requirement: Provider Chain with Fallback

The system SHALL implement automatic provider fallback chain.

Default chain order:

1. MLX (fastest, privacy-first)
2. Ollama (local, good performance)
3. SwiftEmbeddings (always available)
4. Voyage (cloud, code-optimized)
5. OpenAI (cloud, general)

#### Scenario: Use first available provider

- **WHEN** MLX model is cached
- **THEN** EmbeddingService uses MLX
- **AND** does not check other providers

#### Scenario: Fallback on unavailable

- **WHEN** MLX model not cached
- **AND** Ollama not running
- **THEN** EmbeddingService uses SwiftEmbeddings

#### Scenario: All local unavailable, use cloud

- **WHEN** all local providers unavailable
- **AND** Voyage API key is set
- **THEN** EmbeddingService uses Voyage

#### Scenario: No providers available

- **WHEN** all providers unavailable (no models, no API keys)
- **THEN** EmbeddingService throws descriptive error
- **AND** suggests installation steps

---

### Requirement: Model Download with Consent

The system SHALL request user consent before downloading models.

#### Scenario: First-time model download

- **WHEN** MLX model not cached
- **AND** `mlx.download_consented = false`
- **THEN** system prompts user for download consent
- **AND** shows model size and download location

#### Scenario: Pre-consented download

- **WHEN** `mlx.download_consented = true` in config
- **THEN** system downloads without prompting

#### Scenario: Download progress

- **WHEN** downloading model
- **THEN** system shows progress bar
- **AND** allows cancellation

---

### Requirement: Embedding Caching

The system SHALL cache embeddings to avoid recomputation.

#### Scenario: Cache hit

- **WHEN** chunk content unchanged (same hash)
- **THEN** return cached embedding
- **AND** skip provider call

#### Scenario: Cache invalidation

- **WHEN** chunk content changes
- **THEN** recompute embedding
- **AND** update cache

---

### Requirement: Batch Embedding

The system SHALL embed texts in batches that can span multiple files during indexing to reduce per-call overhead and improve MLX/GPU utilization.

Batching rules:

- The batcher MUST aggregate chunk contents across files up to the configured batch size.
- The batcher MUST preserve per-request ordering so callers receive embeddings matching their input chunk order.
- The batcher MUST flush remaining items on indexing completion or after a bounded idle timeout.
- Errors from the embedding provider MUST be propagated to all requests in the affected batch.

#### Scenario: Cross-file batching

- **WHEN** indexing produces many small chunk lists across multiple files
- **THEN** the system aggregates them into larger batches
- **AND** reduces the number of embedding calls compared to per-file embedding

#### Scenario: Flush on completion

- **WHEN** indexing finishes with a partially filled batch
- **THEN** the system flushes the remaining items
- **AND** all pending callers receive embeddings

#### Scenario: Order preservation

- **WHEN** two callers submit chunk lists
- **THEN** each caller receives embeddings corresponding to their original chunk order

### Requirement: Code-Optimized Embedding Models

The system SHALL support code-optimized embedding models when explicitly configured.

Example models for code:

- `jinaai/jina-embeddings-v2-base-code` (768 dim)
- `Salesforce/SFR-Embedding-Code-400M_R` (larger, higher quality)

#### Scenario: Init does not recommend code models

- **WHEN** user runs `swiftindex init`
- **THEN** config comments do not recommend code-optimized models by default
- **AND** default remains `bge-small-en-v1.5-4bit` for memory safety

#### Scenario: Jina code model usage

- **WHEN** config specifies `embedding_model = "jinaai/jina-embeddings-v2-base-code"`
- **THEN** system uses the configured model
- **AND** search results are optimized for code semantics

### Requirement: Google Gemini Provider

The system SHALL support generating embeddings using the Google Gemini API.

#### Scenario: Generate embeddings

- **WHEN** the active provider is Gemini
- **AND** a batch of text chunks is processed
- **THEN** it sends a request to the `batchEmbedContents` endpoint
- **AND** returns vectors of the appropriate dimension (768 for `text-embedding-004`)
