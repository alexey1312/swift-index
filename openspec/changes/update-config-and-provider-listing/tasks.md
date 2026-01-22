## 1. Implementation

- [ ] 1.1 Wire `CLIUtils.loadConfig` to load TOML config via `TOMLConfigLoader` for explicit `--config`, project `.swiftindex.toml`, and global config, then merge with environment variables and defaults per priority.
- [ ] 1.2 Update global config path handling to match spec (if spec change is approved).
- [ ] 1.3 Implement an embedding provider registry that returns all providers with `isAvailable()` and metadata for the providers command.
- [ ] 1.4 Replace placeholder provider list in `ProvidersCommand` with registry output.
- [ ] 1.5 Update `bin/mise` TODOs: refactor the messy section and add optional signature verification (minisign/gpg) for downloads.
- [ ] 1.6 Add or update tests for config merge behavior and providers listing output.
