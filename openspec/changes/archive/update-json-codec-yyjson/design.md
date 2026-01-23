## Context

SwiftIndex uses Foundation JSONEncoder/JSONDecoder and JSONSerialization across MCP JSON-RPC, storage metadata, and HTTP embedding clients. Performance and memory use are important for large payloads. swift-yyjson provides API-compatible alternatives with lower allocations, but it introduces a C dependency and requires Swift 6.1+/Xcode 16+ (per upstream README).

## Goals / Non-Goals

- Goals:
  - Reduce JSON parse/encode allocations and peak memory for large payloads.
  - Keep Codable workflows intact.
  - Preserve strict RFC 8259 JSON parsing (no JSON5/comments/trailing commas).
- Non-Goals:
  - Introduce new user-facing configuration to pick JSON codecs.
  - Change JSON-RPC wire format or tool schemas.

## Decisions

- Decision: Adopt `swift-yyjson` as the default JSON codec.
  - Rationale: Fast parsing/encoding with lower memory and drop-in Codable APIs.
- Decision: Enable `strictStandardJSON` trait to disable JSON5 features.
  - Rationale: Maintain current strict JSON behavior.
- Decision: Replace `JSONSerialization` usage with `YYJSONSerialization` where feasible.
  - Rationale: Keep behavior consistent and reduce allocations.

## Alternatives Considered

- Keep Foundation JSON APIs.
  - Pros: No new dependency or toolchain bump.
  - Cons: Higher allocations and memory for large payloads.
- ZippyJSON / IkigaJSON.
  - Pros: Faster than Foundation.
  - Cons: Different APIs, less comprehensive feature set, less documentation coverage for this project.

## Risks / Trade-offs

- Toolchain bump to Swift 6.1+/Xcode 16+ may affect contributors and CI.
- API gaps vs Foundation: `YYJSONEncoder` uses `writeOptions` (not `outputFormatting`), and some strategies may be unsupported.
- Error types differ (`YYJSONError` vs `DecodingError`/`EncodingError`).
- Number precision: yyjson parses numbers as 64-bit ints or doubles; extremely large integers can lose precision.

## Migration Plan

1. Update `Package.swift` toolchain (if required) and add swift-yyjson dependency with `strictStandardJSON` trait.
2. Introduce a small JSON codec adapter to map existing encoder options.
3. Replace all JSONEncoder/JSONDecoder/JSONSerialization usages in core, MCP, and CLI.
4. Update tests and add coverage for strict JSON rejection.
5. Validate behavior parity for JSON-RPC messages and embedding API payloads.

## Open Questions

- Does `YYJSONWriteOptions` support sorted key output? If not, do we drop sorting or re-serialize using `YYJSONSerialization` for deterministic output?
- Are there any CI/tooling constraints that block Swift 6.1+ adoption?
