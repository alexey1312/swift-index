# Tasks: Add search-docs Command to CLI

## 1. Create SearchDocsCommand

- [ ] 1.1 Create `SearchDocsCommand.swift` in Commands directory
- [ ] 1.2 Define arguments: query (required)
- [ ] 1.3 Define options: limit, format, path, path-filter
- [ ] 1.4 Implement run() using HybridSearchEngine.searchInfoSnippets()

## 2. Output Formatters

- [ ] 2.1 Implement TOON format (copy from SearchDocsTool)
- [ ] 2.2 Implement human format (copy from SearchDocsTool)
- [ ] 2.3 Implement JSON format (copy from SearchDocsTool)
- [ ] 2.4 Extract common formatting logic to shared utility

## 3. Register Command

- [ ] 3.1 Add SearchDocsCommand to SwiftIndex subcommands
- [ ] 3.2 Update help text and command configuration

## 4. Testing

- [ ] 4.1 Add unit tests for SearchDocsCommand
- [ ] 4.2 Add integration tests with indexed Markdown
- [ ] 4.3 Test all output formats

## 5. Documentation

- [ ] 5.1 Update CLAUDE.md with new command
- [ ] 5.2 Add usage examples
