# SwiftIndex - Project Guide

## Overview

- **Purpose**: Semantic code search engine for Swift codebases
- **CLI tool + MCP server** for AI assistants
- **Hybrid search**: BM25 + semantic + RRF fusion
- **Privacy-first**: local embeddings by default
- **Platform**: Apple Silicon (ARM) only — Intel not supported
- **Terminal UI**: Use Noora components for CLI progress, spinners, and status steps (avoid custom print-based animations)

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

The tasks and CI use `swift build --build-system native`. The Swift 6.4 default build
system needs MetalToolchain for the `.metal` sources, and it does not link `CNumKong.o`.

### CLI Commands

| Command                          | Description                               |
| -------------------------------- | ----------------------------------------- |
| `swiftindex init`                | Write an optional `.swiftindex.toml`      |
| `swiftindex index [PATH]`        | Index a codebase                          |
| `swiftindex search <QUERY>`      | Search indexed code                       |
| `swiftindex search-docs <QUERY>` | Search documentation snippets             |
| `swiftindex parse-tree [PATH]`   | Visualize Swift AST structure             |
| `swiftindex watch [PATH]`        | Watch mode (incremental)                  |
| `swiftindex serve`               | Start MCP server                          |
| `swiftindex providers`           | List embedding providers                  |
| `swiftindex auth status`         | Check OAuth token status                  |
| `swiftindex auth login`          | Set up Claude Code OAuth token            |
| `swiftindex auth logout`         | Remove OAuth token from Keychain          |
| `swiftindex status`              | Show config, index and freshness status   |
| `swiftindex install`             | Configure all detected AI agents          |
| `swiftindex explore <QUERY>`     | Ranked, line-numbered code for a question |
| `swiftindex graph <SYMBOL>`      | Callers, callees, impact, paths           |
| `swiftindex graph --dead`        | List unreferenced declarations            |
| `swiftindex affected [FILES]`    | Test files a change can break (`--stdin`) |

`swiftindex install` also writes a marked block into CLAUDE.md, AGENTS.md or GEMINI.md
and adds the `mcp__swiftindex__*` permission to `.claude/settings.json` (project scope).
`--hook` adds a `UserPromptSubmit` hook (hidden command `swiftindex prompt-hook`), and
`--remove` removes all of it.

**Getting Started**: No configuration is required — `swiftindex index` runs on
built-in defaults. `swiftindex init` is optional and only writes a `.swiftindex.toml`
to pin settings. Use `swiftindex status` to see the resolved configuration, index
health and freshness, and `swiftindex install` to register the MCP server with any
installed AI agents.

### Authentication Commands

SwiftIndex supports Claude Code OAuth for secure, automatic token management:

```bash
# Check authentication status
swiftindex auth status

# Set up OAuth token (automatic or manual)
swiftindex auth login            # Automatic: runs 'claude setup-token'
swiftindex auth login --manual   # Manual: paste token directly
swiftindex auth login --force    # Overwrite existing token

# Remove OAuth token
swiftindex auth logout
```

**OAuth Token Management:**

- **Automatic Setup**: `swiftindex auth login` runs `claude setup-token` and stores the token in macOS Keychain
- **Manual Fallback**: If CLI unavailable, use `--manual` to paste token directly
- **Secure Storage**: Tokens stored in system Keychain (Apple platforms only)
- **Priority Chain**: Environment variables override Keychain (see Environment Variables section)

**Init Wizard Integration:**

When selecting "Claude Code OAuth (Pro/Max)" as LLM provider during `swiftindex init`, the wizard:

1. Checks for existing token in Keychain
2. Runs automatic OAuth flow if `claude` CLI available
3. Falls back to manual input if automatic flow fails
4. Validates and saves token securely

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

| Flag         | Description                                         |
| ------------ | --------------------------------------------------- |
| `--force`    | Re-index all files, ignoring change detection       |
| `--quiet`    | Suppress all output except progress bar and summary |
| `--no-embed` | Build only FTS5 text search and the symbol graph    |

