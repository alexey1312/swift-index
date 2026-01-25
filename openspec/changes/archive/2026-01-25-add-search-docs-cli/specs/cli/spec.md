## ADDED Requirements

### Requirement: Search Docs Command

The system SHALL provide `swiftindex search-docs` command for searching documentation.

Command:

- `swiftindex search-docs <QUERY>` — search indexed documentation (Markdown, README, etc.)

Options:

- `<query>` — search query (required)
- `--limit <n>` — max results (default: 10)
- `--format <format>` — output format: toon, human, json (default: toon)
- `--path <path>` — project path (default: current directory)
- `--path-filter <glob>` — filter results by path pattern

Result fields:

- `path` — file path
- `startLine`, `endLine` — position in file
- `breadcrumb` — hierarchy path (e.g., "README > Installation > macOS")
- `kind` — snippet type (markdownSection, documentation, example, annotation)
- `content` — documentation text
- `tokenCount` — approximate token count
- `relevancePercent` — relevance score (0-100)

#### Scenario: Basic docs search

- **WHEN** running `swiftindex search-docs "installation instructions"`
- **THEN** displays matching documentation snippets
- **AND** shows file paths, line numbers, and breadcrumbs

#### Scenario: Search docs with limit

- **WHEN** running `swiftindex search-docs "setup" --limit 5`
- **THEN** shows at most 5 documentation results

#### Scenario: Search docs with path filter

- **WHEN** running `swiftindex search-docs "API" --path-filter "docs/**/*.md"`
- **THEN** only returns results from docs directory Markdown files

#### Scenario: Search docs TOON format

- **WHEN** running `swiftindex search-docs "config" --format toon`
- **THEN** outputs token-optimized format with:
  - `docs_search{q,n}:` header
  - `snippets[n]{r,rel,p,l,k,bc,lang,tok}:` tabular results
  - `content[n]:` section with snippet text

#### Scenario: Search docs human format

- **WHEN** running `swiftindex search-docs "config" --format human`
- **THEN** outputs human-readable format with:
  - Result numbering and file paths
  - Kind and breadcrumb display
  - Relevance percentage
  - Content preview (first 10 lines)

#### Scenario: Search docs JSON format

- **WHEN** running `swiftindex search-docs "config" --format json`
- **THEN** outputs JSON with:
  - `query` string
  - `result_count` number
  - `results` array with full snippet metadata

#### Scenario: No index error

- **WHEN** running `swiftindex search-docs "query"` without index
- **THEN** displays error: "No index found"
- **AND** suggests running `swiftindex index` first

#### Scenario: Empty results

- **WHEN** search returns no matches
- **THEN** displays "No documentation found"
- **AND** exits successfully (exit code 0)

## MODIFIED Requirements

### Requirement: CLI Application Structure

The system SHALL provide `swiftindex` CLI built with swift-argument-parser.

Command structure:

- `swiftindex index` — index codebase
- `swiftindex search <query>` — search indexed codebase
- `swiftindex search-docs <query>` — search indexed documentation
- `swiftindex watch` — watch mode with auto-sync
- `swiftindex providers` — list embedding providers
- `swiftindex install-claude-code` — configure Claude Code
- `swiftindex install-codex` — configure Codex
- `swiftindex install-cursor` — configure Cursor
- `swiftindex init` — create config file
- `swiftindex stats` — show index statistics
- `swiftindex clear` — clear index

#### Scenario: Show help

- **WHEN** running `swiftindex --help`
- **THEN** displays all commands with descriptions

#### Scenario: Show version

- **WHEN** running `swiftindex --version`
- **THEN** displays version number
