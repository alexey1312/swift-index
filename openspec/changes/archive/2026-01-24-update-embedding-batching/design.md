# Design: Cross-file Embedding Batching

## Goals

- Maximize MLX/GPU utilization by increasing batch sizes.
- Reduce per-call overhead by batching embeddings across files.
- Preserve current indexing semantics and change detection.

## Non-Goals

- Changing embedding provider APIs.
- Introducing new config sections beyond existing defaults.

## Approach

Introduce an `EmbeddingBatcher` actor that receives chunk embedding requests from indexing tasks and returns embeddings asynchronously:

- **Input**: `[CodeChunk]` (or `[String]` contents) plus a continuation to resume with `[[Float]]`.
- **Batching**: Collects requests until `batchSize` is reached, then calls `EmbeddingProviderChain.embed` once for the combined texts.
- **Flush**: Flushes remaining requests when indexing completes or after an idle timeout.
- **Mapping**: Preserves ordering so each caller receives embeddings corresponding to its input chunks.
- **Errors**: Propagate embedding failures to all requests in the active batch.

## Batch Size

- Use a configurable batch size (prefer existing provider defaults; fall back to a safe constant).
- Keep batch size independent of per-file chunk count so small files can still benefit.

## Concurrency

- The batcher is an actor to safely coordinate between concurrent indexing tasks.
- Indexing tasks await their embeddings without blocking unrelated parsing/indexing work.

## Idle Timeout

The batcher flushes pending items after **150ms** of idle time (no new requests).

Rationale:

- 150ms balances latency vs. batching efficiency
- Typical file parsing takes 10-50ms, so 150ms allows 3-5 files to accumulate
- Configurable via `embedding.batch_timeout_ms` (default: 150)

## Memory Safeguard

To prevent unbounded memory growth with large chunks:

- Flush batch if pending content exceeds **10MB** total size
- Calculate size as sum of UTF-8 encoded chunk contents
- This limit is independent of batch count

Default 10MB handles ~5000 typical code chunks (2KB avg).

## Configuration

New keys under `[embedding]` section:

| Key                     | Type | Default | Description                     |
| ----------------------- | ---- | ------- | ------------------------------- |
| `batch_size`            | int  | 32      | Max chunks per embedding call   |
| `batch_timeout_ms`      | int  | 150     | Idle timeout before flush       |
| `batch_memory_limit_mb` | int  | 10      | Memory limit for pending chunks |

Provider-specific batch sizes take precedence if configured (e.g., `mlx.batch_size`).

## Observability

- Optionally log batch sizes and flush events at debug level for performance tuning.
