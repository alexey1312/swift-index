# Design: LLM description batch size tuning

## Context

`DescriptionGenerator` processes code chunks in parallel with a fixed batch size (currently 5). The optimal value depends on provider stability and rate limits. Claude/OpenAI often require conservative parallelism, while local providers can benefit from higher batch sizes.

## Goals / Non-Goals

- Goals:
  - Allow users to tune description generation parallelism without code edits.
  - Keep a safe default that minimizes rate-limit errors for cloud providers.
  - Provide an experimental option to group multiple chunks into a single LLM request.
  - Preserve current request model (one chunk per prompt) as the default.
- Non-Goals:
  - Changing the description prompt format for the default (single-chunk) mode.
  - Provider-specific auto-tuning (can be added later).

## Decisions

- Decision: Add `search.enhancement.utility.description_batch_size` with default 5.
  - Rationale: This keeps the current safe behavior while allowing explicit tuning.
- Decision: Add `search.enhancement.utility.description_batch_mode` with default `single`.
  - Rationale: Keep the existing behavior unless explicitly enabled.
- Decision: Add `search.enhancement.utility.description_chunks_per_request` with default 1.
  - Rationale: Allow explicit grouping while keeping validation simple.
- Decision: Validation requires a positive integer (> 0).
  - Rationale: Prevents silent misconfiguration and zero/negative concurrency.

## Alternatives Considered

- Raise default to 10 globally.
  - Rejected: increases risk of rate-limit and timeout failures for cloud providers.
- Combine multiple chunks into a single prompt by default.
  - Rejected: higher failure blast radius, more complex parsing, and quality risks.

## Risks / Trade-offs

- Higher batch sizes increase concurrency and can amplify provider throttling or timeout failures.
- Grouped requests increase failure blast radius and require strict response parsing.
- Users may need to tune per environment; defaults remain conservative.

## Migration Plan

- No migration required. Existing configs remain valid; defaults keep single-chunk mode at batch size 5.

## Grouped Mode JSON Schema

When `description_batch_mode = grouped`, the LLM receives multiple chunks and returns structured JSON:

### Request Format

Chunks are sent with IDs for tracking:

- `chunk_id`: stable identifier (content hash or index)
- `content`: code/signature to describe
- `context`: breadcrumb path

### Response Format

LLM returns a JSON array:

```json
[
  {"id": "chunk_id_1", "description": "Brief description..."},
  {"id": "chunk_id_2", "description": "Brief description..."}
]
```

Validation rules:

- MUST be valid JSON array
- Each item MUST have `id` (string) and `description` (string)
- IDs MUST match requested chunk IDs
- Missing IDs trigger fallback for those chunks

## System Prompt (Grouped Mode)

```
You are a code documentation assistant. Generate brief, accurate descriptions.

For each code chunk, write a 1-2 sentence description explaining:
- What the code does (purpose)
- Key behavior or side effects

Return a JSON array with one object per chunk:
[{"id": "<chunk_id>", "description": "<your description>"}]

Rules:
- Use the exact chunk IDs provided
- Keep descriptions under 100 words
- Focus on behavior, not implementation details
- Return ONLY valid JSON, no markdown or explanations
```

## Fallback Behavior

When grouped request fails, the system applies graduated fallback:

1. **JSON Parse Error**: Entire response invalid
   - Log warning with response preview
   - Retry ALL chunks in batch as single-chunk requests

2. **Partial ID Mismatch**: Some IDs missing/invalid
   - Accept valid descriptions
   - Retry ONLY missing chunks as single-chunk requests

3. **Timeout/Network Error**: No response received
   - Retry entire batch as single-chunk requests
   - Apply exponential backoff per provider config

Fallback is transparent to caller — always returns complete description set.

## Provider Recommendations (Documentation)

| Provider        | Recommended batch_size | Recommended mode     | Rationale                           |
| --------------- | ---------------------- | -------------------- | ----------------------------------- |
| Ollama (local)  | 10-15                  | grouped (3-5 chunks) | High throughput, no rate limits     |
| Claude Code CLI | 5-8                    | single               | Rate limits, high quality per-chunk |
| OpenAI          | 3-5                    | single               | API rate limits, cost per call      |
| Codex CLI       | 5-8                    | single               | Similar to Claude                   |

These are suggestions for documentation; defaults remain conservative (5, single).

## Progress Reporting

Description generation runs silently inside file indexing. Users see no feedback during long-running LLM operations.

### Decisions

- Decision: Add progress callback to `generateBatch()` method.
  - Rationale: Allows CLI/MCP to report intermediate progress.

- Decision: Report progress per batch completion, not per chunk.
  - Rationale: Reduces callback overhead while providing meaningful updates.

- Decision: Use Noora nested step for description progress.
  - Rationale: Integrates with existing progress bar without replacing it.

### Progress Callback Signature

```swift
public typealias DescriptionProgressCallback = @Sendable (
    _ completed: Int,    // chunks with descriptions generated
    _ total: Int,        // total chunks in file
    _ currentFile: String // file being processed
) async -> Void
```

### CLI Display

```
⠹ Indexing files ██████▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒  25%
  └─ Descriptions: 12/45 (LoginManager.swift)
```

### MCP Integration

MCP server emits `indexing/progress` notifications:

```json
{
  "type": "progress",
  "phase": "descriptions",
  "current": 12,
  "total": 45,
  "file": "OAuth/LoginManager.swift"
}
```

## Open Questions

None — all questions resolved.
