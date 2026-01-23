## 1. Specification

- [x] 1.1 Add configuration spec deltas for TOML lint/format checks and env-only API keys
- [x] 1.2 Add CLI spec delta for config lint/format command and init guidance updates
- [x] 1.3 Add embedding spec delta removing code-model recommendations from init guidance

## 2. Implementation

- [x] 2.1 Implement TOML lint/format validation and wiring in CLI command
- [x] 2.2 Run TOML lint/format validation on any config load path
- [x] 2.3 Update `swiftindex init` template to remove API key fields and mention env vars
- [x] 2.4 Update init output/docs with AGENTS.md and CLAUDE.md recommendations
- [x] 2.5 Update docs that reference code-optimized model recommendations

## 3. Tests

- [x] 3.1 Add config lint/format validation tests
- [x] 3.2 Add init template regression tests (no API keys)
