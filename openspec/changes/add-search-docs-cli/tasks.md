# Tasks: Add search-docs Command to CLI

## 1. Create SearchDocsCommand

- [x] 1.1 Create `SearchDocsCommand.swift` in Commands directory
- [x] 1.2 Define arguments: query (required)
- [x] 1.3 Define options: limit, format, path, path-filter
- [x] 1.4 Implement run() using HybridSearchEngine.searchInfoSnippets()

## 2. Output Formatters

- [x] 2.1 Implement TOON format (copy from SearchDocsTool)
- [x] 2.2 Implement human format (copy from SearchDocsTool)
- [x] 2.3 Implement JSON format (copy from SearchDocsTool)
- [x] 2.4 Extract common formatting logic to shared utility (Skipped: Decided to inline to avoid cross-module refactoring for now, as data structures differ)

## 3. Register Command

- [x] 3.1 Add SearchDocsCommand to SwiftIndex subcommands
- [x] 3.2 Update help text and command configuration

## 4. Testing

- [x] 4.1 Add unit tests for SearchDocsCommand
- [x] 4.2 Add integration tests with indexed Markdown
- [x] 4.3 Test all output formats

## 5. Documentation

- [x] 5.1 Update CLAUDE.md with new command (Already present)
- [x] 5.2 Add usage examples (Added to SwiftIndexApp help text)
