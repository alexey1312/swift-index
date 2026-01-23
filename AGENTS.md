<!-- OPENSPEC:START -->

# OpenSpec Instructions

These instructions are for AI assistants working in this project.

Always open `@/openspec/AGENTS.md` when the request:

- Mentions planning or proposals (words like proposal, spec, change, plan)
- Introduces new capabilities, breaking changes, architecture shifts, or big performance/security work
- Sounds ambiguous and you need the authoritative spec before coding

Use `@/openspec/AGENTS.md` to learn:

- How to create and apply change proposals
- Spec format and conventions
- Project structure and guidelines

Keep this managed block so 'openspec update' can refresh the instructions.

<!-- OPENSPEC:END -->

# SwiftIndex - Project Guide

## Overview

- **Purpose**: Semantic code search engine for Swift codebases
- **CLI tool + MCP server** for AI assistants
- **Hybrid search**: BM25 + semantic + RRF fusion
- **Privacy-first**: local embeddings by default

> **Note**: `CLAUDE.md` is a symlink to `AGENTS.md` — editing either file modifies both.

## Quick Reference

### Build & Test Commands

| Command                             | Description                           |
| ----------------------------------- | ------------------------------------- |
| `./bin/mise run build`              | Debug build                           |
| `./bin/mise run build:release`      | Release build (no WMO) + MLX metallib |
| `./bin/mise run test`               | Run all tests                         |
| `./bin/mise run test:filter <name>` | Run filtered tests                    |
| `./bin/mise run lint`               | Run linters                           |
| `./bin/mise run format`             | Format all code                       |

### CLI Commands

| Command                          | Description                   |
| -------------------------------- | ----------------------------- |
| `swiftindex index [PATH]`        | Index a codebase              |
| `swiftindex search <QUERY>`      | Search indexed code           |
| `swiftindex search-docs <QUERY>` | Search documentation snippets |
| `swiftindex watch [PATH]`        | Watch mode (incremental)      |
| `swiftindex serve`               | Start MCP server              |
| `swiftindex providers`           | List embedding providers      |
| `swiftindex init`                | Initialize config             |
| `swiftindex install-claude-code` | Configure Claude Code         |
| `swiftindex install-cursor`      | Configure Cursor              |
| `swiftindex install-codex`       | Configure Codex               |

### Search Enhancement Flags

| Flag                | Description                                      |
| ------------------- | ------------------------------------------------ |
| `--expand-query`    | LLM query expansion for better recall            |
| `--no-expand-query` | Disable query expansion (overrides config)       |
| `--synthesize`      | LLM result synthesis with summary and follow-ups |
| `--no-synthesize`   | Disable synthesis (overrides config)             |

Requires `[search.enhancement]` config section. Default behavior can be configured
via `expand_query_by_default` and `synthesize_by_default` in `[search]` section.
See `docs/search-enhancement.md`.

### Indexing Flags

| Flag                      | Description                                   |
| ------------------------- | --------------------------------------------- |
| `--force`                 | Re-index all files, ignoring change detection |
| `--generate-descriptions` | Generate LLM descriptions for code chunks     |

`--generate-descriptions` requires `[search.enhancement]` config with an LLM provider.

### Search Output Formats

| Format | Flag             | Description                                |
| ------ | ---------------- | ------------------------------------------ |
| human  | `--format human` | Default, with relevance percentages        |
| json   | `--format json`  | Verbose JSON with all metadata             |
| toon   | `--format toon`  | Token-optimized (40-60% smaller than JSON) |

MCP server uses TOON format by default for optimal token efficiency.

## Architecture

### Targets

| Target         | Type       | Description                                       |
| -------------- | ---------- | ------------------------------------------------- |
| SwiftIndexCore | Library    | Core engine (parsing, embedding, storage, search) |
| SwiftIndexMCP  | Library    | MCP server implementation                         |
| swiftindex     | Executable | CLI entry point                                   |

### MCP Architecture (SwiftIndexMCP)

- `MCPServer` — Actor, JSON-RPC 2.0 over stdio
- `MCPContext` — Shared actor for lazy resource initialization
- `MCPToolHandler` — Protocol for tool implementations
- Protocol version: `2024-11-05`
- 5 tools: `index_codebase`, `search_code`, `search_docs`, `code_research`, `watch_codebase`

### Module Structure (SwiftIndexCore)

