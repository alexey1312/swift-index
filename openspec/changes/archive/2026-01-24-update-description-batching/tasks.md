## 1. Implementation

- [ ] 1.1 Add `description_batch_size` to `SearchEnhancementConfig` (utility tier) and wire it through TOML/env loaders.
- [ ] 1.2 Add config for grouped requests (`description_batch_mode`, `description_chunks_per_request`) and wire into LLM description generation.
- [ ] 1.3 Update config validation to allow new keys and enforce positive integers and valid mode values.
- [ ] 1.4 Pass configured batch size and grouping options to `DescriptionGenerator` in `IndexCommand`.
- [ ] 1.5 Update/extend `DescriptionGenerator` tests to cover configured batch size and grouped-request behavior (success, parse failure, fallback).
- [ ] 1.6 Implement grouped-mode system prompt and JSON response parsing in DescriptionGenerator.

## 2. Documentation

- [ ] 2.1 Update configuration spec delta with the new key and default value.
- [ ] 2.2 Update sample config/docs (if any) to include `description_batch_size` and grouped-request guidance.

## 3. Progress Reporting

- [ ] 3.1 Add `DescriptionProgressCallback` typealias to DescriptionGenerator.
- [ ] 3.2 Extend `generateBatch()` signature with optional `onProgress` callback.
- [ ] 3.3 Call progress callback after each batch completion in generateBatch loop.
- [ ] 3.4 Update IndexCommand to pass Noora progress callback to generateBatch.
- [ ] 3.5 Implement nested Noora step display for description progress.
- [ ] 3.6 Add progress notification emission in MCPServer for indexing.
- [ ] 3.7 Update tests to verify progress callback invocation.
