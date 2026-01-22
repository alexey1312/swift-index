# embedding Specification Delta

## MODIFIED Requirements

### Requirement: Real Embeddings

The system SHALL generate semantically meaningful embeddings, NOT random or placeholder vectors.

#### Scenario: SwiftEmbeddingsProvider

- **WHEN** calling `embed("Swift programming")`
- **THEN** returns real BERT-based embedding from swift-embeddings package
- **AND** uses `Bert.loadModelBundle()` to load actual model weights
- **AND** uses `modelBundle.encode()` for embedding generation
- **AND** similar texts have cosine similarity > 0.8
- **AND** different texts have lower similarity

#### Scenario: MLXEmbeddingProvider

- **WHEN** calling `embed("Swift programming")` on Apple Silicon
- **THEN** returns real embedding via MLXEmbedders from mlx-swift-lm
- **AND** uses `MLXEmbedders.loadModelContainer()` for model loading
- **AND** computation uses Metal GPU acceleration
- **AND** similar texts have cosine similarity > 0.8

### Requirement: MLX Provider Dependencies

The system SHALL use mlx-swift-lm package for MLX embeddings support.

Package dependency:

```swift
.package(url: "https://github.com/ml-explore/mlx-swift-lm.git", from: "0.25.0")
```

Products:

- `MLXEmbedders` — for embedding model loading and inference

### Requirement: Swift Embeddings Provider Dependencies

The system SHALL use swift-embeddings package for pure Swift embeddings.

API usage:

```swift
// Load model
let modelBundle = try await Bert.loadModelBundle(
    from: "sentence-transformers/all-MiniLM-L6-v2"
)

// Generate embedding
let embedding = modelBundle.encode("text to embed")
let result = await embedding.cast(to: Float.self).shapedArray(of: Float.self).scalars
```