**Indexing phases**: Indexing first stores chunks for FTS5 text search and builds the
symbol graph. No embedding model loads in this phase, so search, `explore` and
`code_graph` work after seconds. The second phase embeds the chunks that have no vector.
Ctrl-C keeps the saved vectors, and the next run resumes. The MCP server embeds missing
vectors in the background. `[embedding] enabled = false` turns vectors off.

**Provider selection (`auto`)**: An existing index keeps the provider in its `meta.json`.
A new index uses the first cloud provider with a key (OpenAI, then Voyage, then Gemini),
then MLX when `default.metallib` is beside the binary, else Swift Embeddings.
`index --force` selects the provider again.

**LLM Descriptions**: Automatically generated when an LLM provider is available.
No flag needed - descriptions are created during indexing if `[search.enhancement]`
is configured or `claude` CLI is installed.

### Search Output Formats

| Format | Flag             | Description                                      |
| ------ | ---------------- | ------------------------------------------------ |
| toon   | `--format toon`  | Default, token-optimized (57% smaller than JSON) |
| human  | `--format human` | Human-readable with relevance percentages        |
| json   | `--format json`  | Verbose JSON with all metadata                   |

TOON is the default format for both CLI and MCP server.

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
- `MCPTasks` — Tasks API for async long-running operations
- `CancellationToken` — Cooperative cancellation for tool execution
- Protocol version: `2025-11-25`
- 8 tools: `explore`, `index_codebase`, `check_indexing_status`, `search_code`, `search_docs`,
  `code_graph`, `code_research`, `parse_tree`
- The `initialize` response sends `instructions` that tell agents to call `explore` first

#### MCP 2025-11-25 Features

| Feature           | Description                                                                   |
| ----------------- | ----------------------------------------------------------------------------- |
| Tool Annotations  | `readOnlyHint`, `destructiveHint`, `idempotentHint`, `openWorldHint`          |
| Tasks API         | Async execution via `tasks/get`, `tasks/list`, `tasks/result`, `tasks/cancel` |
| Cancellation      | `notifications/cancelled` + `CancellationToken` pattern                       |
| Structured Output | `structuredContent` in `ToolCallResult` for typed JSON                        |
| Content Types     | Text, Image, Audio, Resource, ResourceLink with annotations                   |
| Icons             | `MCPIcon` for visual identification in tools and server info                  |

#### Tool Annotations

| Tool                    | Title                 | readOnly | idempotent |
| ----------------------- | --------------------- | -------- | ---------- |
| `index_codebase`        | Code Indexer          | false    | true       |
| `check_indexing_status` | Indexing Status       | true     | true       |
| `search_code`           | Code Search           | true     | true       |
| `search_docs`           | Documentation Search  | true     | true       |
| `code_research`         | Code Research         | true     | true       |
| `parse_tree`            | Parse Tree Visualizer | true     | true       |
| `explore`               | Code Explorer         | true     | true       |
| `code_graph`            | Code Graph            | true     | true       |

#### Async Indexing (Two-Tool Callback Pattern)

Indexing runs asynchronously by default (`async=true`). Use this pattern
to monitor progress:

1. Call `index_codebase` → returns `task_id` immediately
2. Poll `check_indexing_status` with `task_id` every 2-5 seconds
3. Continue until status is `completed` or `failed`

```
# Start indexing (async by default)
index_codebase(path="/project")
→ {"task_id": "abc-123", "status": "started", "estimated_files": 150}

# Check progress (repeat until done)
check_indexing_status(task_id="abc-123")
→ {"status": "working", "phase": "indexing", "files_processed": 45, "total_files": 150, ...}

# Final result
check_indexing_status(task_id="abc-123")
→ {"status": "completed", "files_indexed": 150, "chunks_indexed": 1250}
```

> Set `async=false` for synchronous blocking mode.

### Module Structure (SwiftIndexCore)

- `/Configuration` — TOML config loading (TOMLConfigLoader, Config, SearchEnhancementConfig)
  - `TOMLConfigValidator.allowedSections` must be updated when adding new config keys to `TOMLConfig` structs
