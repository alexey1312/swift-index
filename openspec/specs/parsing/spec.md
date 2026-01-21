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

The system SHALL use tree-sitter to parse non-Swift files in the project.

Supported languages:

- Objective-C (`.m`, `.mm`, `.h`)
- C/C++ (`.c`, `.cpp`, `.cc`, `.cxx`, `.h`, `.hpp`)
- JSON (`.json`)
- YAML (`.yaml`, `.yml`)
- Markdown (`.md`, `.markdown`)

#### Scenario: Parse Objective-C interface

- **WHEN** file is `MyClass.h` with `@interface MyClass : NSObject`
- **THEN** parser uses tree-sitter-objc grammar
- **AND** creates chunk for interface declaration

#### Scenario: Parse Objective-C implementation

- **WHEN** file is `MyClass.m` with method implementations
- **THEN** parser creates chunks for each method
- **AND** extracts method signatures

#### Scenario: Parse C function

- **WHEN** file is `helpers.c` with `int calculateSum(int a, int b)`
- **THEN** parser creates chunk with function body
- **AND** extracts function name

#### Scenario: Parse JSON object

- **WHEN** file is `package.json`
- **THEN** parser extracts top-level keys
- **AND** creates navigable structure

#### Scenario: Parse YAML config

- **WHEN** file is `.swiftlint.yml`
- **THEN** parser extracts configuration keys
- **AND** preserves hierarchy

#### Scenario: Parse Markdown documentation

- **WHEN** file is `README.md` with sections
- **THEN** parser creates chunks per section
- **AND** extracts code blocks separately

---

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

The system SHALL extract metadata from each chunk.

Extracted metadata:

- `path` — file path relative to project root
- `startLine` — first line number (1-indexed)
- `endLine` — last line number (1-indexed)
- `kind` — chunk type (function, class, struct, etc.)
- `symbols` — declared symbol names
- `references` — referenced symbol names
- `imports` — import statements in scope

#### Scenario: Extract function metadata

- **WHEN** parsing function `func login(credentials: Credentials)`
- **THEN** chunk.symbols contains "login"
- **AND** chunk.references contains "Credentials"

#### Scenario: Extract class metadata

- **WHEN** parsing `class AuthManager: NSObject, AuthProtocol`
- **THEN** chunk.symbols contains "AuthManager"
- **AND** chunk.references contains ["NSObject", "AuthProtocol"]

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
