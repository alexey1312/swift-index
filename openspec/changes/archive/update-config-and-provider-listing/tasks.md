## 1. Implementation

- [x] 1.1 Wire `CLIUtils.loadConfig` to load TOML config via `TOMLConfigLoader` for explicit `--config`, project `.swiftindex.toml`, and global config, then merge with environment variables and defaults per priority.
  - Already implemented in `CommandUtilities.swift`
- [x] 1.2 Update global config path handling to match spec (if spec change is approved).
  - Updated `TOMLConfigLoader.forGlobal()` to use `~/.config/swiftindex/config.toml`
- [x] 1.3 Implement an embedding provider registry that returns all providers with `isAvailable()` and metadata for the providers command.
  - Created `EmbeddingProviderRegistry.swift` with `ProviderInfo` struct and registry class
- [x] 1.4 Replace placeholder provider list in `ProvidersCommand` with registry output.
  - Updated `ProvidersCommand.swift` to use `EmbeddingProviderRegistry`
- [x] 1.5 Update `bin/mise` TODOs: refactor the messy section and add optional signature verification (minisign/gpg) for downloads.
  - Skipped: `bin/mise` is auto-generated via https://mise.jdx.dev/cli/generate/bootstrap.html
- [x] 1.6 Add or update tests for config merge behavior and providers listing output.
  - Added `EmbeddingProviderRegistryTests` and `ProviderInfoTests` in `EmbeddingProviderTests.swift`
  - Updated `forGlobalPath()` test in `TOMLConfigLoaderTests.swift`
