# Change: Add Gemini Support and Graceful Shutdown

## Why

The current system lacks support for Google's Gemini ecosystem, preventing users from utilizing Gemini as an embedding/LLM provider or easily configuring the Gemini CLI assistant. Additionally, interrupting the `swiftindex index` command via `Ctrl+C` causes a crash (`mutex lock failed`) due to unsafe termination of the MLX backend.

## What Changes

- **Gemini Provider**: Adds native support for Google Gemini API as both an Embedding Provider and an LLM Provider.
- **CLI Integration**: Adds a `swiftindex install-gemini` command to configure the Gemini CLI assistant.
- **Graceful Shutdown**: Integrates `swift-nio` to handle POSIX signals (`SIGINT`, `SIGTERM`) safely, ensuring resources (indexes, GPU tasks) are flushed and released correctly on interruption.

## Impact

- **Affected specs**: `cli`, `configuration`, `embedding`.
- **Affected code**: `SwiftIndexCore`, `IndexCommand`, `ServeCommand`, `Package.swift`.
- **New dependency**: `apple/swift-nio` (for signal handling).
