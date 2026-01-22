# Change: Add Phase 3 Features and Spec Compliance

## Why

SwiftIndex Phase 1-2 are implemented, but there are discrepancies with the locked specs:

1. **CLI Spec compliance:** Requires separate commands `install-cursor`, `install-codex`, `install-claude-code` with correct paths
2. **Embedding Providers:** Current implementations return placeholder/random vectors instead of real embeddings
3. **MCP Integration:** Install commands must write correct MCP configuration format for each platform

## What Changes

### MODIFIED: CLI Install Commands

Split install command into separate commands per spec:

- `swiftindex install-claude-code` — writes to `~/.claude.json`:
  ```json
  {"mcpServers":{"swiftindex":{"type":"stdio","command":"...","args":["serve"]}}}
  ```

- `swiftindex install-cursor` — writes to `~/.cursor/mcp.json`:
  ```json
  {"mcpServers":{"swiftindex":{"command":"...","args":["serve"]}}}
  ```

- `swiftindex install-codex` — writes to `~/.codex/config.toml`:
  ```toml
  [mcp_servers.swiftindex]
  command = "..."
  args = ["serve"]
  ```

### MODIFIED: SwiftEmbeddingsProvider

Replace placeholder `BertModel` struct with actual swift-embeddings API:

- Use `Bert.loadModelBundle()` to load real BERT models
- Use `modelBundle.encode()` for real embedding generation
- Remove `SeededRandomNumberGenerator` placeholder

### MODIFIED: MLXEmbeddingProvider

Update to use mlx-swift-lm MLXEmbedders:

- Add mlx-swift-lm dependency to Package.swift
- Use `MLXEmbedders.loadModelContainer()` for real model loading
- Remove `computeEmbedding()` placeholder that returns random vectors

## Impact

### Affected Specs

- `cli/spec.md` — MODIFIED: separate install commands with correct MCP configuration paths
- `embedding/spec.md` — MODIFIED: real embeddings requirement clarified

### Affected Code

- `Sources/swiftindex/Commands/InstallClaudeCodeCommand.swift` — NEW (replaces InstallCommand)
- `Sources/swiftindex/Commands/InstallCursorCommand.swift` — NEW
- `Sources/swiftindex/Commands/InstallCodexCommand.swift` — NEW
- `Sources/swiftindex/Commands/InstallCommand.swift` — REMOVED
- `Sources/SwiftIndexCore/Embedding/SwiftEmbeddingsProvider.swift` — MODIFIED
- `Sources/SwiftIndexCore/Embedding/MLXEmbeddingProvider.swift` — MODIFIED
- `Package.swift` — MODIFIED (add mlx-swift-lm)
- `Sources/swiftindex/SwiftIndex.swift` — MODIFIED (register new commands)
