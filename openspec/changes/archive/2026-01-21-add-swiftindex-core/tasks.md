# Tasks: SwiftIndex Core Implementation

## Configuration
- **Parallelism:** 2 агента
- **Approach:** TDD (Test-Driven Development)
- **Gates:** Build + Tests must pass at each checkpoint

---

## Phase 0: Foundation (BLOCKING)

> All subsequent phases depend on Phase 0 completion.
> **Verification:** `swift build` and `swift test` succeed

### 0.1 Package Setup
- [x] 0.1.1 Create `Package.swift` with all dependencies
- [x] 0.1.2 Verify `swift package resolve` succeeds
- [x] 0.1.3 Create target structure (SwiftIndexCore, SwiftIndexMCP, swiftindex)
- [x] 0.1.4 Create test targets (SwiftIndexCoreTests, IntegrationTests)

### 0.2 Core Protocols
- [x] 0.2.1 Define `EmbeddingProvider` protocol
- [x] 0.2.2 Define `Parser` protocol
- [x] 0.2.3 Define `SearchEngine` protocol
- [x] 0.2.4 Define `ConfigLoader` protocol
- [x] 0.2.5 Define `ChunkStore` protocol
- [x] 0.2.6 Define `VectorStore` protocol

### 0.3 Core Models
- [x] 0.3.1 Define `CodeChunk` struct
- [x] 0.3.2 Define `SearchResult` struct
- [x] 0.3.3 Define `ParseResult` enum
- [x] 0.3.4 Define `Config` struct with all fields
- [x] 0.3.5 Define `ChunkKind` enum
- [x] 0.3.6 Define `ProviderError` enum

### 0.4 Test Infrastructure
- [x] 0.4.1 Create test target directory structure
- [x] 0.4.2 Create `Tests/Fixtures/` directory
- [x] 0.4.3 Create Swift fixture files
- [x] 0.4.4 Create ObjC fixture files
- [x] 0.4.5 Create JSON/YAML fixture files
- [x] 0.4.6 Create TOML config fixtures

### 0.5 Gate: Foundation Complete
- [x] **GATE 0:** `swift build` succeeds with all dependencies
- [x] **GATE 0:** `swift test` runs (0 tests passing is OK)
- [x] **GATE 0:** All protocols compile without errors

---

## Phase 1: Core Components (PARALLEL - 2 Agents)

### Agent 1 Track: Configuration + SwiftSyntax

#### Track A: Configuration Layer (Agent 1)

> **TDD:** Write tests first, then implement

##### A.1 Configuration Tests
- [x] A.1.1 Write `test_loadDefaultConfig()`
- [x] A.1.2 Write `test_loadProjectConfig()`
- [x] A.1.3 Write `test_envOverridesProject()`
- [x] A.1.4 Write `test_cliOverridesEnv()`
- [x] A.1.5 Write `test_mergesPriority()`
- [x] A.1.6 Write `test_missingConfigUsesDefaults()`

##### A.2 Configuration Implementation
- [x] A.2.1 Implement `Config.swift` with all TOML fields
- [x] A.2.2 Implement `TOMLConfigLoader.swift`
- [x] A.2.3 Implement `EnvironmentLoader.swift`
- [x] A.2.4 Implement `ConfigMerger.swift`
- [x] A.2.5 Implement CLI config parsing

##### A.3 Gate: Configuration Complete
- [x] **GATE A:** All 6 config tests pass
- [x] **GATE A:** Can load `.swiftindex.toml` file
- [x] **GATE A:** Environment variables override config

---

#### Track B: SwiftSyntax Parsing (Agent 1)

> **TDD:** Write tests first, then implement

##### B.1 SwiftSyntax Tests
- [x] B.1.1 Write `test_parseFunctionDecl()`
- [x] B.1.2 Write `test_parseClassDecl()`
- [x] B.1.3 Write `test_parseStructDecl()`
- [x] B.1.4 Write `test_parseProtocolDecl()`
- [x] B.1.5 Write `test_parseExtensionDecl()`
- [x] B.1.6 Write `test_parseActorDecl()`
- [x] B.1.7 Write `test_parseMacroDecl()`
- [x] B.1.8 Write `test_extractsSymbolNames()`
- [x] B.1.9 Write `test_extractsLineNumbers()`

