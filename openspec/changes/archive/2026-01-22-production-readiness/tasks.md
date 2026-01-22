# Tasks: Production Readiness

## Summary

| Phase                 | Tasks  | Status              |
| --------------------- | ------ | ------------------- |
| 1. Critical Fixes     | 5      | ✅ Complete         |
| 2. CLI Implementation | 3      | ✅ Complete         |
| 3. Documentation      | 2      | ✅ Complete         |
| 4. Verification       | 3      | ✅ Complete         |
| **Total**             | **13** | **✅ All Complete** |

---

## Phase 1: Critical Build Fixes

### 1.1 Fix swift-toml dependency

- [x] Update Package.swift dependency declaration
- [x] Change from branch reference to version tag
- **File**: `Package.swift:42`
- **Commit**: Part of production-readiness changes

### 1.2 Fix MCPContext Config loading

- [x] Replace `Config.load()` with `TOMLConfigLoader.loadLayered()`
- [x] Update config caching logic
- **File**: `Sources/SwiftIndexMCP/MCPContext.swift:39-43`

### 1.3 Fix WatchCodebaseTool Sendable violation

- [x] Make `stopWatching` function async
- [x] Await operations directly instead of spawning Tasks
- [x] Update all call sites
- **File**: `Sources/SwiftIndexMCP/Tools/WatchCodebaseTool.swift:283-307`

### 1.4 Verify build passes

- [x] Run `./bin/mise run build`
- [x] Confirm no compilation errors
- **Result**: Build succeeded

### 1.5 Verify tests pass

- [x] Run `./bin/mise run test`
- [x] Confirm no test failures
- **Result**: 0 failures

---

## Phase 2: CLI Implementation

### 2.1 IndexCommand implementation

- [x] Load configuration via CLIUtils
- [x] Create EmbeddingProviderChain with fallback
- [x] Initialize IndexManager with stores
- [x] Collect files with exclude patterns
- [x] Parse with HybridParser
- [x] Generate embeddings and save
- [x] Display progress indicator
- [x] Create IndexingContext struct (lint fix)
- **File**: `Sources/swiftindex/Commands/IndexCommand.swift`

### 2.2 SearchCommand implementation

- [x] Load existing index
- [x] Create HybridSearchEngine
- [x] Execute search with semantic weight
- [x] Format results (plain/JSON)
- **File**: `Sources/swiftindex/Commands/SearchCommand.swift`

### 2.3 WatchCommand implementation

- [x] Create IncrementalIndexer
- [x] Setup FileWatcher with debounce
- [x] Handle Ctrl+C signal
- [x] Display periodic stats
- [x] Fix line length violation
- **File**: `Sources/swiftindex/Commands/WatchCommand.swift`

---

## Phase 3: Documentation Updates

### 3.1 CLAUDE.md updates

- [x] Add missing dependencies to table:
  - swift-transformers
  - swift-argument-parser
  - swift-log
  - swift-async-algorithms
  - swift-crypto
  - swift-embeddings
  - mlx-swift-lm
- [x] Update module structure with HubModelManager
- **File**: `CLAUDE.md`

### 3.2 README.md updates

- [x] Add System Requirements section
- [x] Add Homebrew installation
- [x] Add GitHub Releases installation
- [x] Add Verification section
- [x] Add Troubleshooting section
- [x] Add Uninstall section
- **File**: `README.md`

---

## Phase 4: Final Verification

### 4.1 Lint check

- [x] Run `./bin/mise run lint`
- [x] Fix line length violations
- [x] Fix function parameter count violation
- **Result**: 0 violations

### 4.2 Test verification

- [x] Run `./bin/mise run test`
- [x] Confirm all tests pass
- **Result**: 0 failures

### 4.3 Build verification

- [x] Run `./bin/mise run build:release`
- [x] Confirm release build succeeds
- **Result**: Build succeeded

---

## Files Modified

### Core Library

| File            | Changes                   |
| --------------- | ------------------------- |
| `Package.swift` | swift-toml dependency fix |

### MCP Server

| File                                                  | Changes                          |
| ----------------------------------------------------- | -------------------------------- |
| `Sources/SwiftIndexMCP/MCPContext.swift`              | Config loading fix               |
| `Sources/SwiftIndexMCP/Tools/WatchCodebaseTool.swift` | Sendable fix, async stopWatching |

### CLI Commands

| File                                              | Changes                                     |
| ------------------------------------------------- | ------------------------------------------- |
| `Sources/swiftindex/Commands/IndexCommand.swift`  | Full implementation, IndexingContext struct |
| `Sources/swiftindex/Commands/SearchCommand.swift` | Full implementation                         |
| `Sources/swiftindex/Commands/WatchCommand.swift`  | Full implementation, line length fix        |

### Documentation

| File        | Changes                                           |
| ----------- | ------------------------------------------------- |
| `CLAUDE.md` | Dependencies table, module structure              |
| `README.md` | Installation, troubleshooting, uninstall sections |

---

## Completion Metrics

- **Build Time**: ~45 seconds (release)
- **Test Duration**: ~12 seconds
- **Lint Violations Fixed**: 3
- **Files Modified**: 8
- **Lines Changed**: ~500

## Next Steps (Future Work)

1. [ ] E2E testing on real Swift projects
2. [ ] Performance benchmarking on large codebases
3. [ ] Integration testing with Claude Code
4. [ ] First GitHub release (v0.1.0)
