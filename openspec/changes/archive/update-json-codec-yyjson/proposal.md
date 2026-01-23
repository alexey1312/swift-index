# Change: Replace Foundation JSON codec with swift-yyjson

## Why

JSON encoding/decoding happens in MCP JSON-RPC, storage metadata, and embedding API clients. Using swift-yyjson can significantly reduce allocations and memory usage for large payloads while preserving Codable ergonomics.

## What Changes

- Add `swift-yyjson` dependency and adopt `YYJSONEncoder`, `YYJSONDecoder`, and `YYJSONSerialization` as the default JSON codec.
- Map existing encoder configuration (`outputFormatting`, date strategies) to `YYJSONWriteOptions` equivalents.
- Enforce strict RFC 8259 parsing (disable JSON5 features) via package traits.
- Update tests to validate behavior with the new codec.
- **BREAKING**: Require Swift 6.1+/Xcode 16+ if `swift-yyjson` requires this toolchain.

## Impact

- Affected specs: `specs/mcp-server/spec.md`
- Affected code: MCP server JSON-RPC, storage metadata encoding, embedding providers, CLI JSON output
- Tooling: `Package.swift` (dependency + potential swift-tools-version bump)
