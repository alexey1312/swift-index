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
- [ ] 0.1.1 Create `Package.swift` with all dependencies
- [ ] 0.1.2 Verify `swift package resolve` succeeds
- [ ] 0.1.3 Create target structure (SwiftIndexCore, SwiftIndexMCP, swiftindex)
- [ ] 0.1.4 Create test targets (SwiftIndexCoreTests, IntegrationTests)

### 0.2 Core Protocols
- [ ] 0.2.1 Define `EmbeddingProvider` protocol
- [ ] 0.2.2 Define `Parser` protocol
- [ ] 0.2.3 Define `SearchEngine` protocol
- [ ] 0.2.4 Define `ConfigLoader` protocol
- [ ] 0.2.5 Define `ChunkStore` protocol
- [ ] 0.2.6 Define `VectorStore` protocol

### 0.3 Core Models
- [ ] 0.3.1 Define `CodeChunk` struct
- [ ] 0.3.2 Define `SearchResult` struct
- [ ] 0.3.3 Define `ParseResult` enum
- [ ] 0.3.4 Define `Config` struct with all fields
- [ ] 0.3.5 Define `ChunkKind` enum
- [ ] 0.3.6 Define `ProviderError` enum

### 0.4 Test Infrastructure
- [ ] 0.4.1 Create test target directory structure
- [ ] 0.4.2 Create `Tests/Fixtures/` directory
- [ ] 0.4.3 Create Swift fixture files
- [ ] 0.4.4 Create ObjC fixture files
- [ ] 0.4.5 Create JSON/YAML fixture files
- [ ] 0.4.6 Create TOML config fixtures

### 0.5 Gate: Foundation Complete
- [ ] **GATE 0:** `swift build` succeeds with all dependencies
- [ ] **GATE 0:** `swift test` runs (0 tests passing is OK)
- [ ] **GATE 0:** All protocols compile without errors

---

## Phase 1: Core Components (PARALLEL - 2 Agents)

### Agent 1 Track: Configuration + SwiftSyntax

#### Track A: Configuration Layer (Agent 1)

> **TDD:** Write tests first, then implement

##### A.1 Configuration Tests
- [ ] A.1.1 Write `test_loadDefaultConfig()`
- [ ] A.1.2 Write `test_loadProjectConfig()`
- [ ] A.1.3 Write `test_envOverridesProject()`
- [ ] A.1.4 Write `test_cliOverridesEnv()`
- [ ] A.1.5 Write `test_mergesPriority()`
- [ ] A.1.6 Write `test_missingConfigUsesDefaults()`

##### A.2 Configuration Implementation
- [ ] A.2.1 Implement `Config.swift` with all TOML fields
- [ ] A.2.2 Implement `TOMLConfigLoader.swift`
- [ ] A.2.3 Implement `EnvironmentLoader.swift`
- [ ] A.2.4 Implement `ConfigMerger.swift`
- [ ] A.2.5 Implement CLI config parsing

##### A.3 Gate: Configuration Complete
- [ ] **GATE A:** All 6 config tests pass
- [ ] **GATE A:** Can load `.swiftindex.toml` file
- [ ] **GATE A:** Environment variables override config

---

#### Track B: SwiftSyntax Parsing (Agent 1)

> **TDD:** Write tests first, then implement

##### B.1 SwiftSyntax Tests
- [ ] B.1.1 Write `test_parseFunctionDecl()`
- [ ] B.1.2 Write `test_parseClassDecl()`
- [ ] B.1.3 Write `test_parseStructDecl()`
- [ ] B.1.4 Write `test_parseProtocolDecl()`
- [ ] B.1.5 Write `test_parseExtensionDecl()`
- [ ] B.1.6 Write `test_parseActorDecl()`
- [ ] B.1.7 Write `test_parseMacroDecl()`
- [ ] B.1.8 Write `test_extractsSymbolNames()`
- [ ] B.1.9 Write `test_extractsLineNumbers()`

