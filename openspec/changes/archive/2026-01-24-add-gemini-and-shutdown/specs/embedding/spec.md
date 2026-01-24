## ADDED Requirements

### Requirement: Google Gemini Provider

The system SHALL support generating embeddings using the Google Gemini API.

#### Scenario: Generate embeddings

- **WHEN** the active provider is Gemini
- **AND** a batch of text chunks is processed
- **THEN** it sends a request to the `batchEmbedContents` endpoint
- **AND** returns vectors of the appropriate dimension (768 for `text-embedding-004`)
