# Search Features Guide

This guide covers SwiftIndex's search capabilities in detail, including query expansion, result synthesis, and follow-up suggestions.

## Hybrid Search

SwiftIndex uses a hybrid search approach combining:

1. **BM25 Full-Text Search**: Traditional keyword matching with TF-IDF scoring
2. **Semantic Vector Search**: Meaning-based similarity using embeddings
3. **Reciprocal Rank Fusion (RRF)**: Combines rankings for best of both approaches

### Search Weight Configuration

Control the balance between BM25 and semantic search:

```toml
[search]
semantic_weight = 0.7  # 0.0 = BM25 only, 1.0 = semantic only
rrf_k = 60             # RRF constant (higher = more uniform ranking)
```

Or via CLI:

```bash
swiftindex search --semantic-weight 0.5 "query"
```

## Query Expansion

Query expansion uses an LLM to generate related search terms, improving recall for conceptual searches.

### How It Works

Given a query like `"async networking"`, the expander generates:

**Synonyms** (equivalent terms):

- asynchronous network
- concurrent http
- async url session

**Related Concepts** (adjacent topics):

- URLSession
- async/await
- Combine
- network layer

**Variations** (alternative phrasings):

- async net
- network async
- async request

### Using Query Expansion

```bash
# CLI
swiftindex search --expand-query "error handling"

# The expanded query searches for all related terms
# Original: "error handling"
# Expanded: "error handling" OR "exception handling" OR "try catch" OR ...
```

### When to Use

Query expansion is most useful for:

- **Conceptual searches**: "how does authentication work"
- **Exploratory searches**: "networking code"
- **Unfamiliar codebases**: when you don't know exact terminology

It's less useful for:

- **Exact matches**: searching for a specific function name
- **Known identifiers**: `"calculateTotalPrice"`

### Recall vs Precision Trade-off

Query expansion improves **recall** (finding more relevant results) but may reduce **precision** (result relevance). The expanded terms are combined with OR logic, so more results match.

## Result Synthesis

Result synthesis uses an LLM to analyze search results and generate a coherent summary.

### Synthesis Output

```
SUMMARY: The authentication system uses JWT tokens managed by AuthService.
Login requests are validated in LoginController and tokens are refreshed
automatically by TokenManager.

INSIGHTS:
- JWT tokens with 1-hour expiry
- Automatic refresh 5 minutes before expiry
- OAuth2 support for social login

REFERENCES:
- AuthService.swift:42 - Main auth logic
- TokenManager.swift:87 - Token refresh
- LoginController.swift:15 - Request validation

CONFIDENCE: 85%
```

### Components

| Component      | Description                                |
| -------------- | ------------------------------------------ |
| **Summary**    | 2-4 sentence answer to your query          |
| **Insights**   | Key patterns and implementation details    |
| **References** | Specific file:line locations               |
| **Confidence** | How well results answer the query (0-100%) |

### Using Synthesis

```bash
# CLI
swiftindex search --synthesize "authentication flow"

# Combined with expansion
swiftindex search --expand-query --synthesize "user login"
```

### When to Use

Synthesis is most useful for:

- **Understanding questions**: "how does X work"
- **Multiple related results**: when you need to correlate information
- **Documentation generation**: summarizing code behavior

It's less useful for:

- **Finding specific code**: when you just need file locations
- **Quick lookups**: when raw results are sufficient

## Follow-up Suggestions

Follow-up suggestions are generated based on your query and results, helping you explore related topics.

### Suggestion Categories

| Category               | Description             | Example                      |
| ---------------------- | ----------------------- | ---------------------------- |
| `deeper_understanding` | Why something works     | "why use JWT over sessions"  |
| `related_code`         | Similar implementations | "other auth providers"       |
| `how_to`               | Usage examples          | "how to refresh tokens"      |
| `testing`              | Test files and patterns | "auth unit tests"            |
| `configuration`        | Setup and config        | "auth configuration options" |
| `exploration`          | General exploration     | "security middleware"        |

### Example Output

For query `"authentication flow"`:

```
Follow-up suggestions:
1. "token refresh mechanism" - Understand automatic token refresh
2. "OAuth2 provider setup" - Social login configuration
3. "auth middleware tests" - Test coverage for auth
4. "session vs JWT comparison" - Architecture decision context
```

## Output Formats

### Human Format (default)

Readable terminal output with relevance percentages:

```
[98%] Sources/Auth/AuthService.swift:42-87
      func authenticate(credentials: Credentials) async throws -> Token
      Handles user authentication with JWT token generation...

[92%] Sources/Auth/TokenManager.swift:15-45
      actor TokenManager
      Manages token lifecycle including refresh...
```

### JSON Format

Verbose JSON with all metadata:

```bash
swiftindex search --format json "query"
```

```json
{
  "results": [{
    "path": "Sources/Auth/AuthService.swift",
    "startLine": 42,
    "endLine": 87,
    "content": "func authenticate...",
    "docComment": "Handles user authentication...",
    "signature": "func authenticate(credentials: Credentials) async throws -> Token",
    "breadcrumb": "SwiftIndexCore > Auth > AuthService",
    "score": 0.98,
    "kind": "function"
  }]
}
```

### TOON Format

Token-optimized format for AI assistants (40-60% smaller than JSON):

```bash
swiftindex search --format toon "query"
```

```
%results
@Sources/Auth/AuthService.swift#42-87
$func authenticate(credentials: Credentials) async throws -> Token
~Handles user authentication with JWT token generation
^SwiftIndexCore > Auth > AuthService
!0.98
```

## Documentation Search

Search standalone documentation using the `search-docs` command or MCP tool:

```bash
# CLI
swiftindex search-docs "installation guide"

# MCP tool
{
  "tool": "swiftindex_search_docs",
  "arguments": {
    "query": "installation guide",
    "limit": 5
  }
}
```

Documentation search uses BM25 full-text search on:

- Markdown files (README.md, docs/*.md)
- File header comments
- Standalone documentation blocks

## Search Filters

### Extension Filter

Limit search to specific file types:

```bash
swiftindex search --extensions swift,ts "async function"
```

### Path Filter

Limit search to specific paths (glob syntax):

```bash
swiftindex search --path-filter "Sources/Auth/**" "token"
```

### Combined Filters

```bash
swiftindex search \
  --extensions swift \
  --path-filter "Sources/**" \
  --semantic-weight 0.8 \
  --limit 10 \
  "authentication"
```

## Performance Tips

1. **Use filters** to narrow search scope
2. **Adjust semantic weight** based on query type:
   - High (0.8-1.0): conceptual questions
   - Medium (0.5-0.7): mixed queries
   - Low (0.0-0.3): exact keyword searches
3. **Skip synthesis** for quick lookups (`--no-synthesize`)
4. **Skip expansion** for known terms (`--no-expand`)
5. **Use TOON format** when results will be processed by AI

## Troubleshooting

### No Results Found

1. Check index is up to date: `swiftindex index .`
2. Try broader query terms
3. Enable query expansion: `--expand-query`
4. Lower semantic weight for exact matches

### Results Not Relevant

1. Use filters to narrow scope
2. Increase semantic weight for conceptual searches
3. Try more specific query terms
4. Check indexed file extensions in config

### Slow Search

1. Reduce result limit: `--limit 5`
2. Disable LLM features if not needed
3. Use path filters to limit search scope
4. Consider re-indexing with smaller chunk size
