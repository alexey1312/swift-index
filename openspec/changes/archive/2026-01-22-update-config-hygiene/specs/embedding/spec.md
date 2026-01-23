## MODIFIED Requirements

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
