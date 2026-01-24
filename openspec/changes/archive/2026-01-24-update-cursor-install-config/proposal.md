# Change: Update Cursor install configuration

## Why

Cursor MCP configuration uses a dedicated per-project file at `.cursor/mcp.json` and requires `type = "stdio"` for stdio servers. The current `install-cursor` behavior writes `.mcp.json` in the project root and omits the `type` field, which is incompatible with Cursor’s documented requirements.

## What Changes

- Update `install-cursor` project-local target path to `.cursor/mcp.json`.
- Ensure `install-cursor` writes `type = "stdio"` for Cursor MCP stdio servers.
- Preserve existing `mcp.json` content and only add/update the `swiftindex` server entry unless `--force` is used.
- Update CLI spec and user-facing docs to reflect the correct Cursor config locations and format.
- Document that Cursor MCP install links use the same `mcp.json`-style config and can be generated from the written config.

## Impact

- Affected specs: `openspec/specs/cli/spec.md`
- Affected code: `Sources/swiftindex/Commands/InstallCursorCommand.swift`, documentation in `README.md`