##### B.2 SwiftSyntax Implementation
- [ ] B.2.1 Implement `SwiftSyntaxParser.swift`
- [ ] B.2.2 Implement `ChunkingVisitor.swift` base
- [ ] B.2.3 Add function declaration visiting
- [ ] B.2.4 Add type declaration visiting (class, struct, enum)
- [ ] B.2.5 Add protocol/extension visiting
- [ ] B.2.6 Add actor/macro visiting
- [ ] B.2.7 Implement symbol extraction
- [ ] B.2.8 Implement reference extraction

##### B.3 Gate: SwiftSyntax Complete
- [ ] **GATE B:** All 9 SwiftSyntax tests pass
- [ ] **GATE B:** Can parse any valid Swift file
- [ ] **GATE B:** Chunks have correct line numbers

---

### Agent 2 Track: tree-sitter + Embeddings

#### Track C: tree-sitter Parsing (Agent 2)

> **TDD:** Write tests first, then implement

##### C.1 tree-sitter Tests
- [ ] C.1.1 Write `test_parseObjCInterface()`
- [ ] C.1.2 Write `test_parseObjCImplementation()`
- [ ] C.1.3 Write `test_parseObjCMethodDefinition()`
- [ ] C.1.4 Write `test_parseCFunction()`
- [ ] C.1.5 Write `test_parseCStruct()`
- [ ] C.1.6 Write `test_parseJSONObject()`
- [ ] C.1.7 Write `test_parseJSONArray()`
- [ ] C.1.8 Write `test_parseYAMLMapping()`
- [ ] C.1.9 Write `test_parseYAMLSequence()`
- [ ] C.1.10 Write `test_parseMarkdownSection()`
- [ ] C.1.11 Write `test_parseMarkdownCodeBlock()`

##### C.2 HybridParser Tests
- [ ] C.2.1 Write `test_routesSwiftToSwiftSyntax()`
- [ ] C.2.2 Write `test_routesObjCToTreeSitter()`
- [ ] C.2.3 Write `test_routesUnknownToPlainText()`

##### C.3 tree-sitter Implementation
- [ ] C.3.1 Implement `LanguageRegistry.swift`
- [ ] C.3.2 Implement `TreeSitterParser.swift` base
- [ ] C.3.3 Add ObjC grammar support
- [ ] C.3.4 Add C/C++ grammar support
- [ ] C.3.5 Add JSON grammar support
- [ ] C.3.6 Add YAML grammar support
- [ ] C.3.7 Add Markdown grammar support
- [ ] C.3.8 Implement `HybridParser.swift` router

##### C.4 Gate: tree-sitter Complete
- [ ] **GATE C:** All 14 tree-sitter tests pass
- [ ] **GATE C:** HybridParser routes correctly by extension
- [ ] **GATE C:** Unknown extensions fallback to plain text

---

#### Track D: Embedding Providers (Agent 2)

> **TDD:** Write tests first, then implement

##### D.1 Provider Protocol Tests
- [ ] D.1.1 Write `test_isAvailable_returnsCorrectStatus()`
- [ ] D.1.2 Write `test_embed_singleText_returnsVector()`
- [ ] D.1.3 Write `test_embed_batch_returnsMultipleVectors()`
- [ ] D.1.4 Write `test_dimension_matchesExpected()`

##### D.2 Provider Chain Tests
- [ ] D.2.1 Write `test_usesFirstAvailableProvider()`
- [ ] D.2.2 Write `test_fallbackOnUnavailable()`
- [ ] D.2.3 Write `test_allUnavailable_throws()`
- [ ] D.2.4 Write `test_swiftEmbeddings_alwaysAvailable()`

##### D.3 Mock Provider
- [ ] D.3.1 Implement `MockEmbeddingProvider.swift`

##### D.4 Provider Implementations
- [ ] D.4.1 Implement `MLXEmbeddingProvider.swift`
- [ ] D.4.2 Implement `OllamaEmbeddingProvider.swift`
- [ ] D.4.3 Implement `SwiftEmbeddingsProvider.swift`
- [ ] D.4.4 Implement `VoyageProvider.swift`
- [ ] D.4.5 Implement `OpenAIProvider.swift`
- [ ] D.4.6 Implement `EmbeddingService.swift` (chain orchestrator)
- [ ] D.4.7 Implement `ModelDownloader.swift`

