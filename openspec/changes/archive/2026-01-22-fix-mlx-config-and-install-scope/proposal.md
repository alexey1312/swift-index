# Change: Fix MLX Config Passthrough and Install Command Scope

## Why

Two critical issues discovered during E2E testing:

1. **MLX Memory Crash**: `MLXEmbeddingProvider()` ignores config model/dimension, uses hardcoded `nomic-embed-text-v1.5` (768 dim) which attempts to allocate 41GB exceeding Metal's 22GB buffer limit
2. **Install Scope**: `install-claude-code` writes to global `~/.claude.json` instead of project-local `.mcp.json`, causing unintended global configuration

## What Changes

- **BREAKING**: `install-claude-code` default behavior changes from global to project-local
- Add `--global` flag to install commands for explicit global configuration
- Pass config `embeddingModel` and `embeddingDimension` to MLX provider
- Recommend `mlx-community/bge-small-en-v1.5-4bit` (384 dim) as default MLX model for memory safety
- Add `jina-embeddings-v2-base-code` recommendation for code-optimized embeddings

## Impact

- Affected specs: `cli`, `embedding`
- Affected code:
  - `Sources/swiftindex/Commands/InstallClaudeCodeCommand.swift`
  - `Sources/SwiftIndexMCP/MCPContext.swift:70-76`
  - `Sources/SwiftIndexCore/Embedding/MLXEmbeddingProvider.swift`
