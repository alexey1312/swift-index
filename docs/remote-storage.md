# Remote Storage

Remote Storage lets teams share a SwiftIndex index through cloud storage. One
person (or CI) runs `swiftindex push`, and everyone else runs `swiftindex pull`
to reuse the same index with a local overlay.

## Requirements

- A configured `.swiftindex.toml`
- A supported provider:
  - AWS S3
  - Google Cloud Storage

## Quick Start

1. Configure remote storage:

```bash
swiftindex remote config
```

2. Upload the index:

```bash
swiftindex index
swiftindex push
```

3. Download the shared index:

```bash
swiftindex pull
```

## Configuration

Example TOML:

```toml
[remote]
enabled = true
provider = "s3"        # s3 | gcs
bucket = "swiftindex-team-index"
region = "us-east-1"   # S3 only
# project = "my-gcp-project"   # GCS only
prefix = ""            # Optional path prefix

[remote.sync]
compression = "zstd"   # zstd | none
auto_pull = false
```

## Credentials

**AWS S3:**

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- Optional profile in `~/.aws/credentials`

**GCS:**

- `GOOGLE_APPLICATION_CREDENTIALS` (path to JSON key)
- Or `gcloud auth application-default login`

## Commands

- `swiftindex push`: Compresses index files, uploads them, and writes the remote manifest.
- `swiftindex pull`: Downloads only changed files (delta sync) and updates the local cache.
- `swiftindex remote config`: Interactive setup for provider, bucket, and credentials.
- `swiftindex remote status`: Shows remote vs local cache version.

## CI/CD Example

Example GitHub Actions step:

```yaml
- name: Index and push
  run: |
    swiftindex init --provider mlx
    swiftindex index
    swiftindex push
```

For scheduled refreshes, run the same job nightly and let developers pull the
latest index when needed.
