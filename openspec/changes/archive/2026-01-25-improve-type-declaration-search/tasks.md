# Implementation Tasks

## 1. Type Declaration Chunks

- [x] 1.1 Add `isTypeDeclaration` flag to `CodeChunk` model
- [x] 1.2 Create separate chunks for type declarations in `SwiftSyntaxParser`
- [x] 1.3 Ensure type declaration chunks include full signature with conformances
- [x] 1.4 Add `type_declaration` column to GRDBChunkStore schema (v8 migration)
- [x] 1.5 Index type declarations in FTS5 with higher weight

## 2. Exact Symbol Matching

- [x] 2.1 Add `exactSymbolMatch` field to `SearchResult`
- [x] 2.2 Implement exact symbol detection in `HybridSearchEngine`
- [x] 2.3 Add `exact_symbol_boost` (2.0x) for rare terms (< 10 occurrences)
- [x] 2.4 Add term frequency check before applying boost

## 3. Conformance-Aware Ranking

- [x] 3.1 Create conformance index table in GRDBChunkStore
- [x] 3.2 Implement `findConformingTypes(protocol:)` method
- [x] 3.3 Add conformance lookup to "implements X" query detection
- [x] 3.4 Boost conforming types to top of results (3.0x boost)

## 4. Testing

- [x] 4.1 Add tests for type declaration chunk creation
- [x] 4.2 Add tests for exact symbol matching (via storage tests)
- [x] 4.3 Add tests for conformance-aware ranking
- [ ] 4.4 Run benchmark v3 to verify improvements

## 5. Documentation

- [ ] 5.1 Update CLAUDE.md with new search features
- [ ] 5.2 Document conformance search syntax (if added)
