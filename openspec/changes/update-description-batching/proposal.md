# Change: Configurable LLM description batch size

## Why

Description generation during indexing uses a hardcoded batch size of 5. For local and stable providers (e.g., Ollama) users may want higher parallelism, while cloud providers often need conservative settings to avoid rate limits and timeouts. A configurable batch size allows controlled tuning without code changes.

## What Changes

- Add a configuration key `search.enhancement.utility.description_batch_size` with a default of 5.
- Add an experimental mode to group multiple chunks into a single LLM request with structured JSON output and strict validation.
- Add configuration keys to control grouping mode and chunks per request.
- Validate that the value is a positive integer.
- Wire `IndexCommand` to pass the configured batch size into `DescriptionGenerator`.
- Document the new option in configuration defaults and samples.

## Impact

- Affected specs: `configuration`
- Affected code: `Sources/swiftindex/Commands/IndexCommand.swift`, `Sources/SwiftIndexCore/LLM/DescriptionGenerator.swift`, configuration loader/validator, LLM description tests/docs
