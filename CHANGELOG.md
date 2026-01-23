# Changelog

All notable changes to SwiftIndex will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

#### Rich Metadata Indexing (Phase 1)
- Extended `CodeChunk` model with `docComment`, `signature`, `breadcrumb`, `tokenCount`, and `language` fields
- Language detection from file extensions
- Breadcrumb generation from type hierarchy (e.g., "Module > Class > Method")
- Token count estimation for context window planning
- Database schema v2 migration with new metadata columns
- FTS5 index now includes doc comments for improved full-text search

#### Info Snippets for Documentation Search (Phase 2)
- New `InfoSnippet` model for standalone documentation content
- `InfoSnippetStore` protocol for documentation persistence
- FTS5-powered documentation search via `search_docs` MCP tool
- Markdown section extraction as searchable snippets
- Breadcrumb paths for documentation hierarchy (e.g., "README > Installation > macOS")

#### Parallel Indexing & Change Detection (Phase 3)
- `TaskGroup`-based parallel file parsing with bounded concurrency
- `maxConcurrentTasks` configuration option (defaults to CPU core count)
- Thread-safe `AtomicIndexingStats` for progress tracking
- SHA-256 content hashing for precise change detection
- `contentHash` field in `CodeChunk` model
- Database schema v4 migration for content hash column
- `reindexWithChangeDetection()` method for efficient incremental updates
- Vector reuse for unchanged chunks (significant performance improvement)

#### LLM-Powered Search Enhancement (Phase 4)
- `LLMProvider` protocol for text generation abstraction
- `LLMMessage` model with role-based messaging
- `LLMProviderChain` for provider fallback handling
- `ClaudeCodeCLIProvider` - Claude Code CLI subprocess integration
- `CodexCLIProvider` - Codex CLI subprocess integration
- `OllamaLLMProvider` - Ollama HTTP API integration
- `OpenAILLMProvider` - OpenAI HTTP API integration
- `QueryExpander` - LLM-powered query expansion with caching
- `ResultSynthesizer` - Multi-result summarization with insights
- `FollowUpGenerator` - Suggested follow-up queries by category
- `SearchEnhancementConfig` with dual-tier architecture (utility/synthesis)
- `--expand-query` CLI flag for query expansion
- `--synthesize` CLI flag for result synthesis
- `[search.enhancement]` TOML configuration section
- MCP server auto-integration with search enhancement

### Changed

- `SwiftSyntaxParser` now passes extracted metadata to `CodeChunk` constructor
- `TreeSitterParser` extracts metadata for non-Swift files
- `GRDBChunkStore` schema updated to v4 with rich metadata support
- `HybridSearchEngine` supports info snippet search and query expansion
- `SearchCodeTool` MCP response includes synthesis and follow-ups when configured
- `SearchCommand` JSON/TOON output includes all metadata fields
- Config template in `init` command includes LLM provider examples

### Documentation

- Updated README.md with new features and configuration
- Created `docs/search-enhancement.md` - LLM provider configuration guide
- Created `docs/search-features.md` - Query expansion and synthesis documentation
- Updated CLAUDE.md project guide with new module structure

## [0.1.0] - Unreleased

### Added

- Initial release
- Hybrid search with BM25 + semantic vector search + RRF fusion
- SwiftSyntax parser for Swift files
- Tree-sitter parser for ObjC, C, JSON, YAML, Markdown
- MLX embedding provider for Apple Silicon
- Swift Embeddings provider for cross-platform support
- Ollama, OpenAI, and Voyage AI embedding providers
- GRDB-based chunk storage with FTS5
- USearch-based vector storage with HNSW
- Watch mode for automatic re-indexing
- MCP server for AI assistant integration
- CLI with index, search, watch, serve commands
- TOML configuration with multi-source merging
- Homebrew distribution tap
- GitHub Actions release workflow

[Unreleased]: https://github.com/alexey1312/swift-index/compare/main...HEAD
[0.1.0]: https://github.com/alexey1312/swift-index/releases/tag/v0.1.0
