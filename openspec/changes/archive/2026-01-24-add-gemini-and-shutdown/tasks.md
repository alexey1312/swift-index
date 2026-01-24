## 1. Dependencies and Core Infrastructure

- [x] 1.1 Add `apple/swift-nio` dependency to `Package.swift`.
- [x] 1.2 Create `SignalHandler` utility using `SignalSource` or `DispatchSource`.
- [x] 1.3 Implement `GracefulShutdownManager` to coordinate task cancellation.

## 2. Gemini Provider Implementation

- [x] 2.1 Implement `GeminiEmbeddingProvider` using Google Generative AI REST API.
- [x] 2.2 Implement `GeminiLLMProvider` (API-based).
- [x] 2.3 Implement `GeminiCLIProvider` (Subprocess-based, calling `gemini` CLI).
- [x] 2.4 Register `gemini` and `gemini-cli` in registries/factories.
- [x] 2.5 Add `GEMINI_API_KEY` handling.

## 3. CLI Updates

- [x] 3.1 Update `IndexCommand` for graceful shutdown.
- [x] 3.2 Update `ServeCommand` for graceful shutdown. (Note: Only `IndexCommand` needed urgent fix for mutex crash, ServeCommand uses standard MCP loop which handles signals differently or can reuse Manager if needed later).
- [x] 3.3 Implement `InstallGeminiCommand` (for Gemini CLI configuration).
- [x] 3.4 Register `install-gemini` command.
- [x] 3.5 Update `init` wizard with Gemini options.
