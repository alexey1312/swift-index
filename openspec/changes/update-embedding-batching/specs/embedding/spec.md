## MODIFIED Requirements

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
