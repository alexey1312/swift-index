# Design: Claude Code OAuth Automation

## Context

Claude Code Pro/Max пользователи могут генерировать OAuth токены через `claude setup-token`, которые:

- Имеют ограниченный срок жизни
- Автоматически обновляются Claude Code CLI
- Передаются через тот же HTTP заголовок `x-api-key` что и обычные API keys
- Более безопасны для временного доступа
- **Автоматически экспортируются** в `CLAUDE_CODE_OAUTH_TOKEN` environment variable когда Claude Code CLI запущен в shell session

SwiftIndex уже использует Anthropic API через `AnthropicLLMProvider` для search enhancement (query expansion, result synthesis). Текущая имплементация требует API key через environment variables, что создаёт трение для Claude Code пользователей и риск утечки токенов.

**Constraints:**

- macOS only для Keychain integration (initial release)
- Должна сохраниться обратная совместимость с API keys
- OAuth токены функционально идентичны API keys на уровне HTTP API

**Stakeholders:**

- Claude Code Pro/Max пользователи — primary beneficiaries
- Разработчики SwiftIndex — maintainers
- Security-conscious users — benefit from Keychain storage

## Goals / Non-Goals

**Goals:**

- ✅ Автоматизировать OAuth token management для Claude Code пользователей
- ✅ Безопасное хранение токенов через macOS Keychain
- ✅ Seamless integration в init wizard
- ✅ Manual fallback для случаев когда automatic flow недоступен
- ✅ Прозрачность на уровне API — OAuth токены используют ту же инфраструктуру что и API keys
- ✅ CLI commands для token management (`auth status`, `login`, `logout`)

**Non-Goals:**

- ❌ Cross-platform credential storage (Linux libsecret, Windows Credential Manager) — future work
- ❌ Automatic token refresh — обрабатывается Claude Code CLI
- ❌ Multi-account support — single OAuth token per system
- ❌ Token expiration tracking — Anthropic API вернёт 401, user re-authenticates
- ❌ Separate OAuth provider — переиспользуем `AnthropicLLMProvider`

## Decisions

### Decision 1: Keychain as Primary Storage

**What:** Использовать macOS Keychain через Security.framework для хранения OAuth токенов.

**Why:**

- Industry best practice для credential storage на macOS
- Системная защита (encryption at rest, access control)
- Интеграция с macOS security policies (unlock-keychain)
- Избегаем plaintext токенов в environment variables или config files

**Alternatives considered:**

1. **File-based storage** (`~/.swiftindex/credentials.json`)
   - ❌ Риск plaintext exposure
   - ❌ Требует custom encryption
   - ❌ Не интегрируется с OS security model
2. **Environment variables only**
   - ❌ Plaintext в shell history, process environment
   - ❌ Не персистентны между сессиями
   - ❌ Risk of accidental logging
3. **SwiftSecurity или KeychainAccess библиотеки**
   - ❌ Дополнительная зависимость (~5KB+ кода)
   - ✅ Security.framework — native, zero dependencies

### Decision 2: Priority Chain for Authentication Sources

**What:** Приоритет (highest to lowest):

1. `SWIFTINDEX_ANTHROPIC_API_KEY` (env var)
2. `CLAUDE_CODE_OAUTH_TOKEN` (env var)
3. `ANTHROPIC_API_KEY` (env var)
4. Keychain OAuth Token (Security.framework)

**Why:**

- Environment variables имеют приоритет — позволяет explicit overrides для testing, CI/CD, project-specific configs
- `SWIFTINDEX_*` prefix — highest priority для project-specific overrides (существующее поведение)
- `CLAUDE_CODE_OAUTH_TOKEN` — автоматически устанавливается Claude Code CLI при запуске, higher priority чем generic `ANTHROPIC_API_KEY`
- `ANTHROPIC_API_KEY` — standard API key fallback (обратная совместимость)
- Keychain — lowest priority, managed fallback для пользователей без explicit env vars

**Trade-offs:**

- ✅ Environment variables имеют приоритет — упрощает testing и overrides
- ✅ Не ломает существующие workflows
- ✅ Explicit configuration beats implicit (env vars > Keychain)
- ✅ Keychain как managed fallback — good UX для обычных пользователей
- ⚠️ Может быть неочевидно для пользователей (митигация: документация + `auth status` показывает source)

