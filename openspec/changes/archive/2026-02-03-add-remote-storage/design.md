# Design: Remote Storage Architecture

## Overview

Remote Storage enables teams to share indexes through cloud storage. The architecture is based on a simple model: upload index files to a bucket and download with delta sync.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Developer A (or CI):                                           │
│  swiftindex index . && swiftindex push                          │
└─────────────────────────────────────────────────────────────────┘
                                ↓
                    ┌───────────────────────────────────────────┐
                    │         S3/GCS Bucket                     │
                    │  swiftindex-shared-{org}/                 │
                    │  ├── manifest.json        (version, hashes)│
                    │  ├── chunks.db.zst        (SQLite)        │
                    │  ├── vectors.usearch.zst  (HNSW)          │
                    │  └── vectors.mapping.json                 │
                    └───────────────────────────────────────────┘
                                ↓
┌─────────────────────────────────────────────────────────────────┐
│  Developers B, C, D...:                                         │
│  swiftindex pull → ~/.cache/swiftindex/shared/{repo-hash}/      │
│                    ├── chunks.db      (read-only)               │
│                    └── vectors.usearch (read-only)              │
│                              +                                   │
│                    .swiftindex/       (local overlay)           │
│                    ├── chunks.db      (local changes)           │
│                    └── vectors.usearch (local changes)          │
│                              ↓                                   │
│                    HybridSearchEngine (merge remote + local)    │
└─────────────────────────────────────────────────────────────────┘
```

## Components

### 1. RemoteStorageProvider Protocol

```swift
protocol RemoteStorageProvider: Sendable {
    /// Upload local file to remote storage
    func upload(localPath: URL, remotePath: String) async throws

    /// Download remote file to local path
    func download(remotePath: String, localPath: URL) async throws

    /// Check if remote file exists
    func exists(remotePath: String) async throws -> Bool

    /// Get manifest with file checksums
    func getManifest() async throws -> RemoteManifest?

    /// Upload manifest
    func putManifest(_ manifest: RemoteManifest) async throws
}
```

**Implementations:**

- `S3StorageProvider` — AWS S3
- `GCSStorageProvider` — Google Cloud Storage

### 2. RemoteManifest

```swift
struct RemoteManifest: Codable, Sendable {
    let version: Int                    // Incremental version number
    let gitCommit: String?              // Optional: SHA of indexed commit
    let createdAt: Date
    let files: [RemoteFile]

    struct RemoteFile: Codable, Sendable {
        let name: String                // "chunks.db.zst"
        let size: Int64                 // Uncompressed size
        let compressedSize: Int64       // Compressed size
        let checksum: String            // SHA-256
    }
}
```

### 3. DeltaSyncManager

```swift
actor DeltaSyncManager {
    /// Sync remote index to local cache
    func sync(
        provider: RemoteStorageProvider,
        localCache: URL
    ) async throws -> SyncResult

    /// Compare local vs remote and determine what to download
    func computeDelta(
        remote: RemoteManifest,
        localCache: URL
    ) -> [RemoteFile]
}

struct SyncResult {
    let filesDownloaded: Int
    let bytesDownloaded: Int64
    let skippedUnchanged: Int
    let duration: TimeInterval
}
```

### 4. Overlay Index Architecture

```swift
actor OverlayIndexManager {
    let remoteIndex: IndexManager?      // Read-only, from cache
    let localIndex: IndexManager        // Read-write, local changes

    /// Search both indexes and merge results
    func search(
        query: String,
        options: SearchOptions
    ) async throws -> [SearchResult]
}
```

**Merge Strategy:**

1. Search remote index
2. Search local index
3. Deduplicate by `path` — local wins on conflict
4. RRF fusion for final ranking

## Data Flow

### Push Flow

```
1. swiftindex push
2. Validate local index exists
3. Compress files with zstd
4. Calculate checksums
5. Upload compressed files to bucket
6. Upload manifest.json
7. Display success with upload stats
```

### Pull Flow

```
1. swiftindex pull
2. Fetch remote manifest
3. Compare with local cache manifest
4. Download only changed files (delta sync)
5. Decompress to cache directory
6. Update local manifest cache
7. Display success with sync stats
```

### Search Flow (with overlay)

```
1. swiftindex search "query"
2. Check for remote index in cache
3. If exists: load as read-only IndexManager
4. Search remote index
5. Search local index
6. Merge results (local wins for same path)
7. Apply RRF fusion
8. Return combined results
```

## Configuration

### TOML Schema

```toml
[remote]
enabled = true
provider = "s3"                    # s3 | gcs
bucket = "swiftindex-team-index"
region = "us-east-1"               # AWS only
# project = "my-gcp-project"       # GCS only
prefix = ""                        # Optional path prefix in bucket

[remote.sync]
compression = "zstd"               # zstd | none
auto_pull = false                  # Pull before search if outdated
```

### Authentication

**AWS S3:**

- Environment: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`
- Profile: `~/.aws/credentials` with `[profile]`
- IAM Role: automatic when running on AWS infrastructure

**Google Cloud Storage:**

- Environment: `GOOGLE_APPLICATION_CREDENTIALS` (path to JSON key)
- Default credentials: `gcloud auth application-default login`
- Service account: attached to GCP compute resources

## File Structure

### Remote Bucket

```
swiftindex-team-index/
├── manifest.json           # Version, checksums
├── chunks.db.zst          # Compressed SQLite
├── vectors.usearch.zst    # Compressed HNSW index
└── vectors.mapping.json   # Vector ID mapping (small, not compressed)
```

### Local Cache

```
~/.cache/swiftindex/shared/
└── {repo-hash}/
    ├── manifest.json      # Copy of remote manifest
    ├── chunks.db          # Decompressed
    ├── vectors.usearch    # Decompressed
    └── vectors.mapping.json
```

## Error Handling

| Error             | Handling                                  |
| ----------------- | ----------------------------------------- |
| Network timeout   | Retry 3x with exponential backoff         |
| Auth failure      | Clear error message with fix instructions |
| Checksum mismatch | Re-download file                          |
| Bucket not found  | Clear error, suggest checking config      |
| Permission denied | Check IAM/credentials error               |

## Trade-offs

### Compression

**zstd chosen because:**

- ~50% compression ratio for SQLite and binary data
- Very fast decompression (>1GB/s)
- Streaming support for large files
- Widely supported

**Alternative:** gzip — slower but more portable

### Delta Sync vs Full Sync

**Delta sync chosen because:**

- Typical index 500MB-2GB
- When 10% of code changes, need to download only ~50-200MB
- Checksum comparison cheaper than rsync-style diff

**Trade-off:** Requires manifest round-trip before download

### Overlay vs Replace

**Overlay chosen because:**

- Local changes (feature branch) visible immediately
- No need to wait for push to main and re-pull
- Predictable behavior: local always wins

**Trade-off:** Slightly more complex search path
