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

## Quick Reference

### Build & Test Commands

| Command                             | Description        |
| ----------------------------------- | ------------------ |
| `./bin/mise run build`              | Debug build        |
| `./bin/mise run build:release`      | Release build      |
| `./bin/mise run test`               | Run all tests      |
| `./bin/mise run test:filter <name>` | Run filtered tests |
| `./bin/mise run lint`               | Run linters        |
| `./bin/mise run format`             | Format all code    |

### CLI Commands

| Command                          | Description              |
| -------------------------------- | ------------------------ |
| `swiftindex index [PATH]`        | Index a codebase         |
| `swiftindex search <QUERY>`      | Search indexed code      |
| `swiftindex watch [PATH]`        | Watch mode (incremental) |
| `swiftindex serve`               | Start MCP server         |
| `swiftindex providers`           | List embedding providers |
| `swiftindex init`                | Initialize config        |
| `swiftindex install-claude-code` | Configure Claude Code    |
| `swiftindex install-cursor`      | Configure Cursor         |
| `swiftindex install-codex`       | Configure Codex          |

## Architecture

### Targets

| Target         | Type       | Description                                       |
| -------------- | ---------- | ------------------------------------------------- |
| SwiftIndexCore | Library    | Core engine (parsing, embedding, storage, search) |
| SwiftIndexMCP  | Library    | MCP server implementation                         |
| swiftindex     | Executable | CLI entry point                                   |

### Module Structure (SwiftIndexCore)

- `/Configuration` — TOML config loading
- `/Embedding` — Providers (MLX, Ollama, Voyage, OpenAI, SwiftEmbeddings)
- `/Models` — Data structures (CodeChunk, SearchResult, ChunkKind)
- `/Parsing` — Parsers (SwiftSyntax, Tree-sitter, Plain)
- `/Protocols` — Core abstractions
- `/Search` — BM25, Semantic, HybridSearchEngine, RRFFusion
- `/Storage` — GRDBChunkStore (SQLite/FTS5), USearchVectorStore (HNSW)
- `/Watch` — FileWatcher, IncrementalIndexer

### Key Dependencies

| Package           | Version | Purpose                  |
| ----------------- | ------- | ------------------------ |
| SwiftSyntax       | 600.0.0 | Swift AST parsing        |
| swift-tree-sitter | 0.9.0   | Multi-language parsing   |
| mlx-swift         | 0.30.0  | Apple Silicon embeddings |
| GRDB.swift        | 7.9.0   | SQLite + FTS5            |
| usearch           | 2.23.0  | Vector index (HNSW)      |
| swift-toml        | —       | Configuration            |

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

## Distribution

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

Config priority: CLI args > Environment > `.swiftindex.toml` > Defaults

### Environment Variables

| Variable                        | Description                 |
| ------------------------------- | --------------------------- |
| `SWIFTINDEX_EMBEDDING_PROVIDER` | mlx, ollama, voyage, openai |
| `VOYAGE_API_KEY`                | Voyage AI key               |
| `OPENAI_API_KEY`                | OpenAI key                  |
