# Change: Cross-file embedding batching during indexing

## Why

Indexing currently calls embedding per file, which often yields small batches. This underutilizes MLX/GPU and increases per-call overhead, slowing indexing on medium/large codebases.

## What Changes

- Aggregate chunks across files into larger embedding batches during indexing.
- Add a batching coordinator that respects a configurable batch size and flushes on completion/timeout.
- Preserve per-file indexing behavior and change-detection while reducing embedding calls.

## Impact

- Affected specs: `embedding`
- Affected code: `Sources/swiftindex/Commands/IndexCommand.swift`, embedding batching utilities (new), tests
