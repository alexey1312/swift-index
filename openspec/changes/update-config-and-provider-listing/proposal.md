# Change: Update Config Loading and Provider Listing

## Why

Current CLI config loading ignores `.swiftindex.toml` because TOML parsing is not wired up, and `swiftindex providers` uses hardcoded placeholder data. This blocks the expected CLI flow and makes provider status unreliable.

## What Changes

- Wire CLI configuration loading to TOML config files (project and global) using `TOMLConfigLoader`.
- Align configuration specification with the actual TOML structure emitted by `swiftindex init` and parsed by `TOMLConfigLoader`.
- Replace placeholder provider listing with a real provider registry backed by `EmbeddingProvider` availability checks.
- Clean up tooling TODOs in `bin/mise` (refactor and add signature verification where feasible).

## Impact

- Affected specs: `openspec/specs/configuration/spec.md`, `openspec/specs/cli/spec.md`
- Affected code: `Sources/swiftindex/Commands/CommandUtilities.swift`, `Sources/SwiftIndexCore/Configuration/TOMLConfigLoader.swift`, `Sources/swiftindex/Commands/ProvidersCommand.swift`, `bin/mise`