##### B.2 SwiftSyntax Implementation
- [x] B.2.1 Implement `SwiftSyntaxParser.swift`
- [x] B.2.2 Implement `ChunkingVisitor.swift` base
- [x] B.2.3 Add function declaration visiting
- [x] B.2.4 Add type declaration visiting (class, struct, enum)
- [x] B.2.5 Add protocol/extension visiting
- [x] B.2.6 Add actor/macro visiting
- [x] B.2.7 Implement symbol extraction
- [x] B.2.8 Implement reference extraction

##### B.3 Gate: SwiftSyntax Complete
- [x] **GATE B:** All 9 SwiftSyntax tests pass
- [x] **GATE B:** Can parse any valid Swift file
- [x] **GATE B:** Chunks have correct line numbers

---

### Agent 2 Track: tree-sitter + Embeddings

#### Track C: tree-sitter Parsing (Agent 2)

> **TDD:** Write tests first, then implement

##### C.1 tree-sitter Tests
- [x] C.1.1 Write `test_parseObjCInterface()`
- [x] C.1.2 Write `test_parseObjCImplementation()`
- [x] C.1.3 Write `test_parseObjCMethodDefinition()`
- [x] C.1.4 Write `test_parseCFunction()`
- [x] C.1.5 Write `test_parseCStruct()`
- [x] C.1.6 Write `test_parseJSONObject()`
- [x] C.1.7 Write `test_parseJSONArray()`
- [x] C.1.8 Write `test_parseYAMLMapping()`
- [x] C.1.9 Write `test_parseYAMLSequence()`
- [x] C.1.10 Write `test_parseMarkdownSection()`
- [x] C.1.11 Write `test_parseMarkdownCodeBlock()`

##### C.2 HybridParser Tests
- [x] C.2.1 Write `test_routesSwiftToSwiftSyntax()`
- [x] C.2.2 Write `test_routesObjCToTreeSitter()`
- [x] C.2.3 Write `test_routesUnknownToPlainText()`

##### C.3 tree-sitter Implementation
- [x] C.3.1 Implement `LanguageRegistry.swift` (pattern-based fallback)
- [x] C.3.2 Implement `TreeSitterParser.swift` base
- [x] C.3.3 Add ObjC grammar support
- [x] C.3.4 Add C/C++ grammar support
- [x] C.3.5 Add JSON grammar support
- [x] C.3.6 Add YAML grammar support
- [x] C.3.7 Add Markdown grammar support
- [x] C.3.8 Implement `HybridParser.swift` router
- [x] C.3.9 Implement `PlainTextParser.swift` fallback

##### C.4 Gate: tree-sitter Complete
- [x] **GATE C:** All 14 tree-sitter tests pass
- [x] **GATE C:** HybridParser routes correctly by extension
- [x] **GATE C:** Unknown extensions fallback to plain text

---

#### Track D: Embedding Providers (Agent 2)

> **TDD:** Write tests first, then implement

##### D.1 Provider Protocol Tests
- [x] D.1.1 Write `test_isAvailable_returnsCorrectStatus()`
- [x] D.1.2 Write `test_embed_singleText_returnsVector()`
- [x] D.1.3 Write `test_embed_batch_returnsMultipleVectors()`
- [x] D.1.4 Write `test_dimension_matchesExpected()`

##### D.2 Provider Chain Tests
- [x] D.2.1 Write `test_usesFirstAvailableProvider()`
- [x] D.2.2 Write `test_fallbackOnUnavailable()`
- [x] D.2.3 Write `test_allUnavailable_throws()`
- [x] D.2.4 Write `test_swiftEmbeddings_alwaysAvailable()`

##### D.3 Mock Provider
- [x] D.3.1 Implement `MockEmbeddingProvider.swift`

##### D.4 Provider Implementations
- [x] D.4.1 Implement `MLXEmbeddingProvider.swift`
- [x] D.4.2 Implement `OllamaEmbeddingProvider.swift`
- [x] D.4.3 Implement `SwiftEmbeddingsProvider.swift`
- [x] D.4.4 Implement `VoyageProvider.swift`
- [x] D.4.5 Implement `OpenAIProvider.swift`
- [x] D.4.6 Implement `EmbeddingService.swift` (chain orchestrator)
- [x] D.4.7 Implement `ModelDownloader.swift`

##### D.5 Gate: Embeddings Complete
- [x] **GATE D:** All 8 embedding tests pass
- [x] **GATE D:** Provider chain correctly falls back
- [x] **GATE D:** SwiftEmbeddings always returns embeddings

---

## Phase 2: Storage Layer

> **Dependencies:** Phase 1 complete (all protocols defined)

### Track E: Storage

