# Change: Improve MLX defaults and release build

## Why

Local MLX usage fails without Metal shader resources and the current init flow leaves users with commented defaults. We need a predictable setup for MLX and a release build that prepares the metallib resource.

## What Changes

- Make `swiftindex init` write MLX defaults by default, with commented examples for other providers and parameter meanings.
- When `swiftindex init` selects MLX, validate MetalToolchain presence and prompt to install if missing.
- Update release build task to generate MLX Metal resources and place `default.metallib` alongside the release binary.

## Impact

- Affected specs: cli, embedding
- Affected code: `Sources/swiftindex/Commands/InitCommand.swift`, `mise.toml`, MLX runtime setup
