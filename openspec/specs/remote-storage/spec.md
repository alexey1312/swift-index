# remote-storage Specification

## Purpose

Remote Storage enables teams to share SwiftIndex indexes through cloud storage providers (AWS S3, Google Cloud Storage). One developer (or CI/CD) indexes the repository and uploads the index; team members download and use the shared index immediately.

## Requirements

### Requirement: Remote Storage Provider Protocol

The system SHALL define a protocol for remote storage operations.

```swift
protocol RemoteStorageProvider: Sendable {
    func upload(localPath: URL, remotePath: String) async throws
    func download(remotePath: String, localPath: URL) async throws
    func exists(remotePath: String) async throws -> Bool
    func getManifest() async throws -> RemoteManifest?
    func putManifest(_ manifest: RemoteManifest) async throws
}
```

#### Scenario: Upload file to remote

- **WHEN** calling `upload(localPath:remotePath:)`
- **THEN** file is uploaded to bucket at specified path
- **AND** overwrites existing file if present

#### Scenario: Download file from remote

- **WHEN** calling `download(remotePath:localPath:)`
- **AND** remote file exists
- **THEN** file is downloaded to local path
- **AND** creates parent directories if needed

#### Scenario: Download non-existent file

- **WHEN** calling `download(remotePath:localPath:)`
- **AND** remote file does NOT exist
- **THEN** throws `RemoteStorageError.fileNotFound`

#### Scenario: Check file existence

- **WHEN** calling `exists(remotePath:)`
- **THEN** returns `true` if file exists, `false` otherwise
- **AND** does NOT download the file

---

### Requirement: AWS S3 Storage Provider

The system SHALL provide `S3StorageProvider` implementation using aws-sdk-swift.

Configuration:

- `bucket` — S3 bucket name (required)
- `region` — AWS region (required)
- `prefix` — optional path prefix within bucket

Authentication priority:

1. Environment: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`
2. Profile: `~/.aws/credentials`
3. IAM Role: automatic on AWS infrastructure

#### Scenario: Upload to S3

- **WHEN** calling `upload` with S3 provider
- **THEN** file is uploaded using multipart upload for large files
- **AND** uses configured bucket and region

#### Scenario: S3 authentication via environment

- **WHEN** `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` are set
- **THEN** provider authenticates using environment variables

#### Scenario: S3 authentication via profile

- **WHEN** environment variables are NOT set
- **AND** `~/.aws/credentials` contains valid profile
- **THEN** provider authenticates using profile credentials

#### Scenario: S3 bucket not found

- **WHEN** configured bucket does not exist
- **THEN** throws `RemoteStorageError.bucketNotFound(bucket)`
- **AND** error message includes bucket name

---

### Requirement: Google Cloud Storage Provider

The system SHALL provide `GCSStorageProvider` implementation using google-cloud-swift.

Configuration:

- `bucket` — GCS bucket name (required)
- `project` — GCP project ID (optional, for bucket creation)
- `prefix` — optional path prefix within bucket

Authentication priority:

1. Environment: `GOOGLE_APPLICATION_CREDENTIALS` (path to JSON key)
2. Default credentials: `gcloud auth application-default login`
3. Service account: attached to GCP compute resources

#### Scenario: Upload to GCS

- **WHEN** calling `upload` with GCS provider
- **THEN** file is uploaded using resumable upload for large files
- **AND** uses configured bucket

#### Scenario: GCS authentication via service account

- **WHEN** `GOOGLE_APPLICATION_CREDENTIALS` points to valid JSON key
- **THEN** provider authenticates using service account

#### Scenario: GCS default credentials

- **WHEN** `GOOGLE_APPLICATION_CREDENTIALS` is NOT set
- **AND** user has run `gcloud auth application-default login`
- **THEN** provider authenticates using default credentials

---

### Requirement: Remote Manifest

The system SHALL use a manifest file to track index version and file checksums.

```swift
struct RemoteManifest: Codable, Sendable {
    let version: Int
    let gitCommit: String?
    let createdAt: Date
    let files: [RemoteFile]

