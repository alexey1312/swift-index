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

## Impact

- **Affected specs**: storage, parsing, search
- **Affected files**: ~15 files
- **Breaking changes**: Requires re-indexing (v1.0 not yet released — acceptable)
- **Backward compatibility**: Not required (pre-release)
