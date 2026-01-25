## ADDED Requirements

### Requirement: Type Declaration Chunks

The system SHALL create separate chunks for type declarations (class, struct, actor, enum, extension) with full conformance information.

Type declaration chunk properties:

- `isTypeDeclaration` — boolean flag set to true
- `content` — full declaration line with conformances
- `signature` — same as content for type declarations
- `conformances` — list of conformed protocols/inherited types
- `docComment` — documentation comment if present

#### Scenario: Create actor declaration chunk

- **WHEN** parsing `public actor GRDBChunkStore: ChunkStore, InfoSnippetStore { ... }`
- **THEN** creates chunk with `isTypeDeclaration = true`
- **AND** chunk.content is "public actor GRDBChunkStore: ChunkStore, InfoSnippetStore"
- **AND** chunk.conformances is ["ChunkStore", "InfoSnippetStore"]
- **AND** chunk.kind is `.actor`

#### Scenario: Create class declaration chunk

- **WHEN** parsing `class AuthManager: NSObject, AuthProtocol { ... }`
- **THEN** creates chunk with `isTypeDeclaration = true`
- **AND** chunk.conformances is ["NSObject", "AuthProtocol"]

#### Scenario: Create extension declaration chunk

- **WHEN** parsing `extension User: Sendable { ... }`
- **THEN** creates chunk with `isTypeDeclaration = true`
- **AND** chunk.conformances is ["Sendable"]
- **AND** chunk.kind is `.extension`

#### Scenario: Type declaration includes doc comment

- **WHEN** parsing type with `/// SQLite-based storage` doc comment
- **THEN** type declaration chunk includes docComment
- **AND** docComment is searchable

#### Scenario: Type declaration separate from methods

- **WHEN** parsing class with 10 methods
- **THEN** creates 1 type declaration chunk
- **AND** creates 10 method chunks
- **AND** type declaration chunk is indexed first
