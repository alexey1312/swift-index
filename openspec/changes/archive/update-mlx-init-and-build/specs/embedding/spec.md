## MODIFIED Requirements

### Requirement: MLX Embedding Provider

The system SHALL support MLX-based embeddings as primary provider for Apple Silicon.

Supported models:

- `mlx-community/bge-small-en-v1.5-4bit` (384 dim, default)
- `mlx-community/bge-large-en-v1.5-4bit` (1024 dim)
- `mlx-community/nomic-embed-text-v1.5-4bit` (768 dim)

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
- **THEN** returns vector of correct dimension
- **AND** execution uses Metal GPU acceleration

#### Scenario: MLX Metal resources available for CLI

- **WHEN** running the CLI binary with MLX enabled
- **THEN** the Metal shader library `default.metallib` is available via bundled resources or co-located files
- **AND** MLX loads its Metal library without runtime errors
