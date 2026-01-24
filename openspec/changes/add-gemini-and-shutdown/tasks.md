## 1. Dependencies and Core Infrastructure

- [ ] 1.1 Add `apple/swift-nio` dependency to `Package.swift`.
- [ ] 1.2 Create `SignalHandler` utility using `SignalSource` or `DispatchSource` (if NIO is overkill, but proposal says NIO). _Refinement: Using `DispatchSource` from standard lib is often sufficient for simple CLI signal handling without pulling in all of NIO just for signals. However, user requested NIO. I will add NIO._
- [ ] 1.3 Implement `GracefulShutdownManager` to coordinate task cancellation.

## 2. Gemini Provider Implementation

- [ ] 2.1 Implement `GeminiEmbeddingProvider` using Google Generative AI REST API.
- [ ] 2.2 Implement `GeminiLLMProvider` for search enhancements.
- [ ] 2.3 Register `gemini` in `EmbeddingProviderRegistry` and `LLMProviderFactory`.
- [ ] 2.4 Add `GEMINI_API_KEY` handling in `Config` and `EnvironmentConfigLoader`.

## 3. CLI Updates

- [ ] 3.1 Update `IndexCommand` to use `GracefulShutdownManager`.
- [ ] 3.2 Update `ServeCommand` to use `GracefulShutdownManager`.
- [ ] 3.3 Implement `InstallGeminiCommand` to generate `.gemini/mcp.json` (or appropriate config).
- [ ] 3.4 Register `install-gemini` subcommand in `SwiftIndexApp`.
- [ ] 3.5 Update `init` wizard to include Gemini options.
