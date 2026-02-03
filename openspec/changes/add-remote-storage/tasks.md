# Tasks: Add Remote Storage

## Phase 1: Core Infrastructure

### 1.1 Add Dependencies

- [x] Add `aws-sdk-swift` to Package.swift
- [x] Add `google-cloud-kit` to Package.swift
- [x] Verify builds pass with new dependencies
- **Validation:** `swift build` succeeds

### 1.2 Create RemoteStorageProvider Protocol

- [x] Create `Sources/SwiftIndexCore/Remote/RemoteStorageProvider.swift`
- [x] Define protocol with upload/download/exists/manifest operations
- [x] Create `RemoteStorageError` enum
- **Validation:** Protocol compiles, tests can mock it

### 1.3 Implement RemoteManifest

- [x] Create `Sources/SwiftIndexCore/Remote/RemoteManifest.swift`
- [x] Implement Codable struct with version, files, checksums
- [x] Add JSON serialization tests
- **Validation:** Unit tests for encode/decode

### 1.4 Implement S3StorageProvider

- [x] Create `Sources/SwiftIndexCore/Remote/S3StorageProvider.swift`
- [x] Implement upload with multipart for large files
- [ ] Implement download with progress
- [x] Implement credential loading (env, profile, IAM)
- **Validation:** Integration test with LocalStack or real S3

### 1.5 Implement GCSStorageProvider

- [x] Create `Sources/SwiftIndexCore/Remote/GCSStorageProvider.swift`
- [ ] Implement upload with resumable upload
- [ ] Implement download with progress
- [x] Implement credential loading (JSON key, default, service account)
- **Validation:** Integration test with real GCS (optional)

### 1.6 Implement Compression

- [x] Add zstd compression/decompression utilities
- [x] Create `CompressionHelper` with compress/decompress methods
- [x] Handle streaming for large files
- **Validation:** Round-trip test: compress → decompress → compare

## Phase 2: Delta Sync

### 2.1 Implement DeltaSyncManager

- [x] Create `Sources/SwiftIndexCore/Remote/DeltaSyncManager.swift`
- [x] Implement checksum comparison logic
- [x] Implement selective download
- [x] Track and report sync statistics
- **Validation:** Unit tests for delta computation

### 2.2 Implement Local Cache Management

- [x] Create cache directory structure at `~/.cache/swiftindex/shared/`
- [x] Implement repo-hash based isolation
- [x] Store local manifest copy
- **Validation:** Multiple repos don't interfere

## Phase 3: CLI Commands

### 3.1 Implement `swiftindex push` Command

- [ ] Create `Sources/swiftindex/Commands/PushCommand.swift`
- [ ] Compress local index files
- [ ] Upload with progress display
- [ ] Create and upload manifest
- **Validation:** Manual test: push to S3, verify files in bucket

### 3.2 Implement `swiftindex pull` Command

- [ ] Create `Sources/swiftindex/Commands/PullCommand.swift`
- [ ] Fetch manifest and compute delta
- [ ] Download with progress display
- [ ] Decompress to cache
- **Validation:** Manual test: pull from S3, verify cache populated

### 3.3 Implement `swiftindex remote config` Command

- [ ] Create `Sources/swiftindex/Commands/RemoteConfigCommand.swift`
- [ ] Interactive wizard for provider/bucket/credentials
- [ ] Validate credentials during setup
- [ ] Write `[remote]` section to config
- **Validation:** Wizard completes, config file updated

### 3.4 Implement `swiftindex remote status` Command

- [ ] Create `Sources/swiftindex/Commands/RemoteStatusCommand.swift`
- [ ] Compare remote vs local versions
- [ ] Display sync status
- **Validation:** Shows correct status for various states

## Phase 4: Overlay Search

### 4.1 Modify IndexManager for Read-Only Mode

- [ ] Add `readOnly` flag to IndexManager
- [ ] Prevent writes when in read-only mode
- [ ] Load from cache directory
- **Validation:** Read-only index works for search

### 4.2 Implement OverlayIndexManager

- [ ] Create `Sources/SwiftIndexCore/Remote/OverlayIndexManager.swift`
- [ ] Load remote index from cache (if available)
- [ ] Merge search results with deduplication
- [ ] Local wins for same path
- **Validation:** Unit tests for merge logic

### 4.3 Integrate Overlay into HybridSearchEngine

- [ ] Modify HybridSearchEngine to accept optional remote index
- [ ] Implement RRF fusion across both indexes
- [ ] Maintain search performance < 200ms
- **Validation:** Integration test with both indexes

## Phase 5: Configuration

### 5.1 Add Remote Config Schema

- [ ] Update `TOMLConfig` with `RemoteConfig` struct
- [ ] Add `[remote]` and `[remote.sync]` sections
- [ ] Add validation for provider values
- [ ] Update `TOMLConfigValidator.allowedSections`
- **Validation:** Config loads without errors

### 5.2 Documentation

- [ ] Add `docs/remote-storage.md` with setup guide
- [ ] Update CLAUDE.md with new commands
- [ ] Add examples for CI/CD integration
- **Validation:** Docs are clear and complete

## Phase 6: Testing

### 6.1 Unit Tests

- [x] `RemoteManifestTests` — serialization
- [x] `DeltaSyncManagerTests` — checksum comparison
- [ ] `OverlayIndexManagerTests` — merge and deduplication
- **Validation:** All unit tests pass

### 6.2 Integration Tests

- [ ] `S3IntegrationTests` — with LocalStack mock
- [ ] `PushPullIntegrationTests` — full cycle
- [ ] `OverlaySearchIntegrationTests` — search with remote
- **Validation:** Integration tests pass

### 6.3 Manual Testing

- [ ] Test push/pull with real S3 bucket
- [ ] Test with 500MB+ index (realistic size)
- [ ] Test overlay search with local changes
- **Validation:** Works end-to-end

## Dependencies

```
1.1 ──┬── 1.2 ── 1.3 ── 1.4 ── 1.5
      │                   │
      └── 1.6 ────────────┘
                          │
            2.1 ── 2.2 ───┤
                          │
            3.1 ── 3.2 ── 3.3 ── 3.4
                          │
            4.1 ── 4.2 ── 4.3
                          │
            5.1 ── 5.2 ───┤
                          │
                   6.1 ── 6.2 ── 6.3
```

## Parallelizable Work

- **1.4 and 1.5** can be done in parallel (S3 and GCS providers)
- **3.1-3.4** can be done in parallel after Phase 2
- **4.1-4.3** can be done in parallel with Phase 3
- **6.1** can start after Phase 4, **6.2-6.3** after all phases
