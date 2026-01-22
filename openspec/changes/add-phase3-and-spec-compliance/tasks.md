# Tasks: Phase 3 and Spec Compliance

## Phase A: CLI Install Commands

### A.1 Create InstallClaudeCodeCommand

- [x] A.1.1 Create `InstallClaudeCodeCommand.swift`
- [x] A.1.2 Write to `~/.claude.json` (JSON format with `type: stdio`)
- [x] A.1.3 Handle: file not exists / exists / already configured
- [ ] A.1.4 Add unit tests

### A.2 Create InstallCursorCommand

- [x] A.2.1 Create `InstallCursorCommand.swift`
- [x] A.2.2 Write to `~/.cursor/mcp.json` (JSON format)
- [x] A.2.3 Handle: file not exists / exists / already configured
- [ ] A.2.4 Add unit tests

### A.3 Create InstallCodexCommand

- [x] A.3.1 Create `InstallCodexCommand.swift`
- [x] A.3.2 Write to `~/.codex/config.toml` (TOML format)
- [x] A.3.3 Handle: file not exists / exists / already configured
- [ ] A.3.4 Add unit tests

### A.4 Update CLI Registration

- [x] A.4.1 Remove old `InstallCommand.swift`
- [x] A.4.2 Register new commands in `SwiftIndex.swift`

### A.5 Gate: CLI Complete

- [ ] **GATE A:** `swiftindex install-claude-code` works
- [ ] **GATE A:** `swiftindex install-cursor` works
- [ ] **GATE A:** `swiftindex install-codex` works
- [ ] **GATE A:** All tests pass

---

## Phase B: Embedding Providers Fix

### B.1 Fix SwiftEmbeddingsProvider

- [x] B.1.1 Study swift-embeddings API (`Bert.loadModelBundle`, `encode`, `batchEncode`)
- [x] B.1.2 Remove placeholder `BertModel` struct
- [x] B.1.3 Use real `Bert.loadModelBundle()` from swift-embeddings
- [x] B.1.4 Use real `modelBundle.encode()` for embedding generation
- [ ] B.1.5 Add unit tests

### B.2 Fix MLXEmbeddingProvider

- [x] B.2.1 Study MLXEmbedders API from mlx-swift-lm
- [x] B.2.2 Add mlx-swift-lm dependency to Package.swift
- [x] B.2.3 Use `MLXEmbedders.loadModelContainer()` for model loading
- [x] B.2.4 Remove `computeEmbedding()` placeholder
- [ ] B.2.5 Add unit tests

### B.3 Gate: Embedding Providers Complete

- [ ] **GATE B:** SwiftEmbeddingsProvider returns real embeddings
- [ ] **GATE B:** MLXEmbeddingProvider returns real embeddings
- [ ] **GATE B:** Cosine similarity between similar texts > 0.8
- [ ] **GATE B:** Tests pass

---

## Phase C: Verification

### C.1 Build and Test

- [ ] C.1.1 Run `./bin/mise run build`
- [ ] C.1.2 Run `./bin/mise run test`
- [ ] C.1.3 Run `./bin/mise run lint`

### C.2 Manual Testing

- [ ] C.2.1 Test `swiftindex install-claude-code`
- [ ] C.2.2 Test `swiftindex install-cursor`
- [ ] C.2.3 Test `swiftindex install-codex`
- [ ] C.2.4 Test embedding generation with `swiftindex index`