### Decision 3: Reuse AnthropicLLMProvider

**What:** OAuth токены передаются в `AnthropicLLMProvider` через тот же `apiKey: String` параметр.

**Why:**

- Anthropic API не различает OAuth токены и API keys — оба используют `x-api-key` заголовок
- Нет необходимости в отдельном provider
- Минимизирует изменения кода
- Simplifies testing и maintenance

**Alternatives considered:**

1. **Separate `AnthropicOAuthProvider`**
   - ❌ Дублирование ~100 строк HTTP client кода
   - ❌ Увеличивает complexity конфигурации
   - ❌ Функционально идентичны

### Decision 4: Automatic + Manual Flow

**What:** OAuth flow в init wizard:

1. **Automatic** (preferred): Запускает `claude setup-token` как subprocess
2. **Manual** (fallback): Prompt для ручного ввода токена

**Why:**

- Automatic flow — best UX для пользователей с установленным `claude` CLI
- Manual fallback — поддержка edge cases (CLI недоступен, SSH sessions, CI/CD)
- Validation через Anthropic API — проверяет что токен рабочий до сохранения

**Alternatives considered:**

1. **Automatic only**
   - ❌ Блокирует пользователей без `claude` CLI
2. **Manual only**
   - ❌ Хуже UX (копирование токенов из терминала)
3. **OAuth redirect flow** (browser-based authentication)
   - ❌ Требует HTTP server
   - ❌ Anthropic не поддерживает (используется `claude` CLI)

### Decision 5: CLI Auth Commands

**What:** Добавить `swiftindex auth` command с subcommands:

- `auth status` — показывает состояние токена (exists, valid/invalid)
- `auth login` — OAuth flow с `--force` и `--manual` флагами
- `auth logout` — удаляет токен из Keychain

**Why:**

- Separation of concerns — auth management отдельно от indexing/search
- Discoverable — `swiftindex --help` покажет auth commands
- Flexibility — пользователи могут управлять токенами независимо от init wizard
- Standard UX pattern — аналогично `gh auth`, `aws configure`, etc.

### Decision 6: Token Validation

**What:** Валидация токенов через `AnthropicLLMProvider.isAvailable()` который делает test API call.

**Why:**

- Catches invalid tokens до сохранения в Keychain
- Prevents broken state (saved but non-working token)
- Reuses existing validation logic

**Trade-offs:**

- ⚠️ Network call during init/login (adds latency ~1-2s)
- ✅ Better UX than discovering invalid token during first search

## Architecture

### Module Structure

```
Sources/SwiftIndexCore/Security/
├── KeychainManager.swift          # Keychain CRUD operations
└── ClaudeCodeAuthManager.swift    # OAuth flow management

Sources/swiftindex/Commands/
├── AuthCommand.swift              # CLI auth commands
├── InitCommand.swift              # Updated wizard
└── SwiftIndexCommand.swift        # Register auth command

Sources/SwiftIndexCore/Configuration/
└── EnvironmentConfigLoader.swift  # Add Keychain fallback

Sources/SwiftIndexCore/LLM/
└── LLMProviderFactory.swift       # Use Keychain tokens
```

### Data Flow: OAuth Token Usage

```
User runs: swiftindex search "query" --synthesize

1. EnvironmentConfigLoader.load()
   ├─ Check SWIFTINDEX_ANTHROPIC_API_KEY → nil
   ├─ Check CLAUDE_CODE_OAUTH_TOKEN → nil
   ├─ Check ANTHROPIC_API_KEY → nil
   └─ KeychainManager.getClaudeCodeToken() → "oauth-token-123"

2. LLMProviderFactory.createProvider(id: .anthropic)
   ├─ anthropicKey parameter: nil
   ├─ KeychainManager.getClaudeCodeToken() → "oauth-token-123"
   └─ return AnthropicLLMProvider(apiKey: "oauth-token-123")

3. AnthropicLLMProvider.generate()
   ├─ HTTP request to api.anthropic.com
   ├─ Header: "x-api-key: oauth-token-123"
   └─ Return result

4. ResultSynthesizer uses generated text
```

