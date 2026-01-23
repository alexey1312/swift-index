## Context

`tools/list` currently reads from a `Dictionary` of tool handlers. Swift dictionaries do not guarantee stable iteration order, which causes nondeterministic tool listings. MCP clients often render tools in list order, so stability matters for user experience and testability.

## Goals / Non-Goals

- Goals:
  - Deterministic `tools/list` ordering.
  - Preserve registration order for default and custom tools.
  - Minimal API changes for MCP server consumers.
- Non-Goals:
  - Changing JSON schema key ordering in tool definitions.
  - Altering tool semantics or execution behavior.

## Decisions

- Decision: Use `OrderedDictionary<String, any MCPToolHandler>` for tool storage.
- Decision: Keep registration order stable; re-registering an existing tool name keeps its original position unless explicitly removed first.

### Alternatives considered

- Sort tools by name before returning. Rejected: loses intentional ordering and adds per-call sorting cost.
- Maintain a parallel `[String]` order list. Rejected: more bookkeeping, higher risk of drift.
- Keep `Dictionary` and accept nondeterminism. Rejected: inconsistent client experience and brittle tests.

## Risks / Trade-offs

- New dependency (`swift-collections`) increases package surface area slightly.
- Re-register semantics may be surprising; will document behavior in tests/spec.

## Migration Plan

1. Add `swift-collections` dependency and target linkage.
2. Replace MCP tool registry with `OrderedDictionary`.
3. Add/adjust tests for `tools/list` ordering.

## Open Questions

- (Resolved) Re-registering an existing tool keeps its original order unless explicitly unregistered first.
