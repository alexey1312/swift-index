## MODIFIED Requirements

### Requirement: Batch Embedding

The system SHALL embed texts in batches that can span multiple files during indexing to reduce per-call overhead and improve MLX/GPU utilization.

Batching configuration under `[embedding]`:

| Key                    | Type | Default | Description                              |
| ---------------------- | ---- | ------- | ---------------------------------------- |
| `batch_size`           | int  | 32      | Maximum chunks per embedding call        |
| `batch_timeout_ms`     | int  | 150     | Idle timeout before flushing (ms)        |
| `batch_memory_limit_mb`| int  | 10      | Memory limit for pending chunks (MB)     |

Batching rules:

- The batcher MUST aggregate chunk contents across files up to the configured batch size.
- The batcher MUST preserve per-request ordering so callers receive embeddings matching their input chunk order.
- The batcher MUST flush remaining items on indexing completion or after a bounded idle timeout.
- Errors from the embedding provider MUST be propagated to all requests in the affected batch.

#### Scenario: Batch processing

- **WHEN** indexing 100 chunks
- **THEN** embed in batches of `batch_size`
- **AND** show progress indicator

#### Scenario: Batch size configuration

- **WHEN** `batch_size = 64` in config
- **THEN** process 64 texts per provider call

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

#### Scenario: Idle timeout flush

- **WHEN** batcher has pending chunks
- **AND** no new requests arrive for 150ms
- **THEN** the system flushes pending items
- **AND** callers receive embeddings without waiting for full batch

#### Scenario: Memory limit flush

- **WHEN** pending chunk contents exceed 10MB
- **THEN** the system flushes immediately
- **AND** prevents unbounded memory growth

#### Scenario: Error propagation

- **WHEN** embedding provider returns an error
- **THEN** all requests in the affected batch receive the error
- **AND** subsequent batches are not affected