### Data Flow: OAuth Setup (Automatic)

```
User runs: swiftindex init → Claude Code OAuth

1. InitWizard selects llmProvider = .claudeCodeOAuth

2. Check existing token:
   KeychainManager.getClaudeCodeToken() → nil

3. Check CLI availability:
   ClaudeCodeAuthManager.isCLIAvailable() → true

4. Run OAuth flow:
   ClaudeCodeAuthManager.setupOAuthToken()
   ├─ Process.run("claude", "setup-token")
   ├─ Wait for completion (user authenticates in browser)
   ├─ Parse token from stdout
   ├─ Validate token: AnthropicLLMProvider.isAvailable()
   └─ KeychainManager.saveClaudeCodeToken(token)

5. Continue with wizard (save config, etc.)
```

### Data Flow: OAuth Setup (Manual Fallback)

```
User runs: swiftindex auth login --manual

1. Show instructions:
   - Run: claude setup-token
   - Copy the generated token

2. Prompt for token input:
   token = readLine()

3. Validate token:
   ClaudeCodeAuthManager.validateToken(token)
   └─ AnthropicLLMProvider(apiKey: token).isAvailable()

4. Save if valid:
   KeychainManager.saveClaudeCodeToken(token)
```

### Security Considerations

**Keychain Security:**

- Service name: `com.swiftindex.oauth` (unique identifier)
- Account name: `claude-code-oauth-token` (single token per system)
- Accessibility: `kSecAttrAccessibleWhenUnlocked` (only when device unlocked)
- No synchronization across devices (local-only storage)

**Token Exposure Risks:**

- ✅ Not in environment variables (unless explicitly set by user)
- ✅ Not in config files
- ✅ Not in shell history (unless user runs manual commands)
- ✅ Encrypted at rest by Keychain
- ⚠️ Accessible to process running as user (same as any Keychain item)

**Validation:**

- All tokens validated before storage (prevents broken state)
- Timeout on validation:
  - **15 seconds** для interactive flows (wizard, `auth login`) — better UX
  - **3 retries** с exponential backoff (1s, 2s, 4s delays)
  - Progress indicator показывается во время validation
- Graceful handling of 401/403 responses (invalid token)
- Clear error messages с recovery instructions

## Risks / Trade-offs

### Risk 1: Keychain Lock-out

**Risk:** User's Keychain is locked, Keychain access fails.

**Mitigation:**

- Show clear error message with unlock instructions
- Fallback на manual `ANTHROPIC_API_KEY` setup
- Document workaround: `security unlock-keychain ~/Library/Keychains/login.keychain-db`

### Risk 2: Token Expiration

**Risk:** OAuth token expires, search fails with 401.

**Mitigation:**

- Show helpful error message: "OAuth token expired, run `swiftindex auth login`"
- `auth status` command to check token validity
- Document that tokens auto-refresh via Claude Code CLI (if running)

### Risk 3: `claude` CLI Unavailable

**Risk:** User doesn't have `claude` installed, automatic flow fails.

**Mitigation:**

- Check CLI availability before attempting automatic flow
- Automatic fallback на manual token input
- Show installation instructions if CLI missing

### Risk 4: Token Parsing Changes

**Risk:** `claude setup-token` output format changes, parsing breaks.

**Token Format:**

- Expected pattern: `sk-ant-oauth-[a-zA-Z0-9_-]+`
- Regex: `sk-ant-oauth-[\w-]{20,}`
- Extraction strategy:
  1. Try regex match in stdout/stderr
  2. If multiple matches found, use first one
  3. If no match, show full output and prompt manual input
  4. Validate extracted token before accepting

**Mitigation:**

- Robust regex pattern for token extraction (see above)
- Multi-line parsing (token может быть на любой строке output)
- Fallback на manual input if parsing fails
- Log full `claude setup-token` output в debug mode
- Unit tests с примерами реального output

### Risk 5: Platform Limitations

**Risk:** Platforms without Security.framework (Linux/Windows) can't use Keychain.

**Platform Detection:**

