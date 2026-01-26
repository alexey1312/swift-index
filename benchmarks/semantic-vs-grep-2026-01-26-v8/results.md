# SwiftIndex v8 Detailed Results

## Category A: Exact Keywords

### 1. `HybridSearchEngine`

**P@5: 5/5**

| # | Result                       | Relevant |
| - | ---------------------------- | -------- |
| 1 | HybridSearchEngine actor     | ✓        |
| 2 | hybridSearchCombination test | ✓        |
| 3 | BM25Search actor             | ✓        |
| 4 | SemanticSearch actor         | ✓        |
| 5 | USearchVectorStore           | ✓        |

**Notes**: Perfect result - exact match first, related search engines follow.

---

### 2. `USearchError`

**P@5: 2/5** (v7: 0/5, **+2 improvement**)

| # | Result                                   | Relevant |
| - | ---------------------------------------- | -------- |
| 1 | CamelCaseSearchTests (USearchError test) | ✓        |
| 2 | BM25Search                               | ✗        |
| 3 | USearchVectorStore                       | ~        |
| 4 | SemanticSearch                           | ✗        |
| 5 | VectorStoreError extension               | ✓        |

**Notes**: Partial match demotion helped - test case with "USearchError" now ranks #1.
Still missing the actual error handling code in USearchVectorStore.

---

### 3. `EmbeddingProvider`

**P@5: 4/5**

| # | Result                            | Relevant |
| - | --------------------------------- | -------- |
| 1 | InitSelections.embeddingProvider  | ✓        |
| 2 | MCPContext.embeddingProvider      | ✓        |
| 3 | MockEmbeddingProviderForCamelCase | ✓        |
| 4 | SearchTestMockEmbeddingProvider   | ✓        |
| 5 | UnavailableEmbeddingProvider      | ✓        |

**Notes**: All results contain EmbeddingProvider, but the **protocol definition itself** is missing!
This is a ranking issue - usages/mocks ranked higher than the source definition.

---

### 4. `rrfK`

**P@5: 5/5**

| # | Result                     | Relevant |
| - | -------------------------- | -------- |
| 1 | PartialConfig.rrfK         | ✓        |
| 2 | SearchOptions.rrfK         | ✓        |
| 3 | Config.rrfK                | ✓        |
| 4 | HybridSearchOptions.rrfK   | ✓        |
| 5 | IndexManager k calculation | ✓        |

**Notes**: Perfect - all direct references to rrfK parameter.

---

## Category B: Synonyms and Variants

### 5. `text vectorization`

**P@5: 4/4** (only 4 results returned)

| # | Result                  | Relevant |
| - | ----------------------- | -------- |
| 1 | USearchVectorStore      | ✓        |
| 2 | EmbeddingProvider.embed | ✓        |
| 3 | SearchTokenizationTests | ✓        |
| 4 | generateEmbedding       | ✓        |

**Notes**: Good semantic understanding - "vectorization" → embeddings/vectors.

---

### 6. `store vectors persistently`

**P@5: 5/5**

| # | Result                      | Relevant |
| - | --------------------------- | -------- |
| 1 | VectorStore protocol        | ✓        |
| 2 | IndexManager.save           | ✓        |
| 3 | VectorStore full definition | ✓        |
| 4 | VectorStoreMapping          | ✓        |
| 5 | testAddBatch                | ✓        |

**Notes**: Excellent semantic matching for persistence concepts.

---

### 7. `nearest neighbor search`

**P@5: 4/5** (v7: 3/5, **+1 improvement**)

| # | Result              | Relevant |
| - | ------------------- | -------- |
| 1 | USearchVectorStore  | ✓        |
| 2 | BM25Search          | ~        |
| 3 | HybridSearchEngine  | ✓        |
| 4 | SemanticSearch      | ✓        |
| 5 | searchWithThreshold | ✓        |

**Notes**: USearchVectorStore now #1 (doc mentions "approximate nearest neighbor").
BM25Search less relevant but still search-related.

---

### 8. `combine search results from different sources`

**P@5: 4/5**

| # | Result                | Relevant |
| - | --------------------- | -------- |
| 1 | BM25Search            | ✓        |
| 2 | HybridSearchEngine    | ✓        |
| 3 | SemanticSearch        | ✓        |
| 4 | SearchCommand.results | ~        |
| 5 | SearchResultTests     | ✓        |

**Notes**: HybridSearchEngine should ideally be #1 since it's the "combiner".

---

## Category C: Implementation Questions

### 9. `how does the search ranking work`

**P@5: 4/4** (only 4 results returned)

| # | Result             | Relevant |
| - | ------------------ | -------- |
| 1 | BM25Search         | ✓        |
| 2 | HybridSearchEngine | ✓        |
| 3 | SemanticSearch     | ✓        |
| 4 | BM25SearchTests    | ✓        |

**Notes**: Good coverage of ranking components.

---

### 10. `how are code chunks parsed and stored`

**P@5: 5/5**

| # | Result                     | Relevant |
| - | -------------------------- | -------- |
| 1 | ChunkStore protocol        | ✓        |
| 2 | DeclarationVisitor.chunks  | ✓        |
| 3 | MockChunkStore.chunks      | ✓        |
| 4 | MockChunkStoreWithSnippets | ✓        |
| 5 | AtomicIndexingStats        | ~        |

**Notes**: Excellent - ChunkStore first, parsing implementation follows.

---

### 11. `what happens when a file is indexed`

**P@5: 4/5**

| # | Result                    | Relevant |
| - | ------------------------- | -------- |
| 1 | IncrementalIndexer        | ✓        |
| 2 | FileIndexResult           | ✓        |
| 3 | IndexingResult            | ✓        |
| 4 | IndexingStats             | ✓        |
| 5 | needsIndexingChanged test | ✓        |