##### D.5 Gate: Embeddings Complete
- [ ] **GATE D:** All 8 embedding tests pass
- [ ] **GATE D:** Provider chain correctly falls back
- [ ] **GATE D:** SwiftEmbeddings always returns embeddings

---

## Phase 2: Storage Layer

> **Dependencies:** Phase 1 complete (all protocols defined)

### Track E: Storage

##### E.1 MetadataStore Tests
- [ ] E.1.1 Write `test_insertChunk()`
- [ ] E.1.2 Write `test_getChunk()`
- [ ] E.1.3 Write `test_updateChunk()`
- [ ] E.1.4 Write `test_deleteChunk()`
- [ ] E.1.5 Write `test_searchFTS5()`

##### E.2 VectorIndex Tests
- [ ] E.2.1 Write `test_addVector()`
- [ ] E.2.2 Write `test_searchVector_returnsSimilar()`
- [ ] E.2.3 Write `test_deleteVector()`
- [ ] E.2.4 Write `test_persistToDisk()`

##### E.3 Indexer Tests
- [ ] E.3.1 Write `test_indexFile_createsChunks()`
- [ ] E.3.2 Write `test_indexDirectory_recursivelyIndexes()`
- [ ] E.3.3 Write `test_incrementalIndex_onlyNewFiles()`

##### E.4 Storage Implementation
- [ ] E.4.1 Implement `MetadataStore.swift` with GRDB
- [ ] E.4.2 Implement GRDB migrations
- [ ] E.4.3 Implement FTS5 virtual table
- [ ] E.4.4 Implement `VectorIndex.swift` with USearch
- [ ] E.4.5 Implement `Indexer.swift` orchestrator
- [ ] E.4.6 Implement file hash tracking
- [ ] E.4.7 Implement incremental indexing logic

##### E.5 Gate: Storage Complete
- [ ] **GATE E:** All 12 storage tests pass
- [ ] **GATE E:** Can index directory and retrieve chunks
- [ ] **GATE E:** Incremental indexing skips unchanged files

---

## Phase 3: Search Engine

> **Dependencies:** Phase 2 complete (storage working)

### Track F: Search

##### F.1 Search Tests
- [ ] F.1.1 Write `test_bm25Search_returnsRankedResults()`
- [ ] F.1.2 Write `test_bm25Search_emptyQuery_returnsEmpty()`
- [ ] F.1.3 Write `test_semanticSearch_returnsSimilarChunks()`
- [ ] F.1.4 Write `test_semanticSearch_respectsLimit()`
- [ ] F.1.5 Write `test_rrfFusion_combinesResults()`
- [ ] F.1.6 Write `test_rrfFusion_handlesDisjointSets()`
- [ ] F.1.7 Write `test_rrfFusion_respectsK()`
- [ ] F.1.8 Write `test_multiHop_followsReferences()`
- [ ] F.1.9 Write `test_multiHop_respectsDepth()`
- [ ] F.1.10 Write `test_hybridSearch_usesWeightedCombination()`
- [ ] F.1.11 Write `test_hybridSearch_filtersByPath()`

##### F.2 Search Implementation
- [ ] F.2.1 Implement `BM25Search.swift`
- [ ] F.2.2 Implement `SemanticSearch.swift`
- [ ] F.2.3 Implement `RRFFusion.swift`
- [ ] F.2.4 Implement `MultiHopSearch.swift`
- [ ] F.2.5 Implement `HybridSearchEngine.swift`
- [ ] F.2.6 Add path filtering support
- [ ] F.2.7 Add configurable weights

##### F.3 Gate: Search Complete
- [ ] **GATE F:** All 11 search tests pass
- [ ] **GATE F:** Hybrid search returns relevant results
- [ ] **GATE F:** Multi-hop follows references correctly

---

## Phase 4: Application Layer (PARALLEL - 2 Agents)

### Agent 1 Track: MCP Server + CLI

#### Track G: MCP Server (Agent 1)

##### G.1 MCP Implementation
- [ ] G.1.1 Implement `MCPServer.swift` base
- [ ] G.1.2 Implement JSON-RPC handling
- [ ] G.1.3 Implement `IndexCodebaseTool.swift`
- [ ] G.1.4 Implement `SearchCodeTool.swift`
- [ ] G.1.5 Implement `CodeResearchTool.swift`
- [ ] G.1.6 Implement `WatchCodebaseTool.swift`

