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

## Open Questions

- Should we add provider-specific recommended values in docs (e.g., Ollama 10–15)?