```swift
#if canImport(Security)
  // Keychain operations available
  // Works on: macOS, iOS, tvOS, watchOS
#else
  // Fallback to environment variables only
  // Platforms: Linux, Windows
#endif
```

**Mitigation:**

- Compile-time platform check через `canImport(Security)`
- Document platform support: "Keychain available on Apple platforms (macOS, iOS, etc.)"
- Continue supporting environment variables (cross-platform fallback)
- Future work: Linux libsecret, Windows Credential Manager
- CLI shows platform-specific help messages

### Risk 6: Concurrent Keychain Access

**Risk:** Multiple SwiftIndex processes access Keychain simultaneously (read/write/delete conflicts).

**Analysis:**

- Security.framework is thread-safe within single process
- Cross-process atomicity NOT guaranteed by Keychain
- Scenarios:
  - Process A reads token while Process B deletes → read may return stale/nil
  - Process A saves token while Process B saves → last write wins
  - Multiple parallel `auth login` calls → race condition

**Mitigation:**

- **Documented limitation**: "Keychain operations are not atomic across multiple SwiftIndex processes"
- **Advisory file lock** для write operations:
  ```swift
  let lockFile = FileManager.default.temporaryDirectory
    .appendingPathComponent("swiftindex-keychain.lock")
  // Use flock() for advisory locking
  ```
- **Idempotent operations**: save/delete are safe to retry
- **Tests**: integration tests проверяют concurrent scenarios
- **Error handling**: retry logic с exponential backoff for transient failures

## Migration Plan

**Phase 1: Initial Release (macOS only)**

- ✅ Keychain storage for OAuth tokens
- ✅ CLI auth commands
- ✅ Init wizard integration
- ✅ Documentation

**Phase 2: Enhanced UX (future)**

- Token expiration tracking
- Automatic re-authentication prompts
- Multi-account support

**Phase 3: Cross-Platform (future)**

- Linux: libsecret integration
- Windows: Credential Manager integration
- Platform-agnostic credential storage abstraction

**Rollback Strategy:**
If issues arise:

1. Keychain operations fail gracefully → fallback на env vars
2. CLI auth commands are optional → users can skip and use manual setup
3. Init wizard OAuth option can be skipped → defaults to API key
4. No breaking changes → existing configurations unaffected

## Open Questions

1. **Q:** Should we support multiple OAuth tokens (multi-account)?
   **A:** No for initial release. Single token per system simplifies implementation. Future enhancement: project-specific tokens через account name suffix `claude-code-oauth-token:project-hash`.

2. **Q:** Should we cache token validity checks?
   **A:** No. Validation is fast (~1-2s) and infrequent (only during setup/status). Cache adds complexity without significant benefit.

3. **Q:** Should we show token preview in `auth status`?
   **A:** Yes, first 10 characters + masking. Example: `sk-ant-oau*** (first 10 chars)`. Helps users identify which token is stored without exposing full credential.

4. **Q:** Should we support token rotation (store old + new tokens)?
   **A:** No for initial release. Claude Code CLI handles token refresh automatically. We just store the current token.

5. **Q:** Should we encrypt tokens in Keychain?
   **A:** No additional encryption needed. Keychain already encrypts items at rest. Our responsibility is access control (kSecAttrAccessibleWhenUnlocked).

6. **Q:** What is the source of `CLAUDE_CODE_OAUTH_TOKEN` environment variable?
   **A:** Automatically exported by Claude Code CLI when running in shell session. Users don't need to set it manually. SwiftIndex checks this env var to support seamless integration with Claude Code workflows.

7. **Q:** Should we proactively check token expiration before search/index operations?
   **A:** Initial release: reactive (handle 401 errors). Future enhancement: proactive validation + timestamp tracking to warn users before expiration.

## Success Metrics

**User Experience:**

- Reduction in auth-related support requests
- Increased adoption of search enhancement features
- Positive feedback on init wizard OAuth flow

**Technical:**

- Zero security vulnerabilities in Keychain implementation
- < 5% test flakiness due to Keychain operations
- Backward compatibility maintained (no breaking changes)

**Adoption:**

- 30%+ of Pro/Max users enable OAuth via init wizard (target)
- Auth commands usage tracked via telemetry (if implemented)
