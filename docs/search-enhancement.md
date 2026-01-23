# Search Enhancement Guide

SwiftIndex supports optional LLM-powered search enhancements that improve search quality through query expansion, result synthesis, and follow-up suggestions.

## Overview

The search enhancement system uses a **dual-tier architecture**:

- **Utility Tier**: Fast operations with smaller/faster models
  - Query expansion (generating related search terms)
  - Follow-up query suggestions
  - Query classification

- **Synthesis Tier**: Deep analysis with larger/more capable models
  - Result summarization
  - Key insight extraction
  - Code reference correlation

## Configuration

Enable search enhancement in your `.swiftindex.toml`:

```toml
[search.enhancement]
enabled = true

# Utility tier: fast operations (query expansion, follow-ups)
[search.enhancement.utility]
provider = "claude-code-cli"
# model = "claude-haiku-4-5-20251001"  # optional model override
timeout = 30

# Synthesis tier: deep analysis (result summarization)
[search.enhancement.synthesis]
provider = "claude-code-cli"
# model = "claude-sonnet-4-20250514"  # optional model override
timeout = 120
```

## LLM Providers

SwiftIndex supports four LLM providers:

### Claude Code CLI (`claude-code-cli`)

Uses the `claude` CLI tool from Claude Code. Best quality for most use cases.

**Requirements:**

- Claude Code installed (`claude` command available)
- Active Claude Code session or API access

**Configuration:**

```toml
[search.enhancement.utility]
provider = "claude-code-cli"
model = "claude-haiku-4-5-20251001"  # optional, uses default if omitted
timeout = 30
```

**Supported Models:**

- `claude-haiku-4-5-20251001` - Fast, efficient (recommended for utility tier)
- `claude-sonnet-4-20250514` - Balanced (recommended for synthesis tier)
- `claude-opus-4-20250514` - Most capable

### Codex CLI (`codex-cli`)

Uses the `codex` CLI tool from OpenAI Codex.

**Requirements:**

- Codex CLI installed (`codex` command available)
- OpenAI API access

**Configuration:**

```toml
[search.enhancement.utility]
provider = "codex-cli"
timeout = 30
```

### Ollama (`ollama`)

Uses a local Ollama server for privacy-preserving LLM operations.

**Requirements:**

- Ollama installed and running (`ollama serve`)
- Model pulled (e.g., `ollama pull llama3.2`)

**Configuration:**

```toml
[search.enhancement.utility]
provider = "ollama"
model = "llama3.2"  # or: mistral, codellama, etc.
timeout = 60

# Optional: custom Ollama server URL
# base_url = "http://localhost:11434"
```

**Recommended Models:**

- `llama3.2` - General purpose
- `codellama` - Code-focused
- `mistral` - Fast and efficient

### OpenAI (`openai`)

Uses the OpenAI API for cloud-based LLM operations.

**Requirements:**

- `OPENAI_API_KEY` environment variable set

**Configuration:**

```toml
[search.enhancement.utility]
provider = "openai"
model = "gpt-4o-mini"  # or: gpt-4o, gpt-4-turbo
timeout = 30
```

**Recommended Models:**

- `gpt-4o-mini` - Fast, cost-effective (recommended for utility tier)
- `gpt-4o` - Most capable (recommended for synthesis tier)

## Provider Selection Guide

| Use Case          | Recommended Provider | Model         |
| ----------------- | -------------------- | ------------- |
| Claude Code user  | `claude-code-cli`    | default       |
| Privacy-first     | `ollama`             | `llama3.2`    |
| High availability | `openai`             | `gpt-4o-mini` |
| Codex user        | `codex-cli`          | default       |

## Timeout Configuration

Different operations have different latency characteristics:

| Operation            | Typical Latency | Recommended Timeout |
| -------------------- | --------------- | ------------------- |
| Query expansion      | 2-5s            | 30s                 |
| Follow-up generation | 2-5s            | 30s                 |
| Result synthesis     | 5-30s           | 120s                |

## CLI Usage

### Query Expansion

Expand a query with related terms before searching:

```bash
swiftindex search --expand-query "async networking"
```

This generates synonyms, related concepts, and variations:

- **Synonyms**: asynchronous network, concurrent http
- **Related**: URLSession, async/await, Combine
- **Variations**: async net, network async

### Result Synthesis

Get an AI-generated summary of search results:

```bash
swiftindex search --synthesize "authentication flow"
```

The synthesis includes:

- **Summary**: High-level answer to your query
- **Key Insights**: Important patterns and details
- **Code References**: Relevant file:line locations
- **Follow-up Suggestions**: Related queries to explore

### Combined Usage

Use both flags for the most comprehensive results:

```bash
swiftindex search --expand-query --synthesize "error handling"
```

## MCP Server Behavior

When search enhancement is enabled, the MCP server automatically:

1. Expands queries before searching (if utility tier configured)
2. Synthesizes results before returning (if synthesis tier configured)
3. Includes follow-up suggestions in the response

The MCP response includes additional fields:

```json
{
  "results": [...],
  "synthesis": {
    "summary": "The authentication system uses...",
    "keyInsights": ["Uses JWT tokens", "Refresh handled in AuthService"],
    "codeReferences": ["AuthService.swift:42", "TokenManager.swift:87"]
  },
  "followUps": [
    {"query": "token refresh flow", "category": "deeper_understanding"},
    {"query": "auth error handling", "category": "related_code"}
  ]
}
```

## Troubleshooting

### Provider Not Available

**Error:** `LLM provider not available: claude-code-cli`

**Solutions:**

1. Check the CLI tool is installed: `which claude`
2. Ensure you have an active session
3. Try a different provider

### Timeout Errors

**Error:** `LLM operation timed out after 30s`

**Solutions:**

1. Increase the timeout in config
2. Use a faster model (e.g., switch from `gpt-4o` to `gpt-4o-mini`)
3. Use a local provider like Ollama

### API Key Missing

**Error:** `API key required for openai`

**Solution:** Set the environment variable:

```bash
export OPENAI_API_KEY=sk-...
```

## Disabling Enhancement

To disable search enhancement entirely:

```toml
[search.enhancement]
enabled = false
```

Or use CLI flags to skip enhancement for specific searches:

```bash
# Search without expansion or synthesis
swiftindex search "query" --no-expand --no-synthesize
```
