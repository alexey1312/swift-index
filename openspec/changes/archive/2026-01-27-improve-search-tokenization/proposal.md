# Change: Improve Search Tokenization

## Why

Benchmarks (v4) revealed that exact searches for rare CamelCase types like `USearchError` return 0 relevant results, while semantic search returns broad matches for "Search". This is likely due to the `porter` stemmer in the FTS5 tokenizer configuration, which is optimized for English prose and can mangle code identifiers.

For code search, exact token matching is more critical than linguistic stemming (e.g., finding "run" when searching "running").

## What Changes

- **Storage:** Update `GRDBChunkStore` FTS5 table configuration to use `tokenize='unicode61'` instead of `tokenize='porter unicode61'`.
- **Migration:** Add a new database migration (`v9_tokenizer_fix`) to drop and recreate the FTS5 virtual tables with the new tokenizer settings.

## Impact

- **Affected Specs:** `storage`
- **Affected Code:** `GRDBChunkStore.swift`
- **User Experience:** Improved precision for exact identifier searches. Slightly reduced recall for natural language variations in comments (e.g., "processing" won't match "process"), which is an acceptable trade-off for code.
