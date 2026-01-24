## 1. Data Models

- [x] 1.1 Create `InitMode` enum (interactive, defaults)
- [x] 1.2 Create `EmbeddingProviderOption` enum with descriptions
- [x] 1.3 Create `LLMProviderOption` enum with descriptions
- [x] 1.4 Create provider-specific model option enums (MLXModel, SwiftModel, etc.)

## 2. Interactive Flow

- [x] 2.1 Add TTY detection helper (`isInteractiveTerminal`)
- [x] 2.2 Implement mode selection prompt (Noora `singleChoicePrompt`)
- [x] 2.3 Implement embedding provider selection with preselection from `--provider`
- [x] 2.4 Implement model selection with provider-specific options and "Custom..." fallback
- [x] 2.5 Implement LLM enhancement yes/no prompt
- [x] 2.6 Implement LLM provider selection (conditional on 2.5)
- [x] 2.7 Implement config exists overwrite prompt (skip if `--force`)

## 3. Validation

- [x] 3.1 Validate Metal toolchain availability for MLX selection
- [x] 3.2 Validate `claude` CLI availability for claude-code-cli selection
- [x] 3.3 Validate `codex` CLI availability for codex-cli selection
- [x] 3.4 Add fallback prompts when validation fails

## 4. Config Generation

- [x] 4.1 Update `generateConfigContent` to accept wizard selections
- [x] 4.2 Set `search.enhancement.enabled` based on LLM choice
- [x] 4.3 Set LLM provider in `[search.enhancement.utility]` and `[search.enhancement.synthesis]`

## 5. Tests

- [x] 5.1 Unit tests for enum conformance to `CaseIterable` and `CustomStringConvertible`
- [x] 5.2 Unit tests for TTY detection helper (via env override)
- [x] 5.3 Integration tests for non-TTY fallback behavior
- [x] 5.4 Integration tests for `--provider`/`--model` preselection
- [x] 5.5 Integration tests for Metal toolchain validation (using env override)

## 6. Documentation

- [x] 6.1 Update CLI help text for `swiftindex init`
- [x] 6.2 Update README with interactive init flow description

---

**Status**: ✅ Complete — all tasks implemented and tested.
