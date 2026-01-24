# Implementation Tasks

## 1. Glob Pattern Caching

- [x] 1.1 Add `GlobMatcher` utility class with LRU cache
- [x] 1.2 Refactor `HybridSearchEngine.matchesGlob` to use `GlobMatcher`
- [x] 1.3 Update `BM25Search` to use shared `GlobMatcher`
- [x] 1.4 Update `SemanticSearch` to use shared `GlobMatcher`
- [x] 1.5 Add unit tests for `GlobMatcher`

## 2. Batch Vector Retrieval

- [x] 2.1 Add `getBatch(ids:)` method to `VectorStore` protocol
- [x] 2.2 Implement `getBatch` in `USearchVectorStore`
- [x] 2.3 Refactor `IndexManager.reindexWithChangeDetection` to use batch get
- [x] 2.4 Add unit tests for batch retrieval

## 3. LRU Cache for FollowUpGenerator

- [x] 3.1 Add `accessOrder` array to track LRU order in `FollowUpGenerator`
- [x] 3.2 Update cache access to move key to end of `accessOrder`
- [x] 3.3 Change eviction from FIFO to LRU (remove first from `accessOrder`)
- [x] 3.4 Add unit tests for LRU eviction behavior

## 4. Integration Testing

- [x] 4.1 Add integration test for glob caching with 1000+ results
- [x] 4.2 Add integration test for batch reindex with 500+ chunks
- [x] 4.3 Add integration test for LRU cache behavior under load
- [x] 4.4 Verify no regressions in existing search tests
