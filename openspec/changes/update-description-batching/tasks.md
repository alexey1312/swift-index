## 1. Implementation

- [ ] 1.1 Add `description_batch_size` to `SearchEnhancementConfig` (utility tier) and wire it through TOML/env loaders.
- [ ] 1.2 Add config for grouped requests (`description_batch_mode`, `description_chunks_per_request`) and wire into LLM description generation.
- [ ] 1.3 Update config validation to allow new keys and enforce positive integers and valid mode values.
- [ ] 1.4 Pass configured batch size and grouping options to `DescriptionGenerator` in `IndexCommand`.
- [ ] 1.5 Update/extend `DescriptionGenerator` tests to cover configured batch size and grouped-request behavior (success, parse failure, fallback).

## 2. Documentation

- [ ] 2.1 Update configuration spec delta with the new key and default value.
- [ ] 2.2 Update sample config/docs (if any) to include `description_batch_size` and grouped-request guidance.