    struct RemoteFile: Codable, Sendable {
        let name: String
        let size: Int64
        let compressedSize: Int64
        let checksum: String  // SHA-256
    }
}
```

#### Scenario: Create manifest on push

- **WHEN** running `swiftindex push`
- **THEN** manifest is created with:
  - `version` incremented from previous (or 1 if first)
  - `gitCommit` from current HEAD (if in git repo)
  - `createdAt` as current timestamp
  - `files` array with checksums for each uploaded file

#### Scenario: Manifest stored as JSON

- **WHEN** manifest is uploaded
- **THEN** stored as `manifest.json` in bucket root (or prefix)
- **AND** uses pretty-printed JSON for readability

#### Scenario: Read manifest on pull

- **WHEN** running `swiftindex pull`
- **THEN** manifest is fetched first
- **AND** used for delta sync comparison

---

### Requirement: Delta Sync

The system SHALL download only files that have changed since last sync.

Delta sync algorithm:

1. Fetch remote manifest
2. Load local cached manifest (if exists)
3. Compare checksums for each file
4. Download only files with different checksums
5. Update local cached manifest

#### Scenario: First pull downloads all

- **WHEN** running `swiftindex pull` for first time
- **AND** no local cache exists
- **THEN** downloads all files from remote
- **AND** stores manifest locally

#### Scenario: Delta sync skips unchanged

- **WHEN** running `swiftindex pull`
- **AND** local cache has matching checksums
- **THEN** skips unchanged files
- **AND** reports "X files skipped (unchanged)"

#### Scenario: Delta sync downloads changed

- **WHEN** running `swiftindex pull`
- **AND** remote `chunks.db.zst` has different checksum
- **THEN** downloads only `chunks.db.zst`
- **AND** skips `vectors.usearch.zst` if unchanged

#### Scenario: Checksum mismatch after download

- **WHEN** downloaded file checksum doesn't match manifest
- **THEN** throws `RemoteStorageError.checksumMismatch`
- **AND** error includes expected and actual checksums

---

### Requirement: Compression

The system SHALL compress index files using zstd before upload.

Compressed files:

- `chunks.db` → `chunks.db.zst`
- `vectors.usearch` → `vectors.usearch.zst`

Not compressed (small files):

- `manifest.json`
- `vectors.mapping.json`

#### Scenario: Compress on push

- **WHEN** running `swiftindex push`
- **THEN** `chunks.db` is compressed with zstd
- **AND** compression level is 3 (default, good balance)
- **AND** compressed file stored with `.zst` extension

#### Scenario: Decompress on pull

- **WHEN** running `swiftindex pull`
- **AND** downloading compressed file
- **THEN** file is decompressed to local cache
- **AND** stored without `.zst` extension

#### Scenario: Compression ratio reported

- **WHEN** push completes
- **THEN** shows compression ratio: "chunks.db: 18MB → 8MB (44%)"

---

### Requirement: Local Cache Management

The system SHALL store downloaded indexes in a local cache directory.

Cache location: `~/.cache/swiftindex/shared/{repo-hash}/`

Cache structure:

```
{repo-hash}/
├── manifest.json      # Copy of remote manifest
├── chunks.db          # Decompressed SQLite
├── vectors.usearch    # Decompressed HNSW
└── vectors.mapping.json
```

#### Scenario: Cache directory creation

- **WHEN** pulling index
- **AND** cache directory doesn't exist
- **THEN** creates directory with appropriate permissions

#### Scenario: Cache isolation by repository

- **WHEN** pulling indexes for different repositories
- **THEN** each repository has separate cache directory
- **AND** directories identified by hash of repository path

#### Scenario: Cache is read-only for search

- **WHEN** searching with remote index
- **THEN** cached files are opened in read-only mode
- **AND** no modifications to cache during search

---

### Requirement: CLI Push Command

The system SHALL provide `swiftindex push` command to upload index.

#### Scenario: Push local index

- **WHEN** running `swiftindex push`
- **AND** local index exists at `.swiftindex/`
- **THEN** compresses and uploads index files
- **AND** uploads manifest with checksums
- **AND** displays upload progress

#### Scenario: Push without local index

- **WHEN** running `swiftindex push`
- **AND** no local index exists
- **THEN** displays error: "No local index found. Run 'swiftindex index' first."
- **AND** exits with error code

#### Scenario: Push without remote config

- **WHEN** running `swiftindex push`
- **AND** `[remote]` section not configured
- **THEN** displays error: "Remote storage not configured. Run 'swiftindex remote config' first."
- **AND** exits with error code

#### Scenario: Push success output

- **WHEN** push completes successfully
- **THEN** displays:
  - Files uploaded count
  - Total size (compressed)
  - Upload duration
  - Remote URL/bucket location

---

### Requirement: CLI Pull Command

The system SHALL provide `swiftindex pull` command to download index.

#### Scenario: Pull remote index

- **WHEN** running `swiftindex pull`
- **AND** remote index exists
- **THEN** performs delta sync
- **AND** stores in local cache
- **AND** displays download progress

#### Scenario: Pull with no remote index

- **WHEN** running `swiftindex pull`
- **AND** remote bucket is empty
- **THEN** displays: "No remote index found. Someone needs to run 'swiftindex push' first."

#### Scenario: Pull success output

- **WHEN** pull completes successfully
- **THEN** displays:
  - Files downloaded count
  - Files skipped (unchanged)
  - Total size downloaded
  - Download duration
  - Index version and timestamp

---

### Requirement: CLI Remote Config Command

The system SHALL provide `swiftindex remote config` command for interactive setup.

#### Scenario: Interactive config wizard

- **WHEN** running `swiftindex remote config`
- **THEN** prompts for:
  1. Provider selection (S3 / GCS)
  2. Bucket name
  3. Region (for S3) or Project (for GCS)
  4. Credentials validation
- **AND** writes `[remote]` section to `.swiftindex.toml`

#### Scenario: Config with existing settings

- **WHEN** running `swiftindex remote config`
- **AND** `[remote]` already configured
- **THEN** shows current settings
- **AND** asks to overwrite or keep

#### Scenario: Validate credentials during config

- **WHEN** configuring remote storage
- **THEN** validates credentials by listing bucket
- **AND** shows error if credentials invalid

---

### Requirement: CLI Remote Status Command

The system SHALL provide `swiftindex remote status` command.

#### Scenario: Show remote vs local status

- **WHEN** running `swiftindex remote status`
- **THEN** displays:
  - Remote index version and timestamp
  - Local cache version and timestamp
  - Whether local is up-to-date
  - Git commit (if available)

#### Scenario: Status when out of sync

- **WHEN** running `swiftindex remote status`
- **AND** remote version > local version
- **THEN** displays: "Remote index is newer. Run 'swiftindex pull' to update."

#### Scenario: Status with no local cache

- **WHEN** running `swiftindex remote status`
- **AND** no local cache exists
- **THEN** displays: "No local cache. Run 'swiftindex pull' to download."

---

### Requirement: Overlay Search

The system SHALL merge results from remote and local indexes during search.

Merge strategy:

1. Search remote index (if available in cache)
2. Search local index
3. Deduplicate by file path (local wins)
4. Apply RRF fusion for final ranking

#### Scenario: Search with overlay

- **WHEN** searching with remote index cached
- **AND** local index has changes
- **THEN** returns results from both
- **AND** local results override remote for same path

#### Scenario: Local wins on conflict

- **WHEN** remote has chunk for `Auth.swift:10-50`
- **AND** local has different chunk for `Auth.swift:10-50`
- **THEN** local chunk appears in results
- **AND** remote chunk is excluded

#### Scenario: Search without remote cache

- **WHEN** searching without remote index cached
- **THEN** searches only local index
- **AND** operates normally without errors

#### Scenario: Search performance with overlay

- **WHEN** searching with both remote and local indexes
- **THEN** search completes in < 200ms
- **AND** RRF fusion adds < 10ms overhead

---

### Requirement: Remote Configuration Schema

The system SHALL support `[remote]` section in `.swiftindex.toml`.

```toml
[remote]
enabled = true
provider = "s3"                    # s3 | gcs
bucket = "swiftindex-team-index"
region = "us-east-1"               # AWS only
# project = "my-gcp-project"       # GCS only
prefix = ""                        # Optional path prefix