- `/Embedding` — Providers (MLX, Ollama, Voyage, OpenAI, Gemini, SwiftEmbeddings), HubModelManager
  - `EmbeddingBatcher` — Batches cross-file embedding requests for max GPU utilization
- `/Index` — IndexManager (orchestrates storage and embedding)
- `/LLM` — LLM providers and search enhancement features
  - `LLMProvider` protocol, `LLMMessage`, `LLMProviderChain`
  - `MLXLLMProvider` — fully local LLM on Apple Silicon (no cloud required)
  - `AnthropicLLMProvider` — direct Anthropic API access (fast, ~5-10s vs CLI's ~35-40s)
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
  - **Ranking Boosts** in HybridSearchEngine:
    - Exact symbol match: 2.5x for rare terms (< 10 occurrences)
    - Source path: 1.1x for `/Sources/` paths
    - Public modifier: 1.1x for `public` declarations
    - Standard protocol demotion: 0.5x for Comparable/Equatable/etc extensions in conceptual queries
- `/Storage` — GRDBChunkStore (SQLite/FTS5), USearchVectorStore (HNSW)
- `/Watch` — FileWatcher, IncrementalIndexer

### Key Dependencies

| Package               | Version | Purpose                       |
| --------------------- | ------- | ----------------------------- |
| SwiftSyntax           | 603.0.2 | Swift AST parsing             |
| swift-tree-sitter     | 0.25.0  | Multi-language parsing        |
| mlx-swift             | 0.31.6  | Apple Silicon embeddings      |
| mlx-swift-lm          | 3.31.4  | MLX language model support    |
| swift-embeddings      | 0.0.26  | Text embedding models         |
| swift-transformers    | 1.1.6   | HuggingFace model integration |
| GRDB.swift            | 7.11.1  | SQLite + FTS5                 |
| usearch               | 2.26.2  | Vector index (HNSW)           |
| swift-toml            | 2.0.0   | Configuration                 |
| toon-swift            | 0.4.0   | Token-optimized output format |
| swift-argument-parser | 1.7.2   | CLI argument parsing          |
| swift-log             | 1.15.0  | Structured logging            |
| swift-collections     | 1.6.0   | OrderedDictionary (MCP tools) |
| swift-yyjson          | 0.6.0   | JSON codec (JSONCodec)        |
| Noora                 | 0.57.0  | Terminal UI components        |
| swift-crypto          | 4.5.2   | Cryptographic operations      |
| swift-nio             | 2.102.0 | Signal handling (shutdown)    |

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

### Platform: macOS Only

This is a **macOS-only application** (Apple Silicon ARM). Do not add `#if os(macOS)` conditionals
or cross-platform compatibility code. Assume macOS APIs (AppKit, Security.framework, etc.) are
always available. The only exception is existing `#if os(macOS) || os(Linux)` blocks in
ClaudeCodeAuthManager for the CLI-based flow.

### Swift 6 Requirements

- Strict concurrency enabled
- Actors for shared state (HybridSearchEngine, IndexManager, MCPServer)
- Sendable conformance required
- async/await throughout
- Ternary `condition ? nil : { closure }` fails `@Sendable` checks when closure captures non-Sendable values — use `if/else` with explicit let-bindings instead

### Architecture Patterns

- Protocol-oriented design (swappable implementations)
- `auto` provider selection: index meta.json, cloud key, MLX, Swift Embeddings
- Repository pattern for storage abstractions

### Style

- SwiftFormat for formatting
- SwiftLint for linting
- Conventional Commits for git messages

### SwiftLint Limits

- `function_body_length`: max 120 lines. Extract helpers when adding code to large functions.
- `function_parameter_count`: max 5 parameters. Use a params struct to group related parameters.
- `line_length`: max 120 characters.

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

- MLX needs `default.metallib`; without it MLX-C's error handler calls `exit(-1)` and
  kills the process. `MLXRuntime.isMetalLibraryAvailable` checks for it first, so a
  build without one reports MLX as unavailable and falls back to Swift Embeddings.
- `./bin/mise run build:release` runs `scripts/build-mlx-metallib` to create
  `default.metallib` and `mlx.metallib` next to the release binary.
- Release builds disable Whole-Module Optimization to avoid swift-frontend
  crashes in `swift-transformers` (Tokenizers).
- Requires MetalToolchain. Xcode 26+ has a `metal` stub, so `xcrun --find metal` is not
  a valid check; run `xcrun metal --version`. Install it with
  `xcodebuild -downloadComponent MetalToolchain`.
- End users do not need MetalToolchain: release artifacts ship the metallib.
- The Swift 6.4 default build system compiles `.metal` sources and fails without
  MetalToolchain. The tasks and CI use `--build-system native`, which skips them.

### Init Behavior Notes

- **No config required**: Every command runs on built-in defaults when no config file
  exists. `swiftindex init` only pins the settings in a `.swiftindex.toml`.
- `swiftindex init` writes `provider = "auto"` by default and includes commented examples.
- If MLX is selected and no metallib is beside the binary, it can fall back to Swift
  Embeddings defaults.
- Tests can override MLX runtime detection with
  `SWIFTINDEX_MLX_RUNTIME_OVERRIDE=present|missing`.
- **Dimension auto-detection**: Swift Embeddings provider auto-detects dimension from
  the model. Only MLX, Voyage, OpenAI and Gemini require explicit `dimension` in config.
  Don't specify dimension for `swift` provider — it will cause index corruption.

## Distribution

### GitHub Releases

- **Workflow**: `.github/workflows/release.yml`
- **Trigger**: Push tag `v*.*.*` (e.g., `git tag v0.1.0 && git push --tags`)
- **Artifacts**: arm64 binary (Apple Silicon) in `swiftindex-macos.zip`
- **Auto-updates**: Homebrew formula SHA256 on stable releases

### Homebrew

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

### Zero-Config Defaults

No command requires a config file. Every caller loads the config with
`requireInitialization: false`, so a missing `.swiftindex.toml` gives the built-in defaults.
The default embedding provider is `auto`. Run `swiftindex init` to pin settings in a
project `.swiftindex.toml`. Run `swiftindex status` to see the resolved configuration.

### Config Priority

Config priority: CLI args > Environment > Project `.swiftindex.toml` > Global `~/.config/swiftindex/config.toml`

### Search Configuration Options

| Option                  | Type     | Default | Description                               |
| ----------------------- | -------- | ------- | ----------------------------------------- |
| semantic_weight         | float    | 0.7     | Weight for semantic vs BM25 (0.0-1.0)     |
| rrf_k                   | int      | 60      | RRF fusion constant                       |
| output_format           | string   | "toon"  | Default format: toon, human, or json      |
| limit                   | int      | 20      | Default number of search results          |
| expand_query_by_default | bool     | false   | Enable LLM query expansion by default     |
| synthesize_by_default   | bool     | false   | Enable LLM result synthesis by default    |
| default_extensions      | [string] | []      | Default extension filter (empty = all)    |
| default_path_filter     | string   | ""      | Default path filter pattern (glob syntax) |

### Auto Index and Embedding Options

| Option                            | Type | Default | Description                                                              |
| --------------------------------- | ---- | ------- | ------------------------------------------------------------------------ |
| `embedding.enabled`               | bool | true    | Compute vectors; false keeps FTS5 and graph only                         |
| `auto_index.reconcile_on_connect` | bool | true    | Reconcile the index when an MCP session starts                           |
| `auto_index.sync_threshold`       | int  | 25      | Largest change set that a reconcile re-indexes; a larger set stays stale |
| `auto_index.watch`                | bool | true    | Watch the tree while `swiftindex serve` runs                             |

**One writer per index**: Each agent starts its own `swiftindex serve`, so one index can
have several servers. The process that holds `flock` on `.swiftindex/writer.lock` is the
writer: it reconciles, watches and embeds. The other servers only read, and they reload
vectors when the writer saves them. A reader becomes the writer when the lock is free.
The kernel releases the lock when its process exits. `swiftindex index` and
`swiftindex watch` also take the lock, and they stop with a message when a server holds it.
An MCP server takes the lock at its first tool call and keeps it until it exits.
The watcher stores changed chunks for text search and the graph at once; a background
pass adds their vectors.

### Search Enhancement Config

```toml
[search.enhancement]
enabled = false  # opt-in

[search.enhancement.utility]
provider = "mlx"  # mlx | anthropic | claude-code-cli | codex-cli | ollama | openai
model = "mlx-community/Qwen2.5-Coder-1.5B-Instruct-4bit"  # optional (default)
timeout = 60

[search.enhancement.synthesis]
provider = "mlx"
timeout = 120
```

**MLX LLM Models** (4-bit quantized, local-only):

_Code-Specialized (Recommended):_

- `mlx-community/Qwen2.5-Coder-1.5B-Instruct-4bit` — default, fast, code-specialized
- `mlx-community/Qwen2.5-Coder-0.5B-Instruct-4bit` — ultra-fast, code-specialized
- `mlx-community/Qwen2.5-Coder-3B-Instruct-4bit` — better quality, code-specialized

_General-Purpose:_

- `mlx-community/Qwen3-4B-4bit` — good balance of quality/speed
- `mlx-community/SmolLM-135M-Instruct-4bit` — ultra-fast, basic capabilities
- `mlx-community/Llama-3.2-1B-Instruct-4bit` — compact, good for simple tasks
- `mlx-community/Llama-3.2-3B-Instruct-4bit` — larger, better quality

First run downloads the model from HuggingFace (~2-7GB). Models are cached in `~/.cache/huggingface/`
(`$XDG_CACHE_HOME/huggingface` when set, or `SWIFTINDEX_MODEL_CACHE` to point anywhere else).
swift-transformers' own default is `~/Documents/huggingface`, which iCloud Drive syncs when
"Desktop & Documents Folders" is enabled; `ModelCacheLocation` overrides it for every provider and
moves an existing `~/Documents/huggingface` into the cache directory once, so no model is
re-downloaded.

### Environment Variables

| Variable                        | Description                                      |
| ------------------------------- | ------------------------------------------------ |
| `SWIFTINDEX_EMBEDDING_PROVIDER` | auto, mlx, swift, ollama, voyage, openai, gemini |
| `SWIFTINDEX_MODEL_CACHE`        | Model cache directory override                   |
| `SWIFTINDEX_ANTHROPIC_API_KEY`  | Anthropic API key (highest priority)             |
| `CLAUDE_CODE_OAUTH_TOKEN`       | OAuth token (auto-set by Claude Code CLI)        |
| `ANTHROPIC_API_KEY`             | Anthropic API key (fallback)                     |
| `SWIFTINDEX_VOYAGE_API_KEY`     | Voyage AI key (priority)                         |
| `VOYAGE_API_KEY`                | Voyage AI key (fallback)                         |
| `SWIFTINDEX_OPENAI_API_KEY`     | OpenAI key (priority)                            |
| `OPENAI_API_KEY`                | OpenAI key (fallback)                            |
| `SWIFTINDEX_GEMINI_API_KEY`     | Gemini API key (priority)                        |
| `GEMINI_API_KEY`                | Gemini API key (fallback)                        |

**Anthropic Authentication Priority** (highest to lowest):

1. `SWIFTINDEX_ANTHROPIC_API_KEY` — Project-specific override (explicit configuration)
2. `CLAUDE_CODE_OAUTH_TOKEN` — OAuth token from environment (auto-set by Claude Code CLI)
3. `ANTHROPIC_API_KEY` — Standard API key
4. **Keychain OAuth Token** — Managed via `swiftindex auth` (fallback for users without env vars)

**Platform Support**: Keychain authentication is available on Apple platforms (macOS, iOS, tvOS, watchOS) with Security.framework. Other platforms use environment variables only.
