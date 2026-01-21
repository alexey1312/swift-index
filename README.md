# SwiftIndex

A semantic code search engine for Swift codebases, available as both a CLI tool and an MCP server for AI assistants like Claude Code.

## Features

- **Hybrid Search**: Combines BM25 full-text search with semantic vector search using RRF fusion
- **Swift-First Parsing**: Uses SwiftSyntax for accurate Swift parsing with tree-sitter fallback for ObjC, C, JSON, YAML, and Markdown
- **Local-First Embeddings**: Privacy-preserving embedding generation using MLX (Apple Silicon) or swift-embeddings
- **Incremental Indexing**: Only re-indexes changed files based on content hashes
- **Watch Mode**: Automatically updates the index when files change
- **MCP Server**: Exposes search capabilities to AI assistants via Model Context Protocol

## Installation

### From Source

```bash
git clone https://github.com/alexey1312/swift-index.git
cd swift-index
swift build -c release
cp .build/release/swiftindex /usr/local/bin/
```

### Install for Claude Code

```bash
swiftindex install-claude-code
```

This adds SwiftIndex as an MCP server to Claude Code's configuration.

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
swiftindex index --watch .

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

# JSON output
swiftindex search --json "error handling"

# Adjust semantic weight (0.0 = BM25 only, 1.0 = semantic only)
swiftindex search --semantic-weight 0.7 "networking code"
```

### `swiftindex init`

Initialize configuration for a project.

```bash
swiftindex init
```

### `swiftindex install-claude-code [target]`

Install SwiftIndex as an MCP server.

```bash
# Install for Claude Code (default)
swiftindex install-claude-code

# Install for Cursor
swiftindex install-claude-code cursor

# Dry run to see what would be configured
swiftindex install-claude-code --dry-run
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
# Embedding provider: "mlx", "swift-embeddings", "ollama", "openai", "voyage"
provider = "mlx"

# Model to use (provider-specific)
model = "bge-small-en-v1.5"

# Vector dimension
dimension = 384

[search]
# Default number of results
limit = 20

# Semantic weight for hybrid search (0.0-1.0)
semantic_weight = 0.7

# RRF fusion constant
rrf_k = 60

[storage]
# Index storage location
directory = ".swiftindex"
```

### Configuration Priority

Configuration is loaded from multiple sources with the following priority (highest first):

1. **CLI arguments**: `--config`, `--limit`, etc.
2. **Environment variables**: `SWIFTINDEX_*` prefixed
3. **Project config**: `.swiftindex.toml` in project root
4. **Default config**: Built-in defaults

### Environment Variables

| Variable               | Description                      |
| ---------------------- | -------------------------------- |
| `SWIFTINDEX_PROVIDER`  | Embedding provider               |
| `SWIFTINDEX_MODEL`     | Embedding model name             |
| `SWIFTINDEX_DIMENSION` | Vector dimension                 |
| `SWIFTINDEX_LIMIT`     | Default search limit             |
| `OPENAI_API_KEY`       | API key for OpenAI embeddings    |
| `VOYAGE_API_KEY`       | API key for Voyage AI embeddings |

## MCP Tools

When running as an MCP server, SwiftIndex exposes the following tools:

### `swiftindex_search`

Search for code in the indexed codebase.

**Parameters:**

- `query` (required): Search query string
- `limit` (optional): Maximum results (default: 20)
- `semantic_weight` (optional): Weight for semantic search (0.0-1.0, default: 0.7)

**Example:**

```json
{
  "query": "user authentication flow",
  "limit": 10,
  "semantic_weight": 0.8
}
```

### `swiftindex_index`

Trigger indexing of the codebase.

**Parameters:**

- `path` (optional): Path to index (default: current directory)
- `force` (optional): Force re-index all files (default: false)

### `swiftindex_status`

Get the current index status.

**Returns:**

- Indexed file count
- Total chunks
- Last index time
- Provider status

## Embedding Providers

SwiftIndex supports multiple embedding providers:

### MLX (Default)

Hardware-accelerated embeddings on Apple Silicon. Fastest option for local use.

```toml
[embedding]
provider = "mlx"
model = "bge-small-en-v1.5"
```

### Swift Embeddings

Pure Swift implementation, works on all platforms. Fallback when MLX is unavailable.

```toml
[embedding]
provider = "swift-embeddings"
model = "bge-small"
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
├── Config/          # Configuration loading and merging
├── Embedding/       # Embedding providers (MLX, OpenAI, etc.)
├── Models/          # Core data models (CodeChunk, SearchResult)
├── Parsing/         # SwiftSyntax and tree-sitter parsers
├── Protocols/       # Core protocol definitions
├── Search/          # Hybrid search engine with RRF fusion
└── Storage/         # GRDB chunk store + USearch vector store

SwiftIndexMCP/
└── MCPServer.swift  # MCP server implementation

swiftindex/
└── main.swift       # CLI entry point
```

### Storage

- **Chunk Store**: SQLite database with FTS5 for full-text search (GRDB)
- **Vector Store**: HNSW index for approximate nearest neighbor search (USearch)

### Search Algorithm

1. Generate query embedding
2. Perform BM25 full-text search
3. Perform semantic similarity search
4. Combine results using Reciprocal Rank Fusion (RRF)
5. Return top-k results sorted by fused score

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

## License

MIT License. See [LICENSE](LICENSE) for details.
