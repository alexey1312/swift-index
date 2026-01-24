# Change: Add interactive init mode

## Why

`swiftindex init` currently writes a config with fixed defaults. Users must manually edit provider/model and LLM settings in TOML, which is error-prone and slow. An interactive wizard would guide users through key choices while keeping the option to use defaults for CI/scripts.

## What Changes

### Interactive wizard with Noora

Replace manual `promptYesNo` with Noora's component system:

1. **Mode selection** (first screen) — `singleChoicePrompt`:
   - "Configure interactively" (default)
   - "Use defaults (MLX + no LLM enhancement)"

2. **Embedding provider** — `singleChoicePrompt`:
   - MLX (Apple Silicon, fastest)
   - Swift Embeddings (CPU, no Metal required)
   - Ollama (local server)
   - Voyage (cloud API)
   - OpenAI (cloud API)

3. **Embedding model** — `singleChoicePrompt` with provider-specific options, plus "Custom..." option that triggers `textPrompt`

4. **LLM enhancement** — `yesOrNoChoicePrompt`:
   - If yes → provider selection via `singleChoicePrompt`

5. **Config exists** — `yesOrNoChoicePrompt` to overwrite (if file exists)

### CLI flags preserved

- `--provider` / `--model` — preselect values in wizard
- `--force` — skip overwrite confirmation

### Non-TTY fallback

When stdin is not a TTY (CI, pipes), automatically use defaults without prompts.

## Implementation notes

- Noora is already a dependency (added in commit ef89bd8)
- Use `singleChoicePrompt` with enums for type-safe selections
- Validate provider availability before writing config (check Metal toolchain for MLX, check `claude` CLI for claude-code-cli)

## Impact

- Affected specs: `cli`
- Affected code: `Sources/swiftindex/Commands/InitCommand.swift`
