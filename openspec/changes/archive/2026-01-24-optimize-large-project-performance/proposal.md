# Change: Optimize Performance for Large Projects

## Why

SwiftIndex имеет bottlenecks, критичные для проектов 100K+ файлов:

1. **Glob regex recreation** — `NSRegularExpression` создаётся для каждого результата при фильтрации путей (O(n) компиляций на поиск)
2. **Sequential vector retrieval** — `vectorStore.get(id:)` вызывается последовательно в цикле при reindex (N round-trips)
3. **FIFO cache eviction** — `FollowUpGenerator` использует FIFO вместо LRU, вытесняя часто используемые запросы

Эти проблемы снижают производительность на 50-500% для больших кодебаз.

## What Changes

### Search Performance

- **ADDED**: Кэширование скомпилированных glob patterns в `HybridSearchEngine`
- **MODIFIED**: Path filtering использует кэшированные regex вместо пересоздания

### Storage Performance

- **ADDED**: `VectorStore.getBatch(ids:)` для batch retrieval
- **MODIFIED**: `IndexManager.reindexWithChangeDetection` использует batch вместо sequential gets

### LLM Enhancement Performance

- **MODIFIED**: `FollowUpGenerator` использует LRU eviction вместо FIFO

## Impact

- Affected specs: `search`, `storage`
- Affected code:
  - `Sources/SwiftIndexCore/Search/HybridSearchEngine.swift`
  - `Sources/SwiftIndexCore/Search/BM25Search.swift`
  - `Sources/SwiftIndexCore/Search/SemanticSearch.swift`
  - `Sources/SwiftIndexCore/Storage/USearchVectorStore.swift`
  - `Sources/SwiftIndexCore/Storage/IndexManager.swift`
  - `Sources/SwiftIndexCore/LLM/FollowUpGenerator.swift`

## Expected Improvements

| Bottleneck                   | Before                     | After                      | Improvement              |
| ---------------------------- | -------------------------- | -------------------------- | ------------------------ |
| Glob filtering (20 results)  | 20 regex compilations      | 1 compilation              | ~95% faster              |
| Reindex 100 changed chunks   | 100 sequential gets        | 1 batch get                | 5-10x faster             |
| Follow-up cache (50 queries) | Hot queries evicted (FIFO) | Hot queries retained (LRU) | ~2-5s per repeated query |
