# Change: Configuration hygiene and user setup guidance

## Why

Configuration and onboarding should avoid storing API keys in files, catch TOML issues early, and offer clear guidance for AI assistant setup files.

## What Changes

- Add explicit TOML format/lint validation with actionable diagnostics for `.swiftindex.toml`.
- Run TOML format/lint validation on every config load.
- Remove API key fields from config templates and treat API keys as env-only inputs.
- Remove code-optimized model recommendations from init guidance while keeping optional support when explicitly configured.
- Add user-facing recommendations for `AGENTS.md` and `CLAUDE.md` setup.

## Impact

- Affected specs: `configuration`, `cli`, `embedding`
- Affected code: config loading/validation, init template, CLI commands, documentation
