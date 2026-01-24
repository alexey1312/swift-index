# SwiftIndex

[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Falexey1312%2Fswift-index%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/alexey1312/swift-index)
[![Swift-versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Falexey1312%2Fswift-index%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/alexey1312/swift-index)
[![CI](https://github.com/alexey1312/swift-index/actions/workflows/ci.yml/badge.svg)](https://github.com/alexey1312/swift-index/actions/workflows/ci.yml)
[![Release](https://github.com/alexey1312/swift-index/actions/workflows/release.yml/badge.svg)](https://github.com/alexey1312/swift-index/actions/workflows/release.yml)
[![License](https://img.shields.io/github/license/alexey1312/swift-index.svg)](LICENSE)

A semantic code search engine for Swift codebases, available as both a CLI tool and an MCP server for AI assistants like Claude Code.

## Features

- **Hybrid Search**: Combines BM25 full-text search with semantic vector search using RRF fusion
- **Swift-First Parsing**: Uses SwiftSyntax for accurate Swift parsing with tree-sitter fallback for ObjC, C, JSON, YAML, and Markdown
- **Rich Metadata Indexing**: Extracts doc comments, signatures, and breadcrumbs for improved search quality
- **Documentation Search**: Indexes standalone documentation (Markdown sections, file headers) as InfoSnippets
- **LLM-Powered Search Enhancement**: Optional query expansion, result synthesis, and follow-up suggestions
- **Local-First Embeddings**: Privacy-preserving embedding generation using MLX (Apple Silicon) or swift-embeddings
- **Parallel Indexing**: Concurrent file processing with bounded concurrency for faster indexing
- **Content-Based Change Detection**: SHA-256 content hashing for precise incremental re-indexing
- **LLM Description Generation**: Automatic AI-generated descriptions for code chunks (when LLM provider available)
- **Watch Mode**: Automatically updates the index when files change
- **MCP Server**: Exposes search capabilities to AI assistants via Model Context Protocol

## System Requirements

- **macOS 14 (Sonoma)** or later
- **Swift 6.1+** (Xcode 16+). Swift 6.2.3 recommended.
- **Apple Silicon** (M1/M2/M3/M4) — required for MLX embeddings

## Installation

### Homebrew (Recommended)

```bash
brew install alexey1312/swift-index/swiftindex
```

### mise (GitHub backend)

```bash
mise use -g github:alexey1312/swift-index@latest
```

This installs SwiftIndex from GitHub Releases.

### From Source

```bash
git clone https://github.com/alexey1312/swift-index.git
cd swift-index
./bin/mise run build:release
cp .build/release/swiftindex /usr/local/bin/
cp .build/release/default.metallib .build/release/mlx.metallib /usr/local/bin/
```

### Verify Installation

```bash
swiftindex --version
swiftindex providers  # Check available embedding providers
```

### Install for AI Assistants

```bash
# Claude Code (project-local .mcp.json)
swiftindex install-claude-code

# Claude Code (global ~/.claude.json)
swiftindex install-claude-code --global

# Cursor (project-local .mcp.json)
swiftindex install-cursor

# Codex (project-local .mcp.json)
swiftindex install-codex
```

By default, install commands create a project-local `.mcp.json` configuration.
Use `--global` to install to the user-wide configuration file instead.

## Quick Start

### 1. Initialize a Project

```bash
cd /path/to/your/swift/project
swiftindex init
```

This creates a `.swiftindex.toml` configuration file.

### 2. Index the Codebase

```bash
swiftindex index .
```

### 3. Search

```bash
swiftindex search "user authentication flow"
```

## CLI Commands

### `swiftindex index <path>`

Index a Swift codebase.

```bash
# Index current directory
swiftindex index .

# Force re-index all files
swiftindex index --force .

# Watch for changes and re-index automatically
swiftindex watch .

# Use custom config
swiftindex index --config custom.toml .
```

### `swiftindex search <query>`

Search the indexed codebase.

```bash
# Basic search
swiftindex search "authentication"

# Limit results
swiftindex search --limit 5 "user login"

# Output formats
swiftindex search --format human "error handling"  # Default, with relevance %
swiftindex search --format json "error handling"   # Verbose JSON
swiftindex search --format toon "error handling"   # Token-optimized (40-60% smaller)

# Legacy JSON flag (deprecated, use --format json)
swiftindex search --json "error handling"

# Adjust semantic weight (0.0 = BM25 only, 1.0 = semantic only)
swiftindex search --semantic-weight 0.7 "networking code"

# LLM-enhanced search (requires [search.enhancement] config)
swiftindex search --expand-query "async networking"     # Expand query with related terms
swiftindex search --synthesize "authentication flow"   # Generate summary and follow-ups
```

**Output Formats:**

| Format  | Description                         | Use Case                       |
| ------- | ----------------------------------- | ------------------------------ |
| `human` | Readable with relevance percentages | Terminal/interactive use       |
| `json`  | Verbose JSON with all metadata      | Scripting/automation           |
| `toon`  | Token-optimized (TOON format)       | AI assistants (40-60% smaller) |

**Search Enhancement Flags:**

| Flag             | Description                                                |
| ---------------- | ---------------------------------------------------------- |
| `--expand-query` | Use LLM to generate related search terms for better recall |
| `--synthesize`   | Generate AI summary of results with follow-up suggestions  |

Both flags require `[search.enhancement]` configuration. See [Search Enhancement](#search-enhancement).

### `swiftindex init`

Initialize configuration for a project.

```bash
swiftindex init
```

By default this writes MLX settings and commented examples for other providers.
If MetalToolchain is missing and MLX is selected, the CLI prompts to install it
and can fall back to Swift Embeddings defaults.

### `swiftindex config lint` / `swiftindex config format`

Validate or format `.swiftindex.toml`.

```bash
swiftindex config lint
swiftindex config format
swiftindex fmt  # alias for config format
```

Flags for format:

- `-a/--all` format all `.swiftindex.toml` under current directory
- `-c/--check` check formatting without writing
- `-s/--stdin` read from stdin and write formatted output to stdout

### `swiftindex watch`

Watch a directory and update the index incrementally.

```bash
# Watch current directory
swiftindex watch

# Watch a specific path
swiftindex watch /path/to/project
```

### `swiftindex install-claude-code`

Install SwiftIndex as an MCP server for Claude Code.

```bash
# Project-local installation (creates .mcp.json)
swiftindex install-claude-code

# Global installation (writes to ~/.claude.json)
swiftindex install-claude-code --global

# Dry run to see what would be configured
swiftindex install-claude-code --dry-run
```

Similar commands exist for other AI assistants:

- `swiftindex install-cursor` — Cursor IDE (local: `.mcp.json`, global: `~/.cursor/mcp.json`)
- `swiftindex install-codex` — Codex CLI (local: `.mcp.json`, global: `~/.codex/config.toml`)

## Assistant Guidance Files

If you use AI assistants (Claude Code, Cursor, Codex), add `AGENTS.md` and
`CLAUDE.md` in your repo to describe project rules and expectations.

Example `AGENTS.md`:

```md
# Project Guidance

- Build: ./bin/mise run build
- Tests: ./bin/mise run test
- Config: .swiftindex.toml is linted on load
```

Example `CLAUDE.md`:

```md
# Assistant Notes

- Use swiftindex for search
- Prefer local embedding providers
- Keep changes small and well tested
```

## Configuration

SwiftIndex uses TOML configuration files. Create `.swiftindex.toml` in your project root:

```toml
# .swiftindex.toml

[index]
# Directories to scan
include = ["Sources", "Tests"]

# Patterns to exclude
exclude = [
    ".build",
    "Pods",
    "Carthage",
    "DerivedData"
]

# File extensions to index
extensions = ["swift", "m", "mm", "h", "c", "cpp"]

[embedding]
# Embedding provider: "mlx", "swift" (alias: swift-embeddings), "ollama", "openai", "voyage"
provider = "mlx"

# Model to use (provider-specific)
model = "mlx-community/bge-small-en-v1.5-4bit"

# Vector dimension
dimension = 384

[search]
# Default number of results
limit = 20

# Semantic weight for hybrid search (0.0-1.0)
semantic_weight = 0.7

# RRF fusion constant
rrf_k = 60

# Output format: human, json, or toon (token-optimized)
output_format = "human"

[storage]
# Index storage location
directory = ".swiftindex"
```

API keys for cloud providers are read from environment variables:
`VOYAGE_API_KEY` and `OPENAI_API_KEY`.

### Configuration Priority

Configuration is loaded from multiple sources with the following priority (highest first):

1. **CLI arguments**: `--config`, `--limit`, etc.
2. **Environment variables**: `SWIFTINDEX_*` prefixed
3. **Project config**: `.swiftindex.toml` in project root
4. **Global config**: `~/.config/swiftindex/config.toml`
5. **Default config**: Built-in defaults

### Environment Variables

| Variable                        | Description                      |
| ------------------------------- | -------------------------------- |
| `SWIFTINDEX_EMBEDDING_PROVIDER` | Embedding provider               |
| `SWIFTINDEX_EMBEDDING_MODEL`    | Embedding model name             |
| `SWIFTINDEX_LIMIT`              | Default search limit             |
| `OPENAI_API_KEY`                | API key for OpenAI embeddings    |
| `VOYAGE_API_KEY`                | API key for Voyage AI embeddings |

## Search Enhancement

SwiftIndex supports optional LLM-powered search enhancements for improved results:

- **Query Expansion**: Automatically expands search queries with synonyms and related terms
- **Result Synthesis**: Generates AI summaries of search results with key insights
- **Follow-up Suggestions**: Suggests related queries to explore further

### Configuration

Add the `[search.enhancement]` section to your `.swiftindex.toml`:

```toml
[search.enhancement]
enabled = true  # Enable LLM features

# Utility tier: fast operations (query expansion, follow-ups)
[search.enhancement.utility]
provider = "claude-code-cli"  # or: codex-cli, ollama, openai
# model = "claude-haiku-4-5-20251001"  # optional model override
timeout = 30

# Synthesis tier: deep analysis (result summarization)
[search.enhancement.synthesis]
provider = "claude-code-cli"
# model = "claude-sonnet-4-20250514"  # optional model override
timeout = 120
```

### Supported Providers

| Provider          | Requirement              | Best For                   |
| ----------------- | ------------------------ | -------------------------- |
| `claude-code-cli` | `claude` CLI installed   | Best quality, Claude users |
| `codex-cli`       | `codex` CLI installed    | OpenAI Codex users         |
| `ollama`          | Ollama server running    | Local, privacy-preserving  |
| `openai`          | `OPENAI_API_KEY` env var | Cloud, high availability   |

### Usage

```bash
# Expand query with related terms before searching
swiftindex search --expand-query "async networking"

# Get AI synthesis of results
swiftindex search --synthesize "authentication flow"

# Both together
swiftindex search --expand-query --synthesize "error handling"
```

MCP tools accept `expand_query` and `synthesize` flags. These require
`[search.enhancement]` to be enabled in config.

**Further Reading:**

- [Search Enhancement Guide](docs/search-enhancement.md) — Detailed LLM provider configuration
- [Search Features Guide](docs/search-features.md) — Query expansion, synthesis, and search tips

## MCP Server

SwiftIndex implements [Model Context Protocol](https://modelcontextprotocol.io/) version `2024-11-05` for AI assistant integration.

| Property  | Value                           |
| --------- | ------------------------------- |
| Transport | stdio (stdin/stdout)            |
| Format    | JSON-RPC 2.0                    |
| Tools     | 5 tools for indexing and search |

### Configuration by Client

Different AI assistants require slightly different configuration formats:

| Client      | Config File                           | Type Field                  | Notes                        |
| ----------- | ------------------------------------- | --------------------------- | ---------------------------- |
| Claude Code | `.mcp.json` or `~/.claude.json`       | Required: `"type": "stdio"` | Use `--global` for user-wide |
| Cursor      | `.mcp.json` or `~/.cursor/mcp.json`   | Not needed                  | Standard MCP format          |
| Codex       | `.mcp.json` or `~/.codex/config.toml` | Not needed                  | TOML format for global       |

### Error Responses

MCP tools return errors in standard format:

```json
{ "content": [{ "type": "text", "text": "Error message" }], "isError": true }
```

Common errors:

- `"No index found for path: /path"` — Run `index_codebase` first
- `"Missing required argument: query"` — Required parameter not provided
- `"Path does not exist or is not a directory"` — Invalid path

## MCP Tools

When running as an MCP server, SwiftIndex exposes the following tools:

### `search_code`

Search for code in the indexed codebase.

**Parameters:**

- `query` (required): Search query string
- `limit` (optional): Maximum results (default: 20)
- `semantic_weight` (optional): Weight for semantic search (0.0-1.0, default: 0.7)
- `format` (optional): Output format - `toon`, `json`, or `human` (default from config)
- `path` (optional): Path to indexed codebase (default: current directory)
- `extensions` (optional): Comma-separated extension filter (e.g., `swift,ts`)
- `path_filter` (optional): Path filter (glob syntax)
- `expand_query` (optional): Enable LLM query expansion (requires search.enhancement)
- `synthesize` (optional): Enable LLM synthesis + follow-ups (requires search.enhancement)

**Example:**

```json
{
  "query": "user authentication flow",
  "limit": 10,
  "semantic_weight": 0.8,
  "format": "toon"
}
```

### `index_codebase`

Trigger indexing of the codebase.

**Parameters:**

- `path` (optional): Path to index (default: current directory)
- `force` (optional): Force re-index all files (default: false)

### `search_docs`

Search indexed documentation (Markdown files, README sections, etc.).

**Parameters:**

- `query` (required): Natural language search query
- `limit` (optional): Maximum results (default: 10)
- `path_filter` (optional): Filter by path pattern (glob syntax)
- `format` (optional): Output format - `toon`, `json`, or `human`
- `path` (optional): Path to indexed codebase (default: current directory)

**Example:**

```json
{
  "query": "installation instructions",
  "limit": 5,
  "path_filter": "*.md"
}
```

### `code_research`

Perform multi-step research over the indexed codebase.

**Parameters:**

- `query` (required): Research query or topic to investigate
- `path` (optional): Path to indexed codebase (default: current directory)
- `depth` (optional): Maximum reference depth (1-5, default: 2)
- `focus` (optional): One of `architecture`, `dependencies`, `patterns`, `flow`

**Example:**

```json
{
  "query": "How is search enhancement configured and used?",
  "depth": 3,
  "focus": "architecture"
}
```

### `watch_codebase`

Start, stop, or check status of watch mode for a codebase.

**Parameters:**

- `path` (required): Absolute path to the directory to watch
- `action` (optional): One of `start`, `stop`, or `status` (default: `start`)

**Example:**

```json
{
  "action": "start",
  "path": "/path/to/project"
}
```

### Output Formats

The MCP server supports three output formats via the `format` parameter:

| Format  | Description                         | Use Case                       |
| ------- | ----------------------------------- | ------------------------------ |
| `toon`  | Token-optimized (default for MCP)   | AI assistants (40-60% smaller) |
| `json`  | Verbose JSON with all metadata      | Scripting/automation           |
| `human` | Readable with relevance percentages | Terminal/interactive           |

**TOON Format Structure** (Token-Optimized Object Notation):

```
search{q,n}:                    # Query and result count
  "query string",10

results[n]{r,rel,p,l,k,s}:      # Tabular metadata
  1,95,"path.swift",[10,25],"function",["symbolName"]

meta[n]{sig,bc}:                # Signatures and breadcrumbs
  "func example()",~            # ~ = null

docs[n]:                        # Doc comments (truncated)
  "Description of the code..."

descs[n]:                       # LLM-generated descriptions
  "Validates user credentials"  # ~ = null if not generated

code[n]:                        # Code content (max 15 lines)
  ---
  func example() { ... }

synthesis{sum,insights,refs}:   # LLM summary (optional)
  "Summary of results"

follow_ups[n]{q,cat}:           # Related queries (optional)
  "related query","deeper"
```

## Embedding Providers

SwiftIndex supports multiple embedding providers:

### MLX (Default)

Hardware-accelerated embeddings on Apple Silicon. Fastest option for local use.

```toml
[embedding]
provider = "mlx"
model = "mlx-community/bge-small-en-v1.5-4bit"
```

### Swift Embeddings

Pure Swift implementation, works on all platforms. Fallback when MLX is unavailable.

```toml
[embedding]
provider = "swift" # alias: swift-embeddings
model = "all-MiniLM-L6-v2"
```

### Ollama

Local server-based embeddings via Ollama.

```toml
[embedding]
provider = "ollama"
model = "nomic-embed-text"
base_url = "http://localhost:11434"
```

### OpenAI

Cloud embeddings via OpenAI API.

```toml
[embedding]
provider = "openai"
model = "text-embedding-3-small"
# Set OPENAI_API_KEY environment variable
```

### Voyage AI

Code-optimized embeddings via Voyage AI.

```toml
[embedding]
provider = "voyage"
model = "voyage-code-2"
# Set VOYAGE_API_KEY environment variable
```

## Architecture

SwiftIndex follows a modular architecture:

```
SwiftIndexCore/
├── Configuration/   # Configuration loading and merging
├── Embedding/       # Embedding providers (MLX, OpenAI, Voyage, Ollama)
├── Index/           # IndexManager (orchestrates storage and embedding)
├── LLM/             # LLM providers for search enhancement
│   ├── ClaudeCodeCLIProvider  # Claude Code CLI integration
│   ├── CodexCLIProvider       # Codex CLI integration
│   ├── OllamaLLMProvider      # Ollama HTTP API
│   ├── OpenAILLMProvider      # OpenAI HTTP API
│   ├── QueryExpander          # LLM-powered query expansion
│   ├── ResultSynthesizer      # Multi-result summarization
│   └── FollowUpGenerator      # Suggested follow-up queries
├── Models/          # Core data models
│   ├── CodeChunk              # Code constructs with metadata
│   ├── InfoSnippet            # Standalone documentation snippets
│   └── SearchResult           # Search result container
├── Parsing/         # SwiftSyntax and tree-sitter parsers
├── Protocols/       # Core abstractions
│   ├── EmbeddingProvider      # Embedding generation
│   ├── LLMProvider            # LLM text generation
│   ├── ChunkStore             # Code chunk persistence
│   ├── InfoSnippetStore       # Documentation snippet persistence
│   └── VectorStore            # Vector index operations
├── Search/          # Hybrid search engine with RRF fusion
└── Storage/         # GRDB chunk store + USearch vector store

SwiftIndexMCP/
├── MCPServer.swift  # MCP server implementation
└── Tools/           # MCP tool handlers
    ├── SearchCodeTool
    ├── SearchDocsTool
    ├── IndexCodebaseTool
    ├── CodeResearchTool
    └── WatchCodebaseTool

swiftindex/
└── Commands/        # CLI commands
```

### Storage

- **Chunk Store**: SQLite database with FTS5 for full-text search (GRDB)
- **Info Snippet Store**: Separate FTS5 index for documentation search
- **Vector Store**: HNSW index for approximate nearest neighbor search (USearch)

### Search Algorithm

1. Generate query embedding
2. (Optional) Expand query using LLM for better recall
3. Perform BM25 full-text search (on code chunks and/or info snippets)
4. Perform semantic similarity search
5. Combine results using Reciprocal Rank Fusion (RRF)
6. (Optional) Synthesize results using LLM for summary
7. Return top-k results sorted by fused score

### Indexed Metadata

Each code chunk includes rich metadata for improved search:

| Field                  | Description                                         |
| ---------------------- | --------------------------------------------------- |
| `content`              | The actual code                                     |
| `docComment`           | Associated documentation comment                    |
| `signature`            | Function/type signature (if applicable)             |
| `breadcrumb`           | Hierarchy path (e.g., "Module > Class > Method")    |
| `tokenCount`           | Approximate token count (content.count / 4)         |
| `language`             | Programming language                                |
| `contentHash`          | SHA-256 hash for change detection                   |
| `generatedDescription` | LLM-generated description (when provider available) |

## Development

### Building

```bash
swift build
```

### Testing

```bash
# Run all tests
swift test

# Run specific test suite
swift test --filter "E2ETests"

# Run with coverage
swift test --enable-code-coverage
```

### Project Structure

```
swift-index/
├── Sources/
│   ├── SwiftIndexCore/     # Core library
│   ├── SwiftIndexMCP/      # MCP server
│   └── swiftindex/         # CLI
├── Tests/
│   ├── SwiftIndexCoreTests/
│   └── IntegrationTests/
└── Package.swift
```

## Troubleshooting

### MLX Metal library missing

Release builds expect `default.metallib` (and `mlx.metallib`) next to the
`swiftindex` binary. `./bin/mise run build:release` generates these using
MetalToolchain.

### Build errors with Xcode

Ensure you have Xcode 16.2+ with command line tools installed:

```bash
xcode-select --install
xcode-select -p  # Should show Xcode path
```

### Index not updating

Try forcing a re-index:

```bash
swiftindex index --force .
```

### MCP server not responding

Check the server is running:

```bash
swiftindex serve --verbose
```

Verify the MCP configuration in your AI assistant's settings file.

## Uninstall

### Homebrew

```bash
brew uninstall swiftindex
```

### Manual

```bash
rm /usr/local/bin/swiftindex
rm -rf ~/.swiftindex  # Optional: remove cached models
```

## Comparison with Alternatives

SwiftIndex is designed specifically for Swift developers on macOS. Here's how it compares to other code search tools:

| Feature           | SwiftIndex            | [mgrep](https://github.com/mixedbread-ai/mgrep) | [ChunkHound](https://github.com/chunkhound/chunkhound) |
| ----------------- | --------------------- | ----------------------------------------------- | ------------------------------------------------------ |
| **Privacy**       | ✅ Local-first (MLX)  | ❌ Cloud-only                                   | ✅ Local-first                                         |
| **Swift Parsing** | ✅ SwiftSyntax (AST)  | ❌ Generic                                      | ⚠️ Tree-sitter                                          |
| **Apple Silicon** | ✅ MLX optimized      | ❌                                              | ❌                                                     |
| **Search Method** | BM25 + Semantic + RRF | Semantic + reranking                            | Multi-hop semantic                                     |
| **MCP Server**    | ✅ Native             | ✅ Agent support                                | ❌                                                     |
| **Language**      | Swift (native)        | Rust/Cloud                                      | Python                                                 |

### Why SwiftIndex?

- **Swift-First**: Native SwiftSyntax parsing extracts rich metadata (doc comments, signatures, breadcrumbs) that generic parsers miss
- **Apple Silicon Native**: MLX embeddings are 2-3x faster than Ollama on M1/M2/M3, with zero network latency
- **True Hybrid Search**: RRF fusion of BM25 + semantic search provides better recall than pure semantic approaches
- **Token Efficient**: TOON output format saves 40-60% tokens for AI assistants
- **Privacy**: All processing happens locally — your code never leaves your machine

### When to Use Alternatives

- **mgrep**: If you need multimodal search (PDFs, images) or web search integration
- **ChunkHound**: If you work primarily with Python/JS codebases and don't need Swift-specific features
- **[Context7](https://github.com/upstash/context7)**: For external library documentation (complements SwiftIndex, not a competitor)

## License

MIT License. See [LICENSE](LICENSE) for details.