##### G.2 MCP Tests
- [ ] G.2.1 Write `test_indexCodebase_tool()`
- [ ] G.2.2 Write `test_searchCode_tool()`
- [ ] G.2.3 Write `test_codeResearch_tool()`
- [ ] G.2.4 Write `test_watchCodebase_tool()`

##### G.3 Gate: MCP Complete
- [ ] **GATE G:** All 4 MCP tools respond to JSON-RPC
- [ ] **GATE G:** Tools return valid MCP responses

---

#### Track H: CLI Commands (Agent 1)

##### H.1 CLI Implementation
- [ ] H.1.1 Implement `main.swift` with ArgumentParser
- [ ] H.1.2 Implement `IndexCommand.swift`
- [ ] H.1.3 Implement `SearchCommand.swift`
- [ ] H.1.4 Implement `WatchCommand.swift`
- [ ] H.1.5 Implement `ProvidersCommand.swift`
- [ ] H.1.6 Implement `InstallClaudeCodeCommand.swift`
- [ ] H.1.7 Implement `InstallCodexCommand.swift`
- [ ] H.1.8 Implement `InstallCursorCommand.swift`
- [ ] H.1.9 Implement `InitCommand.swift`

##### H.2 CLI Tests
- [ ] H.2.1 Write `test_indexCommand()`
- [ ] H.2.2 Write `test_searchCommand()`
- [ ] H.2.3 Write `test_installClaudeCode()`

##### H.3 Gate: CLI Complete
- [ ] **GATE H:** `swiftindex index` works E2E
- [ ] **GATE H:** `swiftindex search` returns results
- [ ] **GATE H:** `swiftindex install-claude-code` creates config

---

### Agent 2 Track: Watch Mode

#### Track I: Watch Mode (Agent 2)

##### I.1 Watch Tests
- [ ] I.1.1 Write `test_detectsFileCreation()`
- [ ] I.1.2 Write `test_detectsFileModification()`
- [ ] I.1.3 Write `test_detectsFileDeletion()`
- [ ] I.1.4 Write `test_debounces_rapidChanges()`
- [ ] I.1.5 Write `test_incrementalReindex()`

##### I.2 Watch Implementation
- [ ] I.2.1 Implement `FileWatcher.swift`
- [ ] I.2.2 Implement debouncing logic
- [ ] I.2.3 Implement `IncrementalIndexer.swift`
- [ ] I.2.4 Integrate with WatchCommand

##### I.3 Gate: Watch Complete
- [ ] **GATE I:** File changes detected within 500ms
- [ ] **GATE I:** Debouncing prevents rapid re-indexes
- [ ] **GATE I:** Incremental re-index updates only changed files

---

## Phase 5: Integration and Polish

### J.1 Integration Tests
- [ ] J.1.1 Write E2E test: index → search flow
- [ ] J.1.2 Write E2E test: watch → modify → search
- [ ] J.1.3 Write E2E test: MCP server full workflow
- [ ] J.1.4 Write E2E test: provider fallback chain

### J.2 Performance Tests
- [ ] J.2.1 Benchmark indexing 1K files
- [ ] J.2.2 Benchmark indexing 10K files
- [ ] J.2.3 Benchmark search latency
- [ ] J.2.4 Profile memory usage

### J.3 Documentation
- [ ] J.3.1 Update README.md
- [ ] J.3.2 Document configuration options
- [ ] J.3.3 Document MCP tools
- [ ] J.3.4 Add usage examples

### J.4 Distribution
- [ ] J.4.1 Create Homebrew formula
- [ ] J.4.2 Create release workflow
- [ ] J.4.3 Add versioning

### J.5 Final Gate
- [ ] **FINAL GATE:** All 60+ tests pass
- [ ] **FINAL GATE:** `swiftindex index` + `swiftindex search "auth"` works
- [ ] **FINAL GATE:** `swiftindex install-claude-code` creates valid config
- [ ] **FINAL GATE:** MCP server responds to all 4 tools
- [ ] **FINAL GATE:** Watch mode detects and re-indexes changes

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
| **TOTAL** | | **76** | |

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
