# parsing Specification

## Purpose

TBD - created by archiving change add-swiftindex-core. Update Purpose after archive.

## Requirements

### Requirement: SwiftSyntax Parsing for Swift Files

The system SHALL use SwiftSyntax to parse `.swift` files with 100% AST accuracy.

Supported Swift constructs:

- Function declarations (`func`)
- Class declarations (`class`)
- Struct declarations (`struct`)
- Enum declarations (`enum`)
- Protocol declarations (`protocol`)
- Extension declarations (`extension`)
- Actor declarations (`actor`)
- Macro declarations (`macro`)
- Property wrapper declarations
- Computed properties

#### Scenario: Parse function declaration

- **WHEN** Swift file contains `func authenticate(user: String) -> Bool`
- **THEN** parser creates chunk with kind `.function`
- **AND** chunk contains full function body
- **AND** symbols include "authenticate"

#### Scenario: Parse class with methods

- **WHEN** Swift file contains class with multiple methods
- **THEN** parser creates chunk for class declaration
- **AND** creates separate chunks for each method
- **AND** preserves parent-child relationship

#### Scenario: Parse actor declaration

- **WHEN** Swift file contains `actor DatabaseManager { ... }`
- **THEN** parser creates chunk with kind `.actor`
- **AND** extracts actor-specific semantics

#### Scenario: Parse macro declaration

- **WHEN** Swift file contains `@attached(member) macro Observable()`
- **THEN** parser creates chunk with kind `.macro`
- **AND** captures macro attributes

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

### Requirement: Hybrid Parser Routing

The system SHALL route files to appropriate parser based on file extension.

Routing rules:

- `.swift` → SwiftSyntax
- `.m`, `.mm`, `.h` (with ObjC content) → tree-sitter-objc
- `.c`, `.cpp`, `.cc`, `.cxx` → tree-sitter-c/cpp
- `.json` → tree-sitter-json
- `.yaml`, `.yml` → tree-sitter-yaml
- `.md`, `.markdown` → tree-sitter-markdown
- Unknown → Plain text chunking

#### Scenario: Route Swift file

- **WHEN** file has `.swift` extension
- **THEN** HybridParser delegates to SwiftSyntaxParser

#### Scenario: Route Objective-C file

- **WHEN** file has `.m` extension
- **THEN** HybridParser delegates to TreeSitterParser with ObjC grammar

#### Scenario: Route unknown extension

- **WHEN** file has `.xyz` extension
- **THEN** HybridParser uses plain text chunking
- **AND** no error is raised

---

### Requirement: AST-Aware Chunking

The system SHALL create chunks at semantic boundaries, not arbitrary line counts.

Chunk boundaries:

- Function/method boundaries
- Type declaration boundaries (class, struct, enum)
- Top-level statements
- Documentation comments attached to declarations

#### Scenario: Chunk respects function boundary

- **WHEN** function spans lines 10-50
- **THEN** chunk includes entire function
- **AND** does not split mid-function

#### Scenario: Large function handling

- **WHEN** function exceeds `chunking.max_size` (2500 tokens)
- **THEN** function is split at logical points (nested blocks)
- **AND** overlap preserves context

---

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

### Requirement: Context Overlap

The system SHALL preserve context between adjacent chunks.

Overlap strategy:

- Include parent declaration header in child chunks
- Include preceding documentation comments
- Configurable overlap percentage (`chunking.overlap`)

#### Scenario: Method includes class context

- **WHEN** method is inside `class AuthManager`
- **THEN** method chunk includes class header as context
- **AND** search can understand method belongs to AuthManager
