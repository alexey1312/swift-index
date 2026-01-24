## MODIFIED Requirements

### Requirement: Incremental Indexing

The system SHALL support incremental indexing based on file changes.

Change detection:

- File hash (stable SHA-256 of content)
- Modification timestamp
- File existence
- File path for hash lookup (per-path tracking)

#### Scenario: New file detection

- **WHEN** new Swift file added to project
- **THEN** only new file is indexed
- **AND** existing chunks unchanged

#### Scenario: Modified file detection

- **WHEN** existing file content changes
- **THEN** old chunks for file are removed
- **AND** new chunks are created

#### Scenario: Deleted file detection

- **WHEN** indexed file is deleted
- **THEN** chunks for file are removed
- **AND** vectors are removed from index

#### Scenario: Unchanged file skipped

- **WHEN** file hash for a path matches stored hash for that same path
- **THEN** file is skipped
- **AND** no parsing or embedding performed

#### Scenario: Identical content across different paths

- **WHEN** two different paths contain identical content
- **THEN** each path is tracked independently
- **AND** skipping applies per path without collisions

---

### Requirement: Database Schema Migration

The system SHALL support incremental schema migrations for index evolution.

#### Scenario: v2 migration adds rich metadata columns

- **WHEN** opening index created with v1 schema
- **THEN** v2 migration runs automatically
- **AND** new columns are added with default values
- **AND** FTS5 index is recreated with doc_comment column
- **AND** existing data is preserved