[remote.sync]
compression = "zstd"               # zstd | none
auto_pull = false                  # Pull before search if outdated
```

#### Scenario: Load remote config

- **WHEN** loading configuration
- **AND** `[remote]` section exists
- **THEN** remote storage is available for push/pull

#### Scenario: Remote disabled by default

- **WHEN** `[remote]` section missing
- **OR** `enabled = false`
- **THEN** push/pull commands show config instructions

#### Scenario: Validate remote config

- **WHEN** loading `[remote]` config
- **AND** `provider` is not "s3" or "gcs"
- **THEN** throws configuration error

---

### Requirement: Error Handling

The system SHALL provide clear error messages for remote storage failures.

Error types:

- `RemoteStorageError.authenticationFailed`
- `RemoteStorageError.bucketNotFound(String)`
- `RemoteStorageError.fileNotFound(String)`
- `RemoteStorageError.checksumMismatch(expected:actual:)`
- `RemoteStorageError.networkError(Error)`
- `RemoteStorageError.permissionDenied(String)`

#### Scenario: Authentication failure

- **WHEN** credentials are invalid
- **THEN** error message includes:
  - "Authentication failed"
  - Provider-specific fix instructions
  - Link to credentials documentation

#### Scenario: Network timeout with retry

- **WHEN** network request times out
- **THEN** retries up to 3 times
- **AND** uses exponential backoff (1s, 2s, 4s)
- **AND** shows retry progress

#### Scenario: Final network failure

- **WHEN** all retries exhausted
- **THEN** shows clear error with last failure reason
- **AND** suggests checking network connection