- `/Configuration` — TOML config loading (TOMLConfigLoader, Config, SearchEnhancementConfig)
- `/Embedding` — Providers (MLX, Ollama, Voyage, OpenAI, SwiftEmbeddings), HubModelManager
- `/Index` — IndexManager (orchestrates storage and embedding)
- `/LLM` — LLM providers and search enhancement features
  - `LLMProvider` protocol, `LLMMessage`, `LLMProviderChain`
  - `ClaudeCodeCLIProvider`, `CodexCLIProvider`, `OllamaLLMProvider`, `OpenAILLMProvider`
  - `QueryExpander` — LLM-powered query expansion
  - `ResultSynthesizer` — multi-result summarization
  - `FollowUpGenerator` — suggested follow-up queries
- `/Models` — Data structures
  - `CodeChunk` — code with docComment, signature, breadcrumb, contentHash
  - `InfoSnippet` — standalone documentation (Markdown sections, headers)
  - `SearchResult`, `ChunkKind`
- `/Parsing` — Parsers (SwiftSyntax, Tree-sitter, Plain), HybridParser
- `/Protocols` — Core abstractions
  - `EmbeddingProvider`, `LLMProvider`
  - `ChunkStore`, `InfoSnippetStore`, `VectorStore`
- `/Search` — BM25, Semantic, HybridSearchEngine, RRFFusion
- `/Storage` — GRDBChunkStore (SQLite/FTS5), USearchVectorStore (HNSW)
- `/Watch` — FileWatcher, IncrementalIndexer

### Key Dependencies

| Package                | Version | Purpose                       |
| ---------------------- | ------- | ----------------------------- |
| SwiftSyntax            | 600.0.0 | Swift AST parsing             |
| swift-tree-sitter      | 0.9.0   | Multi-language parsing        |
| mlx-swift              | 0.30.0  | Apple Silicon embeddings      |
| mlx-swift-lm           | main    | MLX language model support    |
| swift-embeddings       | 0.0.25  | Text embedding models         |
| swift-transformers     | 1.1.6   | HuggingFace model integration |
| GRDB.swift             | 7.9.0   | SQLite + FTS5                 |
| usearch                | 2.23.0  | Vector index (HNSW)           |
| swift-toml             | 1.0.0   | Configuration                 |
| toon-swift             | 0.3.0   | Token-optimized output format |
| swift-argument-parser  | 1.7.0   | CLI argument parsing          |
| swift-log              | 1.9.0   | Structured logging            |
| swift-async-algorithms | 1.1.0   | Async sequence utilities      |
| swift-crypto           | 4.0.0   | Cryptographic operations      |

### USearch Library Notes

**Important**: The USearch Swift wrapper has limited public API:

- `capacity`, `length`, `dimensions` properties are `internal` (not accessible)
- `USearchError` does not conform to `Equatable` — use pattern matching:
  ```swift
  if case .reservationError = usearchError { ... }
  ```
- **Error 15** = `USearchError.reservationError` ("Reserve capacity ahead of insertions!")
  - This is capacity exhaustion, NOT dimension mismatch
  - Handle by calling `index.reserve(newCapacity)` and retrying

`USearchVectorStore` tracks capacity internally (`trackedCapacity`) and stores
dimension in the mapping file for validation on load.

## Code Conventions

### Swift 6 Requirements

- Strict concurrency enabled
- Actors for shared state (HybridSearchEngine, IndexManager, MCPServer)
- Sendable conformance required
- async/await throughout

### Architecture Patterns

- Protocol-oriented design (swappable implementations)
- Provider chain (embedding fallback: MLX → SwiftEmbeddings)
- Repository pattern for storage abstractions

### Style

- SwiftFormat for formatting
- SwiftLint for linting
- Conventional Commits for git messages

### JSON Handling

**ALWAYS use `JSONCodec` instead of Foundation's `JSONEncoder`/`JSONDecoder`/`JSONSerialization`.**

The project uses swift-yyjson with strict RFC 8259 mode for:

- ~16x faster JSON parsing than Foundation
- Strict JSON compliance (rejects comments, trailing commas)
- Significantly fewer allocations (3 vs 6600+ for typical operations)

```swift
// Encoding
let data = try JSONCodec.encode(object)           // Standard encoding
let data = try JSONCodec.encodePretty(object)     // Pretty-printed
let data = try JSONCodec.encodeSorted(object)     // Sorted keys
let data = try JSONCodec.encodePrettySorted(object) // Both

// Decoding
let object = try JSONCodec.decode(Type.self, from: data)

// Serialization (for [String: Any] and dynamic JSON)
let data = try JSONCodec.serialize(dict, options: [.prettyPrinted, .sortedKeys])
let object = try JSONCodec.deserialize(data)
```

