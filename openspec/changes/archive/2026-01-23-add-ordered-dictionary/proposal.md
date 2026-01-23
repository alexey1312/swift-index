# Change: Add OrderedDictionary for deterministic MCP tool ordering

## Why

MCP tool definitions are stored in a `Dictionary`, so `tools/list` can return tools in nondeterministic order. This makes client UIs inconsistent and produces noisy diffs for snapshots. `OrderedDictionary` preserves insertion order without extra sorting logic.

## What Changes

- Add `swift-collections` dependency and expose `OrderedDictionary` to `SwiftIndexMCP`.
- Store MCP tool handlers in an `OrderedDictionary` to preserve registration order.
- Ensure `tools/list` emits tools in insertion order (default + custom tools).
- Define re-register behavior for existing tool names (order is stable unless removed).
- Add tests to lock the ordering behavior.

## Impact

- Affected specs: `mcp-server`
- Affected code: `Package.swift`, `Sources/SwiftIndexMCP/MCPServer.swift`, MCP tests
- Compatibility: non-breaking; output ordering becomes deterministic