##### E.1 MetadataStore Tests
- [x] E.1.1 Write `test_insertChunk()`
- [x] E.1.2 Write `test_getChunk()`
- [x] E.1.3 Write `test_updateChunk()`
- [x] E.1.4 Write `test_deleteChunk()`
- [x] E.1.5 Write `test_searchFTS5()`

##### E.2 VectorIndex Tests
- [x] E.2.1 Write `test_addVector()`
- [x] E.2.2 Write `test_searchVector_returnsSimilar()`
- [x] E.2.3 Write `test_deleteVector()`
- [x] E.2.4 Write `test_persistToDisk()`

##### E.3 Indexer Tests
- [x] E.3.1 Write `test_indexFile_createsChunks()`
- [x] E.3.2 Write `test_indexDirectory_recursivelyIndexes()`
- [x] E.3.3 Write `test_incrementalIndex_onlyNewFiles()`

##### E.4 Storage Implementation
- [x] E.4.1 Implement `MetadataStore.swift` with GRDB
- [x] E.4.2 Implement GRDB migrations
- [x] E.4.3 Implement FTS5 virtual table
- [x] E.4.4 Implement `VectorIndex.swift` with USearch
- [x] E.4.5 Implement `Indexer.swift` orchestrator
- [x] E.4.6 Implement file hash tracking
- [x] E.4.7 Implement incremental indexing logic

##### E.5 Gate: Storage Complete
- [x] **GATE E:** All 12 storage tests pass
- [x] **GATE E:** Can index directory and retrieve chunks
- [x] **GATE E:** Incremental indexing skips unchanged files

---

## Phase 3: Search Engine

> **Dependencies:** Phase 2 complete (storage working)

### Track F: Search

##### F.1 Search Tests
- [x] F.1.1 Write `test_bm25Search_returnsRankedResults()`
- [x] F.1.2 Write `test_bm25Search_emptyQuery_returnsEmpty()`
- [x] F.1.3 Write `test_semanticSearch_returnsSimilarChunks()`
- [x] F.1.4 Write `test_semanticSearch_respectsLimit()`
- [x] F.1.5 Write `test_rrfFusion_combinesResults()`
- [x] F.1.6 Write `test_rrfFusion_handlesDisjointSets()`
- [x] F.1.7 Write `test_rrfFusion_respectsK()`
- [x] F.1.8 Write `test_multiHop_followsReferences()`
- [x] F.1.9 Write `test_multiHop_respectsDepth()`
- [x] F.1.10 Write `test_hybridSearch_usesWeightedCombination()`
- [x] F.1.11 Write `test_hybridSearch_filtersByPath()`

##### F.2 Search Implementation
- [x] F.2.1 Implement `BM25Search.swift`
- [x] F.2.2 Implement `SemanticSearch.swift`
- [x] F.2.3 Implement `RRFFusion.swift`
- [x] F.2.4 Implement `MultiHopSearch.swift`
- [x] F.2.5 Implement `HybridSearchEngine.swift`
- [x] F.2.6 Add path filtering support
- [x] F.2.7 Add configurable weights

##### F.3 Gate: Search Complete
- [x] **GATE F:** All 11 search tests pass
- [x] **GATE F:** Hybrid search returns relevant results
- [x] **GATE F:** Multi-hop follows references correctly

---

## Phase 4: Application Layer (PARALLEL - 2 Agents)

### Agent 1 Track: MCP Server + CLI

#### Track G: MCP Server (Agent 1)

##### G.1 MCP Implementation
- [x] G.1.1 Implement `MCPServer.swift` base
- [x] G.1.2 Implement JSON-RPC handling
- [x] G.1.3 Implement `IndexCodebaseTool.swift`
- [x] G.1.4 Implement `SearchCodeTool.swift`
- [x] G.1.5 Implement `CodeResearchTool.swift`
- [x] G.1.6 Implement `WatchCodebaseTool.swift`

##### G.2 MCP Tests
- [x] G.2.1 Write `test_indexCodebase_tool()`
- [x] G.2.2 Write `test_searchCode_tool()`
- [x] G.2.3 Write `test_codeResearch_tool()`
- [x] G.2.4 Write `test_watchCodebase_tool()`

##### G.3 Gate: MCP Complete
- [x] **GATE G:** All 4 MCP tools respond to JSON-RPC
- [x] **GATE G:** Tools return valid MCP responses

---

#### Track H: CLI Commands (Agent 1)