## Testing

### Test Targets

| Target              | Description              |
| ------------------- | ------------------------ |
| SwiftIndexCoreTests | Unit tests with fixtures |
| SwiftIndexMCPTests  | MCP protocol tests       |
| IntegrationTests    | E2E tests                |

### Running Tests

```bash
./bin/mise run test                              # All tests
./bin/mise run test:filter SwiftIndexCoreTests   # Specific suite
```

### MLX Release Artifacts

- `./bin/mise run build:release` runs `scripts/build-mlx-metallib` to create
  `default.metallib` and `mlx.metallib` next to the release binary.
- Release builds disable Whole-Module Optimization to avoid swift-frontend
  crashes in `swift-transformers` (Tokenizers).
- Requires MetalToolchain (`xcrun --find metal` and `xcrun --find metallib`).

### Init Behavior Notes

- `swiftindex init` writes MLX defaults by default and includes commented examples.
- If MetalToolchain is missing and MLX is selected, it prompts to install and can
  fall back to Swift Embeddings defaults.
- Tests can override MetalToolchain detection with
  `SWIFTINDEX_METALTOOLCHAIN_OVERRIDE=present|missing`.
- **Dimension auto-detection**: Swift Embeddings provider auto-detects dimension from
  the model. Only MLX, Voyage, and OpenAI require explicit `dimension` in config.
  Don't specify dimension for `swift` provider — it will cause index corruption.

## Distribution

### One-Line Install (via GitHub Pages)

- **Script**: `docs/install.sh` (served at `alexey1312.github.io/swift-index/install.sh`)
- **Install**: `curl -fsSL https://alexey1312.github.io/swift-index/install.sh | sh`
- **Default path**: `~/.local/bin` (no sudo required)
- **Checksums**: Release workflow generates `checksums.txt` for verification
- **GitHub Pages**: Enable in repo Settings → Pages → Source: `main` branch, `/docs` folder

### GitHub Releases (Ready)

- **Workflow**: `.github/workflows/release.yml`
- **Trigger**: Push tag `v*.*.*` (e.g., `git tag v0.1.0 && git push --tags`)
- **Artifacts**: Universal binary (arm64 + x86_64) in `swiftindex-macos.zip`
- **Auto-updates**: Homebrew formula SHA256 on stable releases

### Homebrew (Ready)

- **Tap**: `alexey1312/swift-index` (published)
- **Formula**: `homebrew-swift-index/Formula/swiftindex.rb`
- **Install**: `brew install alexey1312/swift-index/swiftindex`
- **Status**: Waiting for first GitHub release to populate SHA256

### First Release Checklist

```bash
# 1. Tag and push
git tag v0.1.0
git push --tags

# 2. Wait for GitHub Actions to complete
# 3. Homebrew formula auto-updates via workflow
```

## Configuration

Config priority: CLI args > Environment > Project `.swiftindex.toml` > Global `~/.config/swiftindex/config.toml` > Defaults

### Search Configuration Options

| Option                  | Type     | Default | Description                               |
| ----------------------- | -------- | ------- | ----------------------------------------- |
| semantic_weight         | float    | 0.7     | Weight for semantic vs BM25 (0.0-1.0)     |
| rrf_k                   | int      | 60      | RRF fusion constant                       |
| output_format           | string   | "human" | Default format: human, json, or toon      |
| limit                   | int      | 20      | Default number of search results          |
| expand_query_by_default | bool     | false   | Enable LLM query expansion by default     |
| synthesize_by_default   | bool     | false   | Enable LLM result synthesis by default    |
| default_extensions      | [string] | []      | Default extension filter (empty = all)    |
| default_path_filter     | string   | ""      | Default path filter pattern (glob syntax) |

### Search Enhancement Config

```toml
[search.enhancement]
enabled = false  # opt-in

[search.enhancement.utility]
provider = "claude-code-cli"  # claude-code-cli | codex-cli | ollama | openai
timeout = 30

[search.enhancement.synthesis]
provider = "claude-code-cli"
timeout = 120
```

### Environment Variables

| Variable                        | Description                 |
| ------------------------------- | --------------------------- |
| `SWIFTINDEX_EMBEDDING_PROVIDER` | mlx, ollama, voyage, openai |
| `VOYAGE_API_KEY`                | Voyage AI key               |
| `OPENAI_API_KEY`                | OpenAI key                  |
