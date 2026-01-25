# Tasks: Improve Exact Term Search

## 1. Term Frequency Lookup

- [x] 1.1 Add `getTermFrequency(term: String) -> Int` to ChunkStore protocol
- [x] 1.2 Implement in GRDBChunkStore using FTS5 term frequency
- [x] 1.3 Cache term frequencies during search session (LRU, 100 entries)
- [x] 1.4 Add tests for term frequency lookup

## 2. Exact Symbol Match Boost

- [x] 2.1 Add `isRareTerm(term: String, threshold: Int = 10)` method
- [x] 2.2 Implement 2.5x boost in HybridSearchEngine for exact symbol match
- [x] 2.3 Apply boost only when term is rare (< threshold occurrences)
- [x] 2.4 Add tests for exact symbol boost

## 3. Standard Protocol Extension Demotion

- [x] 3.1 Define `standardProtocols` set: Comparable, Equatable, Hashable, Codable, Sendable, CustomStringConvertible
- [x] 3.2 Add `isConceptualQuery(query: String)` detection for "how", "what", "where" patterns
- [x] 3.3 Apply 0.5x demotion for extension chunks conforming to standard protocols in conceptual queries
- [x] 3.4 Add tests for extension demotion

## 4. Source/Test Ranking Boost

- [x] 4.1 Add path-based boost in HybridSearchEngine.search()
- [x] 4.2 Apply 1.1x boost for paths containing `/Sources/`
- [x] 4.3 ~~Make configurable via `search.source_boost` (default: 1.1)~~ (deferred - hardcoded values work well)
- [x] 4.4 Add tests for source boost

## 5. Public Modifier Boost

- [x] 5.1 Check signature starts with "public" in re-ranking
- [x] 5.2 Apply 1.1x boost for public declarations
- [x] 5.3 Add tests for public modifier boost

## 6. Integration Testing

- [x] 6.1 Run benchmark v3 queries with new ranking
- [x] 6.2 Verify USearchError returns relevant results
- [x] 6.3 Verify nearest neighbor search improved
- [x] 6.4 Verify GRDBChunkStore ranks #1 for ChunkStore queries

## 7. Documentation

- [x] 7.1 Update CLAUDE.md with new boost parameters
- [x] 7.2 ~~Add configuration options to config.toml example~~ (deferred - hardcoded values work well)
