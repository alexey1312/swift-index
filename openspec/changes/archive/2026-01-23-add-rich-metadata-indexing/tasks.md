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

## Phase 2: Info Snippets (COMPLETED)

### 2.1 InfoSnippet Model

- [x] 2.1.1 Create `InfoSnippet.swift` model with fields: `id`, `chunkId`, `content`, `breadcrumb`, `tokenCount`, etc.
- [x] 2.1.2 Write tests for `InfoSnippet` model
- [x] 2.1.3 Add `InfoSnippetStore` protocol

### 2.2 Database Support

- [x] 2.2.1 Add `info_snippets` table in v3 migration
- [x] 2.2.2 Add FTS5 index `info_snippets_fts` for documentation search
- [x] 2.2.3 Implement CRUD operations for info snippets
- [x] 2.2.4 Write storage tests

### 2.3 Parser Extraction

- [x] 2.3.1 Add `ParseResult.successWithSnippets` case for combined chunk/snippet results
- [x] 2.3.2 Extract Markdown sections as InfoSnippet in `TreeSitterParser`
- [x] 2.3.3 Link InfoSnippet to parent CodeChunk via `chunkId`
- [x] 2.3.4 Update all production code to handle new ParseResult variant
- [x] 2.3.5 Write extraction tests

### 2.4 Search Integration

- [x] 2.4.1 Add `searchInfoSnippets()` method to `HybridSearchEngine`
- [x] 2.4.2 Create `InfoSnippetSearchResult` model for search results
- [x] 2.4.3 Create `SearchDocsTool` MCP tool for documentation search
- [x] 2.4.4 Add formatters for TOON, JSON, and human-readable output
- [x] 2.4.5 Write search integration tests

**Gate**: Build + all tests pass ✓

---

## Phase 3: Advanced Features (COMPLETED)

### 3.1 Parallel Indexing

- [x] 3.1.1 Add `TaskGroup`-based parallel parsing in `IndexCommand`
- [x] 3.1.2 Add `maxConcurrentTasks` configuration option (default: CPU cores)
- [x] 3.1.3 Add thread-safe `AtomicIndexingStats` for parallel progress tracking
- [x] 3.1.4 Implement bounded concurrency (sliding window pattern)

### 3.2 Content-Based Change Detection

- [x] 3.2.1 Add `contentHash` field to `CodeChunk` (SHA-256)
- [x] 3.2.2 Add v4 migration for `content_hash` column in `GRDBChunkStore`
- [x] 3.2.3 Add `getByContentHashes()` method to `ChunkStore` protocol
- [x] 3.2.4 Add `get()` method to `VectorStore` protocol for vector retrieval
- [x] 3.2.5 Implement `reindexWithChangeDetection()` in `IndexManager`
- [x] 3.2.6 Update `IndexCommand.indexFile()` to use change detection
- [x] 3.2.7 Add `ReindexResult` struct for tracking reuse statistics
- [x] 3.2.8 Write change detection tests

### 3.3 LLM Description Generation

- [x] 3.3.1 Add `--generate-descriptions` CLI flag
- [x] 3.3.2 Implement offline batch generation via LLM providers
- [x] 3.3.3 Store `generatedDescription` in CodeChunk (v5 migration)
- [x] 3.3.4 Write generation tests

**Gate**: Build + all tests pass ✓

---

## Phase 4: LLM Code Research (COMPLETED)

### 4.1 LLM Provider Protocol & Models

- [x] 4.1.1 Create `LLMProvider` protocol in `Protocols/LLMProvider.swift`
- [x] 4.1.2 Create `LLMMessage` model (role + content) in `LLM/LLMMessage.swift`
- [x] 4.1.3 Create `LLMProviderChain` for fallback handling in `LLM/LLMProviderChain.swift`
- [x] 4.1.4 Add `SearchEnhancementConfig` struct to `Config.swift` (nested under `SearchConfig`)
- [x] 4.1.5 Update `TOMLConfigLoader` to parse `[search.enhancement]` section
- [x] 4.1.6 Write protocol tests

### 4.2 CLI Providers (Claude Code & Codex)

- [x] 4.2.1 Implement `ClaudeCodeCLIProvider` with subprocess invocation
- [x] 4.2.2 Implement `CodexCLIProvider` with reasoning effort support
- [x] 4.2.3 Add CLI availability detection
- [x] 4.2.4 Handle timeouts and errors gracefully
- [x] 4.2.5 Write integration tests (mocked subprocess)

### 4.3 API Providers (Ollama & OpenAI)

- [x] 4.3.1 Implement `OllamaLLMProvider` (HTTP API)
- [x] 4.3.2 Implement `OpenAILLMProvider` (HTTP API)
- [x] 4.3.3 Add model configuration support
- [x] 4.3.4 Write provider tests

### 4.4 Query Enhancement Features

- [x] 4.4.1 Create `QueryExpander` with prompt templates
- [x] 4.4.2 Integrate query expansion into `HybridSearchEngine`
- [x] 4.4.3 Add caching for common expansions
- [x] 4.4.4 Add `--expand-query` flag to `SearchCommand`
- [x] 4.4.5 Write expansion tests

### 4.5 Result Synthesis Features

- [x] 4.5.1 Create `ResultSynthesizer` for multi-result summaries
- [x] 4.5.2 Create `FollowUpGenerator` for suggested queries
- [x] 4.5.3 Integrate into MCP `SearchCodeTool` response
- [x] 4.5.4 Add synthesis to CLI output (optional flag)
- [x] 4.5.5 Write synthesis tests

### 4.6 Integration & Documentation

- [x] 4.6.1 Update `IndexManager` to initialize LLM providers (implemented in MCPContext instead - better architectural fit)
- [x] 4.6.2 Add `[search.enhancement]` section to `generateConfigContent()` in `InitCommand.swift`
- [x] 4.6.3 Add commented examples for all LLM providers (claude-code-cli, codex-cli, ollama, openai)
- [x] 4.6.4 Add dual-tier (utility/synthesis) config examples with timeouts
- [x] 4.6.5 Write end-to-end integration tests
- [x] 4.6.6 Benchmark query latency with/without LLM

**Gate**: Build + all tests pass ✓

---

## Phase 5: Documentation Update (COMPLETED)

### 5.1 User Documentation

- [x] 5.1.1 Update `README.md` with all new features (metadata, info snippets, LLM)
- [x] 5.1.2 Create `docs/search-enhancement.md` — LLM provider configuration guide
- [x] 5.1.3 Create `docs/search-features.md` — query expansion & synthesis docs
- [x] 5.1.4 Add usage examples for each new CLI flag

### 5.2 Developer Documentation

- [x] 5.2.1 Update `CLAUDE.md` project guide with new commands/architecture
- [x] 5.2.2 Document new protocols (`LLMProvider`, `InfoSnippetStore`)
- [x] 5.2.3 Add inline documentation to config template in `init` command

### 5.3 Release Preparation

- [x] 5.3.1 Update CHANGELOG with all phases
- [x] 5.3.2 Review and update Homebrew formula description (auto-updates via workflow)
- [x] 5.3.3 Final review of all doc links and references

**Gate**: Documentation complete and reviewed ✓

---

## Summary

| Phase | Status    | Tasks | Tests Added |
| ----- | --------- | ----- | ----------- |
| 1     | COMPLETED | 20/20 | ~15         |
| 2     | COMPLETED | 18/18 | ~12         |
| 3     | COMPLETED | 16/16 | ~12         |
| 4     | COMPLETED | 27/27 | ~25         |
| 5     | COMPLETED | 10/10 | 0           |

**Total**: 91/91 tasks completed.
