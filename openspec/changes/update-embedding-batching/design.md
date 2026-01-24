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

## Observability

- Optionally log batch sizes and flush events at debug level for performance tuning.
