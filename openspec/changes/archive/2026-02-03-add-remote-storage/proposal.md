# Proposal: Add Remote Storage

## Summary

Add the ability to store and sync indexes through cloud storage providers (AWS S3, Google Cloud Storage) for team collaboration.

## Motivation

**Problem:** In teams of 60+ developers, everyone spends time indexing the same monorepo. Indexing a large repository (500K-2M lines) takes significant time and resources.

**Solution:** One developer (or CI/CD) indexes the repository and uploads the index to cloud storage. Team members download the ready index and start working immediately.

## Use Cases

1. **Team Index Sharing** — one person indexes, everyone uses
2. **CI/CD Integration** — automatic index updates on merge to main
3. **Local Overlay** — local changes are layered on top of remote index

## Scope

### In Scope

- New `Remote/` module with `RemoteStorageProvider` protocol
- Implementations for AWS S3 and Google Cloud Storage
- CLI commands: `push`, `pull`, `remote config`, `remote status`
- Configuration `[remote]` section in TOML
- Overlay search: merge remote + local results
- Delta sync by checksum for optimization

### Out of Scope

- Real-time synchronization between clients
- Client-side index encryption
- Multi-tenant access control
- Support for other providers (Azure, MinIO) — can be added later

## Dependencies

| Package            | Version | Purpose                             |
| ------------------ | ------- | ----------------------------------- |
| aws-sdk-swift      | 1.0.0+  | AWS S3 operations                   |
| google-cloud-swift | 1.0.0+  | GCS operations                      |
| swift-crypto       | 4.0.0   | SHA-256 checksums (already present) |

## Risks

| Risk                   | Mitigation                                             |
| ---------------------- | ------------------------------------------------------ |
| Large index size (2GB) | zstd compression (~50% reduction), delta sync          |
| Credentials security   | Environment variables, IAM roles, no plaintext storage |
| Network failures       | Retry with exponential backoff, resume support         |

## Success Criteria

1. `swiftindex push` successfully uploads index to S3/GCS
2. `swiftindex pull` downloads index and is ready for search in <2 minutes (for 1GB index)
3. Delta sync downloads only changed files
4. Overlay search returns results from remote + local
5. Credentials work via env vars and IAM roles
