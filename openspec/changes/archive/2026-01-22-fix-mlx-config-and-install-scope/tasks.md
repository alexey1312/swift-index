## 1. Install Command Scope Fix

- [x] 1.1 Add `--global` flag to `InstallClaudeCodeCommand`
- [x] 1.2 Change default behavior to write `.mcp.json` in current directory
- [x] 1.3 When `--global` is passed, write to `~/.claude.json` (current behavior)
- [x] 1.4 Apply same pattern to `install-codex` and `install-cursor` commands
- [x] 1.5 Update command help text to explain scope options

## 2. MLX Config Passthrough Fix

- [x] 2.1 Update `MCPContext.swift` to pass config model/dimension to `MLXEmbeddingProvider`
- [x] 2.2 Update `MLXEmbeddingProvider` initializer to accept optional model/dimension parameters
- [x] 2.3 Change default MLX model from `nomic-embed-text-v1.5` to `bge-small-en-v1.5-4bit`
- [x] 2.4 Add memory-safe batch size handling based on model dimension

## 3. Model Recommendations

- [x] 3.1 Document `mlx-community/bge-small-en-v1.5-4bit` as default MLX model (384 dim, memory-safe)
- [x] 3.2 Add `jina-embeddings-v2-base-code` option for code-optimized embeddings
- [x] 3.3 Update `swiftindex init` to use memory-safe defaults

## 4. Testing

- [x] 4.1 Test `install-claude-code` creates `.mcp.json` locally by default
- [x] 4.2 Test `install-claude-code --global` writes to `~/.claude.json`
- [x] 4.3 Test MLX provider uses config model when specified
- [x] 4.4 Test indexing completes without memory crash on Apple Silicon
