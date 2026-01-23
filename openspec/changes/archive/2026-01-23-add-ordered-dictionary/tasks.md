## 1. Implementation

- [x] 1.1 Add `swift-collections` dependency and link it to `SwiftIndexMCP`.
- [x] 1.2 Replace MCP tool registry storage with `OrderedDictionary` and preserve registration order in `tools/list`.
- [x] 1.3 Add MCP tests to assert deterministic tool ordering, including re-register behavior.

## 2. Validation

- [x] 2.1 Run `openspec validate add-ordered-dictionary --strict`.