##### H.1 CLI Implementation
- [x] H.1.1 Implement `main.swift` with ArgumentParser
- [x] H.1.2 Implement `IndexCommand.swift`
- [x] H.1.3 Implement `SearchCommand.swift`
- [x] H.1.4 Implement `WatchCommand.swift`
- [x] H.1.5 Implement `ProvidersCommand.swift`
- [x] H.1.6 Implement `InstallClaudeCodeCommand.swift`
- [x] H.1.7 Implement `InstallCodexCommand.swift`
- [x] H.1.8 Implement `InstallCursorCommand.swift`
- [x] H.1.9 Implement `InitCommand.swift`

##### H.2 CLI Tests
- [x] H.2.1 Write `test_indexCommand()`
- [x] H.2.2 Write `test_searchCommand()`
- [x] H.2.3 Write `test_installClaudeCode()`

##### H.3 Gate: CLI Complete
- [x] **GATE H:** `swiftindex index` works E2E
- [x] **GATE H:** `swiftindex search` returns results
- [x] **GATE H:** `swiftindex install-claude-code` creates config

---

### Agent 2 Track: Watch Mode

#### Track I: Watch Mode (Agent 2)

##### I.1 Watch Tests
- [x] I.1.1 Write `test_detectsFileCreation()`
- [x] I.1.2 Write `test_detectsFileModification()`
- [x] I.1.3 Write `test_detectsFileDeletion()`
- [x] I.1.4 Write `test_debounces_rapidChanges()`
- [x] I.1.5 Write `test_incrementalReindex()`

##### I.2 Watch Implementation
- [x] I.2.1 Implement `FileWatcher.swift`
- [x] I.2.2 Implement debouncing logic
- [x] I.2.3 Implement `IncrementalIndexer.swift`
- [x] I.2.4 Integrate with WatchCommand

##### I.3 Gate: Watch Complete
- [x] **GATE I:** File changes detected within 500ms
- [x] **GATE I:** Debouncing prevents rapid re-indexes
- [x] **GATE I:** Incremental re-index updates only changed files

---

## Phase 5: Integration and Polish

### J.1 Integration Tests
- [x] J.1.1 Write E2E test: index → search flow
- [x] J.1.2 Write E2E test: watch → modify → search
- [x] J.1.3 Write E2E test: MCP server full workflow
- [x] J.1.4 Write E2E test: provider fallback chain

### J.2 Performance Tests
- [x] J.2.1 Benchmark indexing 1K files
- [x] J.2.2 Benchmark indexing 10K files
- [x] J.2.3 Benchmark search latency
- [x] J.2.4 Profile memory usage

### J.3 Documentation
- [x] J.3.1 Update README.md
- [x] J.3.2 Document configuration options
- [x] J.3.3 Document MCP tools
- [x] J.3.4 Add usage examples

### J.4 Distribution
- [x] J.4.1 Create Homebrew formula
- [x] J.4.2 Create release workflow
- [x] J.4.3 Add versioning

### J.5 Final Gate
- [x] **FINAL GATE:** All 60+ tests pass (260 tests passed)
- [x] **FINAL GATE:** `swiftindex index` + `swiftindex search "auth"` works
- [x] **FINAL GATE:** `swiftindex install-claude-code` creates valid config
- [x] **FINAL GATE:** MCP server responds to all 4 tools
- [x] **FINAL GATE:** Watch mode detects and re-indexes changes

---

## Test Summary

| Phase | Track | Tests | Description |
|-------|-------|-------|-------------|
| 1 | A | 6 | Configuration loading |
| 1 | B | 9 | SwiftSyntax parsing |
| 1 | C | 14 | tree-sitter + HybridParser |
| 1 | D | 8 | Embedding providers |
| 2 | E | 12 | Storage (GRDB + USearch) |
| 3 | F | 11 | Hybrid search engine |
| 4 | G | 4 | MCP tools |
| 4 | H | 3 | CLI commands |
| 4 | I | 5 | Watch mode |
| 5 | J | 4 | Integration E2E |
| **TOTAL** | | **260** | (actual test count as of final gate) |

---

## Agent Assignment Summary

| Phase | Agent 1 | Agent 2 |
|-------|---------|---------|
| 0 | Foundation (both) | Foundation (both) |
| 1 | Track A + B (Config + SwiftSyntax) | Track C + D (tree-sitter + Embeddings) |
| 2 | Track E (Storage) | Support |
| 3 | Support | Track F (Search) |
| 4 | Track G + H (MCP + CLI) | Track I (Watch) |
| 5 | Polish (both) | Polish (both) |
