# parsing Spec Delta

## MODIFIED Requirements

### Requirement: Chunk Metadata Extraction

The system SHALL extract rich metadata from each chunk.

Extracted metadata:

- `path` — file path relative to project root
- `startLine` — first line number (1-indexed)
- `endLine` — last line number (1-indexed)
- `kind` — chunk type (function, class, struct, etc.)
- `symbols` — declared symbol names
- `references` — referenced symbol names
- `imports` — import statements in scope
- `docComment` — extracted documentation comment (`///` or `/** */`)
- `signature` — full declaration signature
- `breadcrumb` — hierarchy path built from type stack
- `tokenCount` — approximate token count (content.count / 4)
- `language` — programming language based on file extension

#### Scenario: Extract function metadata

- **WHEN** parsing function `func login(credentials: Credentials)`
- **THEN** chunk.symbols contains "login"
- **AND** chunk.references contains "Credentials"

#### Scenario: Extract function with doc comment

- **WHEN** parsing function with `/// Authenticates the user with credentials`
- **THEN** chunk.docComment contains "Authenticates the user with credentials"
- **AND** chunk.signature contains "func authenticate(user: String) -> Bool"

#### Scenario: Extract nested method breadcrumb

- **WHEN** parsing method inside `class AuthManager` inside `extension Auth`
- **THEN** chunk.breadcrumb is "Auth (extension) > AuthManager > methodName"

#### Scenario: Calculate token count

- **WHEN** parsing chunk with 400-character content
- **THEN** chunk.tokenCount is approximately 100

#### Scenario: Detect Swift language

- **WHEN** parsing file with `.swift` extension
- **THEN** chunk.language is "swift"

#### Scenario: Extract class metadata

- **WHEN** parsing `class AuthManager: NSObject, AuthProtocol`
- **THEN** chunk.symbols contains "AuthManager"
- **AND** chunk.references contains ["NSObject", "AuthProtocol"]
- **AND** chunk.signature contains full class declaration line

---

### Requirement: tree-sitter Parsing for Other Languages

The system SHALL use tree-sitter to parse non-Swift files with metadata extraction.

Supported languages with metadata:

- Objective-C (`.m`, `.mm`, `.h`) — extracts doc comments, signatures
- C/C++ (`.c`, `.cpp`, `.h`) — extracts doc comments, signatures
- JSON (`.json`) — language detection
- YAML (`.yaml`, `.yml`) — language detection
- Markdown (`.md`) — extracts breadcrumb from header hierarchy

#### Scenario: Parse Objective-C with doc comment

- **WHEN** parsing method with `/** Performs login */` comment
- **THEN** chunk.docComment contains "Performs login"
- **AND** chunk.language is "objective-c"

#### Scenario: Parse C function with signature

- **WHEN** parsing `int calculateSum(int a, int b) { ... }`
- **THEN** chunk.signature contains "int calculateSum(int a, int b)"
- **AND** chunk.language is "c"

#### Scenario: Parse Markdown with breadcrumb

- **WHEN** parsing section under `# Guide` > `## Authentication` > `### Login`
- **THEN** chunk.breadcrumb is "Guide > Authentication > Login"
- **AND** chunk.language is "markdown"

#### Scenario: Language detection from extension

- **WHEN** parsing file `config.json`
- **THEN** chunk.language is "json"
