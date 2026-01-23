# Tasks: Rich Metadata Indexing

## Phase 1: Extended CodeChunk (COMPLETED)

### 1.1 CodeChunk Model Extension

- [x] 1.1.1 Add fields to `CodeChunk.swift`: `docComment`, `signature`, `breadcrumb`, `tokenCount`, `language`
- [x] 1.1.2 Add `detectLanguage(from:)` static helper
- [x] 1.1.3 Add default values and backward-compatible initializer
- [x] 1.1.4 Write tests for new fields in `SwiftSyntaxParserTests.swift`

### 1.2 Database Schema Update

- [x] 1.2.1 Add v2 migration `v2_rich_metadata` in `GRDBChunkStore.swift`
- [x] 1.2.2 Add new columns: `doc_comment`, `signature`, `breadcrumb`, `token_count`, `language`
- [x] 1.2.3 Recreate FTS5 index with `doc_comment` column
- [x] 1.2.4 Update `ChunkRecord` to handle new fields
- [x] 1.2.5 Write storage tests for new fields in `StorageTests.swift`

### 1.3 SwiftSyntaxParser Updates

- [x] 1.3.1 Pass `docComment` to CodeChunk in `addChunk()`
- [x] 1.3.2 Pass `signature` to CodeChunk in `addChunk()`
- [x] 1.3.3 Add `buildBreadcrumb()` method using `typeStack`
- [x] 1.3.4 Calculate `tokenCount` as `content.count / 4`
- [x] 1.3.5 Write tests for metadata extraction

### 1.4 TreeSitterParser Updates

- [x] 1.4.1 Add `detectLanguage(from:)` method
- [x] 1.4.2 Add `extractDocComment(before:in:)` method
- [x] 1.4.3 Build breadcrumb for Markdown sections from header stack
- [x] 1.4.4 Pass metadata to CodeChunk constructor
- [x] 1.4.5 Write tests for TreeSitter metadata extraction

### 1.5 Output Formatters

- [x] 1.5.1 Update `SearchCommand.swift` JSON output with new fields
- [x] 1.5.2 Update `SearchCommand.swift` human-readable output with docComment/signature
- [x] 1.5.3 Update `SearchCommand.swift` TOON output with meta/docs sections
- [x] 1.5.4 Update `SearchCodeTool.swift` (MCP) with same changes
- [x] 1.5.5 Integration test: full index → search cycle with docComment

**Gate**: Build + all tests pass ✓

---

## Phase 2: Info Snippets (PENDING)

### 2.1 InfoSnippet Model

- [ ] 2.1.1 Create `InfoSnippet.swift` model with fields: `id`, `chunkId`, `content`, `breadcrumb`, `tokenCount`
- [ ] 2.1.2 Write tests for `InfoSnippet` model
- [ ] 2.1.3 Add `InfoSnippetStore` protocol

### 2.2 Database Support

- [ ] 2.2.1 Add `info_snippets` table in v3 migration
- [ ] 2.2.2 Add FTS5 index `info_snippets_fts` for documentation search
- [ ] 2.2.3 Implement CRUD operations for info snippets
- [ ] 2.2.4 Write storage tests

### 2.3 Parser Extraction

- [ ] 2.3.1 Extract standalone doc comments as InfoSnippet in `SwiftSyntaxParser`
- [ ] 2.3.2 Extract Markdown sections as InfoSnippet in `TreeSitterParser`
- [ ] 2.3.3 Link InfoSnippet to parent CodeChunk via `chunkId`
- [ ] 2.3.4 Write extraction tests

### 2.4 Search Integration

- [ ] 2.4.1 Add `searchInfoSnippets()` method to `HybridSearchEngine`
- [ ] 2.4.2 Integrate info snippet results into main `search()` method
- [ ] 2.4.3 Update output formatters to include info snippets
- [ ] 2.4.4 Write search integration tests

**Gate**: Build + all tests pass

---

## Phase 3: Advanced Features (PENDING)

### 3.1 Parallel Indexing

- [ ] 3.1.1 Add `TaskGroup`-based parallel parsing in `IndexManager`
- [ ] 3.1.2 Add `maxConcurrentTasks` configuration option
- [ ] 3.1.3 Write concurrency tests
- [ ] 3.1.4 Benchmark sequential vs parallel indexing

### 3.2 Content-Based Change Detection

- [ ] 3.2.1 Add `contentHash` field to `CodeChunk`
- [ ] 3.2.2 Implement skip logic for unchanged chunks during re-index
- [ ] 3.2.3 Write change detection tests

### 3.3 LLM Description Generation (Optional)

- [ ] 3.3.1 Add `--generate-descriptions` CLI flag
- [ ] 3.3.2 Implement offline batch generation via MLX
- [ ] 3.3.3 Store `generatedDescription` in CodeChunk
- [ ] 3.3.4 Write generation tests

**Gate**: Build + all tests pass

---

## Summary

| Phase | Status    | Tasks | Tests Added |
| ----- | --------- | ----- | ----------- |
| 1     | COMPLETED | 20/20 | ~15         |
| 2     | PENDING   | 0/16  | 0           |
| 3     | PENDING   | 0/11  | 0           |
