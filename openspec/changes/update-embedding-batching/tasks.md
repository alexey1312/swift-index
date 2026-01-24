## 1. Implementation

- [ ] 1.1 Add an embedding batcher (actor) that aggregates chunk requests across files and returns embeddings to callers.
- [ ] 1.2 Wire `IndexCommand.indexFile` to use the batcher instead of calling `embed` per file.
- [ ] 1.3 Flush pending batches on completion and propagate errors to callers.
- [ ] 1.4 Add unit tests for batching behavior (cross-file aggregation, batch size, order preservation, error propagation).

## 2. Documentation

- [ ] 2.1 Update embedding spec delta to reflect cross-file batching behavior.