**Notes**: Good coverage of indexing flow.

---

### 12. `how are embedding failures handled`

**P@5: 4/5**

| # | Result                            | Relevant |
| - | --------------------------------- | -------- |
| 1 | EmbeddingBatcher                  | ✓        |
| 2 | EmbeddingBatcherErrorTests        | ✓        |
| 3 | vector1 test                      | ~        |
| 4 | EmbeddingProviderIntegrationTests | ✓        |
| 5 | UnavailableEmbeddingProvider      | ✓        |

**Notes**: Good error handling coverage.

---

## Category D: Patterns and Design

### 13. `actor pattern for thread safety`

**P@5: 5/5**

| # | Result                        | Relevant |
| - | ----------------------------- | -------- |
| 1 | TaskManager actor             | ✓        |
| 2 | FileWatcher actor             | ✓        |
| 3 | GracefulShutdownManager actor | ✓        |
| 4 | IndexManager actor            | ✓        |
| 5 | MCPServer actor               | ✓        |

**Notes**: Excellent - all results are actors demonstrating the pattern.

---

### 14. `what implements ChunkStore protocol`

**P@5: 5/5**

| # | Result                           | Relevant |
| - | -------------------------------- | -------- |
| 1 | ChunkStore protocol              | ✓        |
| 2 | ChunkStore full definition       | ✓        |
| 3 | GRDBChunkStore (implementation!) | ✓        |
| 4 | GRDBChunkStore full              | ✓        |
| 5 | MockChunkStore                   | ✓        |

**Notes**: Perfect - protocol and its implementations found.

---

### 15. `how are providers configured`

**P@5: 4/5**

| # | Result                           | Relevant |
| - | -------------------------------- | -------- |
| 1 | EmbeddingProviderRegistry.config | ✓        |
| 2 | ProvidersCommand.configuration   | ✓        |
| 3 | ProvidersCommand                 | ✓        |
| 4 | TierSection.provider             | ✓        |
| 5 | ActiveProviderManager            | ✓        |

**Notes**: Good coverage of provider configuration.

---

### 16. `where is caching used`

**P@5: 4/5**

| # | Result                         | Relevant |
| - | ------------------------------ | -------- |
| 1 | PartialConfig.cachePath        | ~        |
| 2 | Config.cachePath               | ~        |
| 3 | TOMLConfig.cache_path          | ~        |
| 4 | FollowUpGeneratorTests.caching | ✓        |
| 5 | GlobMatcher (LRU caching!)     | ✓        |

**Notes**: Mix of path configs and actual caching implementations.

---

## Category E: Cross-cutting Concerns

### 17. `async await concurrency patterns`

**P@5: 3/5**

| # | Result                          | Relevant |
| - | ------------------------------- | -------- |
| 1 | Config.maxConcurrentTasks       | ✓        |
| 2 | response test (async test data) | ~        |
| 3 | max_concurrent_tasks config     | ✓        |
| 4 | ExpandedQuery (async test data) | ~        |
| 5 | generateFollowUps async test    | ✓        |

**Notes**: Results are async-related but not demonstrating patterns.
Would benefit from finding actor definitions or Task usage examples.

---

### 18. `error types and their handling`

**P@5: 5/5**

| # | Result                  | Relevant |
| - | ----------------------- | -------- |
| 1 | ParseError enum         | ✓        |
| 2 | LLMError enum           | ✓        |
| 3 | IndexingStats.errors    | ✓        |
| 4 | IndexingResult.errors   | ✓        |
| 5 | LLMError LocalizedError | ✓        |

**Notes**: Good coverage of error types.

---

### 19. `TOML configuration loading and validation`

**P@5: 5/5**

| # | Result                | Relevant |
| - | --------------------- | -------- |
| 1 | TOMLConfigValidator   | ✓        |
| 2 | TOMLConfigLoader      | ✓        |
| 3 | TOMLConfig struct     | ✓        |
| 4 | tomlConfig constant   | ✓        |
| 5 | TOMLConfigLoaderTests | ✓        |

**Notes**: Perfect - all TOML-related code found.

---

### 20. `how is search engine tested`

**P@5: 5/5**

| # | Result               | Relevant |
| - | -------------------- | -------- |
| 1 | BM25Search           | ✓        |
| 2 | HybridSearchEngine   | ✓        |
| 3 | BM25SearchTestHelper | ✓        |
| 4 | BM25SearchTests      | ✓        |
| 5 | SearchResultTests    | ✓        |

**Notes**: Good mix of search engines and their tests.

---

## Summary Statistics

| Category          | Q1 | Q2 | Q3 | Q4 | Avg  |
| ----------------- | -- | -- | -- | -- | ---- |
| A: Exact          | 5  | 2  | 4  | 5  | 4.00 |
| B: Synonyms       | 4  | 5  | 4  | 4  | 4.25 |
| C: Implementation | 4  | 5  | 4  | 4  | 4.25 |
| D: Patterns       | 5  | 5  | 4  | 4  | 4.50 |
| E: Cross-cutting  | 3  | 5  | 5  | 5  | 4.50 |

**Overall Average P@5: 4.30**

## Key Findings

### Improvements from v7

1. **USearchError**: 0/5 → 2/5 - CamelCase partial match demotion is working
2. **nearest neighbor search**: 3/5 → 4/5 - USearchVectorStore now ranks #1

### Areas for Further Improvement

1. **Protocol definitions vs usages**: EmbeddingProvider protocol not in top results
2. **Conceptual queries**: "async await patterns" returns config values, not code examples
3. **Definition priority**: Source definitions should rank higher than test mocks

### Recommendations

- Consider boosting protocol/class definitions over property usages
- Weight source files higher than test files for conceptual queries
- Explore boosting files that define types vs files that use them
