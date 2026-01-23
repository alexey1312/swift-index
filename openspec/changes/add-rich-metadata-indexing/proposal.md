# Change: Add Rich Metadata Indexing

## Why

The current parsing system extracts `docComment` and `signature` during Swift parsing (`SwiftSyntaxParser.swift:75-83`) but **discards them** when creating `CodeChunk` instances (`SwiftSyntaxParser.swift:395-405`). This is a critical loss of semantic information that could significantly improve search relevance.

Analysis of Context7's data model revealed a richer approach:

- **Code Snippets**: title, description, language, tokenCount, codeList
- **Info Snippets**: breadcrumb, content, contentTokens
- **Separation of code and documentation** for independent search

## What Changes

**Phase 1 — Extended CodeChunk** (COMPLETED)

- MODIFIED: `CodeChunk` — added `docComment`, `signature`, `breadcrumb`, `tokenCount`, `language`
- MODIFIED: `GRDBChunkStore` — extended DB schema with v2 migration
- MODIFIED: `SwiftSyntaxParser` — wires extracted metadata through to CodeChunk
- MODIFIED: `TreeSitterParser` — extracts metadata for non-Swift files
- MODIFIED: `SearchCommand` / `SearchCodeTool` — updated output formatters

**Phase 2 — Info Snippets** (PENDING)

- ADDED: `InfoSnippet` — new entity for standalone documentation
- ADDED: `InfoSnippetStore` — storage for documentation snippets
- MODIFIED: `HybridSearchEngine` — search across info snippets

**Phase 3 — Advanced Features** (PENDING)

- ADDED: Parallel indexing with TaskGroup
- ADDED: Content-based chunk hashing for change detection
- ADDED: Optional LLM-generated descriptions

**Phase 4 — LLM Code Research** (PENDING)

ChunkHound-inspired LLM integration at **query time** for enhanced search UX:

- ADDED: `LLMProvider` protocol — abstraction for LLM backends
- ADDED: `LLMMessage` — message model (role + content)
- ADDED: `LLMProviderChain` — fallback chain (like EmbeddingProviderChain)
- ADDED: `ClaudeCodeCLIProvider` — Claude Code CLI subprocess integration
- ADDED: `CodexCLIProvider` — Codex CLI subprocess integration
- ADDED: `OllamaLLMProvider` — Ollama HTTP API integration
- ADDED: `OpenAILLMProvider` — OpenAI HTTP API integration
- ADDED: `QueryExpander` — LLM-powered query expansion for better recall
- ADDED: `ResultSynthesizer` — multi-result summarization
- ADDED: `FollowUpGenerator` — suggested follow-up queries
- MODIFIED: `Config` — add `SearchEnhancementConfig` struct with dual-tier LLM config
- MODIFIED: `TOMLConfigLoader` — parse `[search.enhancement]` section
- MODIFIED: `HybridSearchEngine` — integrate query expansion
- MODIFIED: `SearchCodeTool` — add synthesis & follow-ups to MCP response
- MODIFIED: `SearchCommand` — add `--expand-query` flag

**Dual-Tier Architecture**:

- **Utility tier**: Fast operations (query expansion, follow-ups, classification)
- **Synthesis tier**: Deep analysis (result summarization, large context)

**Configuration**:

```toml
[search]
semantic_weight = 0.7
rrf_k = 60

# LLM-powered search enhancements (query expansion, result synthesis)
[search.enhancement]
enabled = false  # opt-in by default

[search.enhancement.utility]
provider = "claude-code-cli"  # claude-code-cli | codex-cli | ollama | openai
model = "claude-haiku-4-5-20251001"  # optional override
timeout = 30

[search.enhancement.synthesis]
provider = "claude-code-cli"
model = "claude-sonnet-4-20250514"
timeout = 120
```

**Phase 5 — Documentation Update** (PENDING)

Final documentation pass after all implementation phases:

- MODIFIED: `README.md` — comprehensive feature documentation
- MODIFIED: `CLAUDE.md` — updated project guide with new commands/flags
- ADDED: `docs/search-enhancement.md` — LLM provider configuration guide
- ADDED: `docs/search-features.md` — query expansion & synthesis docs
- MODIFIED: Config template comments — inline documentation for all options

## Impact

- **Affected specs**: storage, parsing, search, configuration
- **Affected files**: ~30 files (Phase 1-3: ~15, Phase 4: ~10 new + ~8 modified, Phase 5: ~5 docs)
- **Breaking changes**: Requires re-indexing (v1.0 not yet released — acceptable)
- **Backward compatibility**: Not required (pre-release)
- **Privacy**: LLM features opt-in by default (disabled)
