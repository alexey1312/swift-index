# Implementation Tasks

## 1. RRF Fusion Improvements

- [x] 1.1 Implement hybrid scoring (rank + normalized score) in `RRFFusion.swift`
- [x] 1.2 Add `alpha` parameter for fusion control
- [x] 1.3 Increase fetch limit in `HybridSearchEngine.swift`

## 2. Protocol Conformance Indexing

- [x] 2.1 Add `conformances` field to `CodeChunk` model
- [x] 2.2 Implement conformance extraction in `SwiftSyntaxParser`
- [x] 2.3 Update `GRDBChunkStore` schema (v7 migration) to store and index conformances

## 3. Description Indexing

- [x] 3.1 Add `generated_description` column to database schema
- [x] 3.2 Add `generated_description` to FTS5 index
- [x] 3.3 Update BM25 search to include description field

## 4. Description Generation

- [x] 4.1 Update `DescriptionGenerator` prompt to include conformances
- [x] 4.2 Update system prompt to encourage mentioning protocols

## 5. Semantic Search Re-ranking

- [x] 5.1 Implement metadata-aware re-ranking in `SemanticSearch.swift`
- [x] 5.2 Add boost logic for "implements/conforms" intent
