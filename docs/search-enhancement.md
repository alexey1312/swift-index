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

SwiftIndex supports several LLM providers:

### MLX (`mlx`)

Uses Apple MLX for fully local text generation on Apple Silicon. Best for privacy-sensitive use cases and offline operation.

**Requirements:**

- Apple Silicon Mac (M1 or later)
- macOS 14.0+
- First run downloads model from HuggingFace (~2-7GB)

**Configuration:**

```toml
[search.enhancement.utility]
provider = "mlx"
model = "mlx-community/Qwen3-4B-4bit"  # optional (default)
timeout = 60
```

**Supported Models:**

- `mlx-community/Qwen3-4B-4bit` - Default, good balance of quality/speed
- `mlx-community/SmolLM-135M-Instruct-4bit` - Ultra-fast, basic capabilities
- `mlx-community/Llama-3.2-1B-Instruct-4bit` - Compact, good for simple tasks
- `mlx-community/Llama-3.2-3B-Instruct-4bit` - Larger, better quality

Models are cached in `~/.cache/huggingface/` after first download.

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

### Anthropic (`anthropic`)

Uses the Anthropic Messages API directly for fast, low-latency operations. **Much faster than `claude-code-cli`** (5-10s vs 35-40s) because it bypasses CLI initialization overhead.

**Requirements:**

- `ANTHROPIC_API_KEY` environment variable set

**Configuration:**

```toml
[search.enhancement.utility]
provider = "anthropic"
model = "claude-haiku-4-5-20251001"  # fast, efficient (default)
timeout = 30

[search.enhancement.synthesis]
provider = "anthropic"
model = "claude-sonnet-4-5-20250929"  # more capable
timeout = 60
```

**Supported Models:**

- `claude-haiku-4-5-20251001` - Fastest, efficient (recommended for utility tier)
- `claude-sonnet-4-5-20250929` - Best balance (recommended for synthesis tier)
- `claude-opus-4-5-20251101` - Most capable overall

**Performance Comparison:**

| Provider          | Typical Latency |
| ----------------- | --------------- |
| `claude-code-cli` | ~35-40s         |
| `anthropic`       | ~5-10s          |

The `anthropic` provider is recommended over `claude-code-cli` when direct API access is acceptable, as it significantly reduces search enhancement latency.

### Gemini (`gemini`) / Gemini CLI (`gemini-cli`)

Uses Google's Gemini models via API or CLI.

**Gemini API (`gemini`):**

- **Requirements:** `GEMINI_API_KEY` environment variable set
- **Configuration:** `provider = "gemini"`
- **Models:** `gemini-1.5-flash` (default), `gemini-1.5-pro`

**Gemini CLI (`gemini-cli`):**

- **Requirements:** `gemini` command installed
- **Configuration:** `provider = "gemini-cli"`

```toml
[search.enhancement.utility]
provider = "gemini"
model = "gemini-1.5-flash"
timeout = 30
```

## Provider Selection Guide

| Use Case               | Recommended Provider | Model                       |
| ---------------------- | -------------------- | --------------------------- |
| Privacy-first (local)  | `mlx`                | `Qwen3-4B-4bit`             |
| Offline usage          | `mlx`                | `Qwen3-4B-4bit`             |
| Claude models (fast)   | `anthropic`          | `claude-haiku-4-5-20251001` |
| Claude models (legacy) | `claude-code-cli`    | default                     |
| Local server (non-M1)  | `ollama`             | `llama3.2`                  |
| High availability      | `openai`             | `gpt-4o-mini`               |
| Codex user             | `codex-cli`          | default                     |

**Notes:**

- MLX is recommended for Apple Silicon users who want fully local, private LLM operations with no cloud dependency.
- `anthropic` is recommended over `claude-code-cli` when direct API access is acceptable, as it significantly reduces latency (5-10s vs 35-40s).

## Timeout Configuration

Different operations have different latency characteristics:

| Operation              | Typical Latency | Recommended Timeout |
| ---------------------- | --------------- | ------------------- |
| Query expansion        | 2-5s            | 30s                 |
| Follow-up generation   | 2-5s            | 30s                 |
| Description generation | 2-5s per chunk  | 30s                 |
| Result synthesis       | 5-30s           | 120s                |

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

## Description Generation

AI descriptions for code chunks are **automatically generated** during indexing when an LLM provider is available:

```bash
swiftindex index .
```

Descriptions are generated when:

- `[search.enhancement]` is configured with a utility provider, OR
- The `claude` CLI is installed (used as default fallback)

Descriptions provide human-readable summaries explaining each code chunk's purpose. They are:

- Stored in the database alongside code chunks
- **Indexed in FTS5** for BM25 keyword search (searchable!)
- Visible in search results (human/JSON/TOON formats)

**Note:** Description generation uses the **utility tier** LLM provider. For large codebases, consider using a fast provider like `ollama` or `gpt-4o-mini` to reduce indexing times.

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

**Error:** `API key required for openai` or `API key required for Anthropic`

**Solution:** Set the appropriate environment variable:

```bash
# For OpenAI provider
export OPENAI_API_KEY=sk-...

# For Anthropic provider
export ANTHROPIC_API_KEY=sk-ant-...
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
