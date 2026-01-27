# Implementation Tasks

## 1. Core Security Infrastructure

- [x] 1.1 Создать `Sources/SwiftIndexCore/Security/` директорию
- [x] 1.2 Реализовать `KeychainManager.swift` с методами: `saveClaudeCodeToken()`, `getClaudeCodeToken()`, `deleteClaudeCodeToken()`
  - [x] 1.2.1 Platform check: `#if canImport(Security)` для Apple platforms
  - [x] 1.2.2 Advisory file lock для write operations (`flock()` на temporary lock file)
- [x] 1.3 Реализовать `ClaudeCodeAuthManager.swift` с методами: `isCLIAvailable()`, `setupOAuthToken()`, `getToken()`, `deleteToken()`, `validateToken()`
  - [x] 1.3.1 Token parsing regex: `sk-ant-oauth-[\w-]{20,}`
  - [x] 1.3.2 Multi-line parsing (токен может быть на любой строке output)
  - [x] 1.3.3 Fallback на manual input если parsing fails
  - [ ] 1.3.4 Validation timeout: 15 seconds с 3 retries (exponential backoff) - DEFERRED (будет реализовано в CLI commands)
  - [ ] 1.3.5 Progress indicator во время validation - DEFERRED (будет реализовано в CLI commands)
- [x] 1.4 Добавить `KeychainError` enum для error handling
- [x] 1.5 Добавить `ClaudeCodeAuthError` enum для OAuth-специфичных ошибок

## 2. Configuration Integration

- [x] 2.1 Обновить `EnvironmentConfigLoader.swift` для чтения Keychain токенов как lowest priority fallback
- [x] 2.2 Обновить `LLMProviderFactory.swift` для использования Keychain токенов при создании Anthropic provider
- [x] 2.3 Добавить `CLAUDE_CODE_OAUTH_TOKEN` в environment variable chain (auto-set by Claude Code CLI)
- [x] 2.4 Реализовать priority chain (highest to lowest):
  - [x] 2.4.1 `SWIFTINDEX_ANTHROPIC_API_KEY` (project-specific override)
  - [x] 2.4.2 `CLAUDE_CODE_OAUTH_TOKEN` (OAuth env var)
  - [x] 2.4.3 `ANTHROPIC_API_KEY` (standard API key)
  - [x] 2.4.4 Keychain OAuth Token (managed fallback)
- [ ] 2.5 Добавить `auth status` показывает source токена (env var name или "Keychain") - DEFERRED (будет реализовано в CLI commands)

## 3. CLI Commands

- [ ] 3.1 Создать `Sources/swiftindex/Commands/AuthCommand.swift`
- [ ] 3.2 Реализовать `auth status` subcommand (проверка токена в Keychain + валидация)
- [ ] 3.3 Реализовать `auth login` subcommand с флагами `--force` и `--manual`
- [ ] 3.4 Реализовать `auth logout` subcommand (удаление токена из Keychain)
- [ ] 3.5 Добавить `AuthCommand` в `SwiftIndexCommand.subcommands`
- [ ] 3.6 Добавить automatic OAuth flow в `auth login` (запуск `claude setup-token`)
- [ ] 3.7 Добавить manual token input fallback в `auth login`

## 4. Init Wizard Enhancement

- [ ] 4.1 Добавить `LLMProviderOption.claudeCodeOAuth` case
- [ ] 4.2 Обновить `InitWizard.selectLLMProvider()` для показа OAuth опции
- [ ] 4.3 Реализовать OAuth setup flow в `InitWizard.run()`:
  - [ ] 4.3.1 Проверка существующего токена в Keychain
  - [ ] 4.3.2 Автоматический запуск `claude setup-token` если CLI доступен
  - [ ] 4.3.3 Manual token input fallback если CLI недоступен или automatic flow failed
  - [ ] 4.3.4 Валидация токена через Anthropic API
  - [ ] 4.3.5 Сохранение в Keychain при успехе

## 5. Tests

### Unit Tests

- [x] 5.1 `KeychainManagerTests.swift` — тесты CRUD операций Keychain (9 tests passed)
  - [x] 5.1.1 Use in-memory mock Keychain для isolation
  - [x] 5.1.2 Platform guard: `#if canImport(Security)` for Apple platforms
  - [x] 5.1.3 Test concurrent access scenarios
- [x] 5.2 `ClaudeCodeAuthManagerTests.swift` — моки для subprocess, парсинг токенов (10 tests passed)
  - [x] 5.2.1 Test token regex pattern с real examples
  - [x] 5.2.2 Test multi-line parsing
  - [x] 5.2.3 Test parsing failure fallback
  - [ ] 5.2.4 Test validation timeout и retries - DEFERRED (будет реализовано с API validation)
- [x] 5.3 `EnvironmentConfigLoaderOAuthTests.swift` — добавить тесты для Keychain priority chain (8 tests passed)
  - [x] 5.3.1 Test all priority scenarios from specs
  - [x] 5.3.2 Test env var overrides Keychain
- [ ] 5.4 `LLMProviderFactoryTests.swift` — проверка использования Keychain токенов - DEFERRED (LLMProviderFactory проверяется через integration tests)

### Integration Tests

- [ ] 5.5 `ClaudeCodeOAuthE2ETests.swift` — полный OAuth flow (требует моков для `claude` CLI)
  - [ ] 5.5.1 Use unique service/account names per test для isolation
  - [ ] 5.5.2 Cleanup Keychain после каждого теста
- [ ] 5.6 `AuthCommandE2ETests.swift` — тесты CLI commands (status, login, logout)
  - [ ] 5.6.1 Test detailed error messages
  - [ ] 5.6.2 Test token preview format
- [ ] 5.7 `InitWizardOAuthTests.swift` — OAuth integration в init wizard
- [ ] 5.8 CI configuration: skip Keychain tests на non-Apple runners

### Manual Testing Scenarios

- [ ] 5.8 Проверить automatic OAuth flow: `swiftindex init` → Claude Code OAuth → automatic token generation
- [ ] 5.9 Проверить manual fallback: `swiftindex auth login --manual`
- [ ] 5.10 Проверить приоритет: Keychain token используется когда env vars не заданы
- [ ] 5.11 Проверить override: `SWIFTINDEX_ANTHROPIC_API_KEY` имеет приоритет над Keychain
- [ ] 5.12 Проверить auth status: `swiftindex auth status` показывает валидный/невалидный токен

## 6. Documentation

- [ ] 6.1 Обновить `AGENTS.md`:
  - [ ] 6.1.1 Добавить `CLAUDE_CODE_OAUTH_TOKEN` в Environment Variables таблицу
  - [ ] 6.1.2 Clarify: "Auto-set by Claude Code CLI when running"
  - [ ] 6.1.3 Документировать приоритет источников аутентификации (highest to lowest)
  - [ ] 6.1.4 Добавить раздел про `swiftindex auth` commands
  - [ ] 6.1.5 Документировать platform support: "Apple platforms with Security.framework"
- [ ] 6.2 Обновить `docs/search-enhancement.md`:
  - [ ] 6.2.1 Документировать Claude Code OAuth как authentication метод
  - [ ] 6.2.2 Обновить Anthropic Requirements секцию
  - [ ] 6.2.3 Добавить troubleshooting секцию (Keychain locked, token expired, etc.)
- [ ] 6.3 Обновить `README.md`:
  - [ ] 6.3.1 Добавить quick start для Claude Code OAuth users
  - [ ] 6.3.2 Документировать `auth` commands
- [ ] 6.4 Добавить комментарии в generated `.swiftindex.toml`:
  - [ ] 6.4.1 Документировать priority chain
  - [ ] 6.4.2 Объяснить источники токенов

## 7. Platform Considerations

- [x] 7.1 Добавить platform check для Keychain operations:
  - [x] 7.1.1 Compile-time check: `#if canImport(Security)`
  - [x] 7.1.2 Поддержка: macOS, iOS, tvOS, watchOS
  - [x] 7.1.3 Fallback: Linux, Windows используют только env vars
- [x] 7.2 Graceful fallback на env vars на non-Apple platforms
- [ ] 7.3 Platform-specific help messages в `auth` commands - DEFERRED (будет реализовано в CLI commands)
- [ ] 7.4 Документировать platform support: "Keychain available on Apple platforms with Security.framework" - DEFERRED (будет реализовано в Documentation)

## 8. Error Handling & Edge Cases

- [x] 8.1 Обработать случай когда `claude` CLI не установлен:
  - [x] 8.1.1 Показать installation instructions
  - [x] 8.1.2 Предложить manual mode: `swiftindex auth login --manual`
- [x] 8.2 Обработать случай когда Keychain locked:
  - [x] 8.2.1 Показать unlock инструкции: `security unlock-keychain`
  - [x] 8.2.2 Предложить alternative: use environment variable
- [x] 8.3 Обработать парсинг ошибки токена:
  - [ ] 8.3.1 Log full `claude setup-token` output в debug mode - DEFERRED (будет реализовано в CLI commands)
  - [ ] 8.3.2 Automatic fallback на manual input - DEFERRED (будет реализовано в CLI commands)
  - [x] 8.3.3 Показать output пользователю для manual extraction (через error messages)
- [ ] 8.4 Обработать token validation failure: - DEFERRED (будет реализовано с API validation в CLI)
  - [ ] 8.4.1 Detailed error: "Token validation failed: Invalid credentials (HTTP 401)"
  - [ ] 8.4.2 Recovery instructions: "Run 'swiftindex auth login --force'"
  - [ ] 8.4.3 Timeout handling (15s с retries)
- [x] 8.5 Обработать concurrent access к Keychain:
  - [x] 8.5.1 Advisory file lock для write operations
  - [x] 8.5.2 Document limitation: "Not atomic across multiple processes"
  - [ ] 8.5.3 Retry logic с exponential backoff - DEFERRED (может быть добавлено позже при необходимости)
- [x] 8.6 Добавить detailed error messages для всех failure scenarios

## 9. Validation & QA

- [ ] 9.1 Запустить `openspec validate add-claude-oauth-automation --strict`
- [ ] 9.2 Запустить все unit tests: `./bin/mise run test`
- [ ] 9.3 Запустить integration tests
- [ ] 9.4 Проверить backwards compatibility: существующие API keys продолжают работать
- [ ] 9.5 Проверить что OAuth токены работают идентично API keys (тот же HTTP заголовок)

## 10. Review & Approval

- [ ] 10.1 Code review всех изменений
- [ ] 10.2 Security review Keychain implementation
- [ ] 10.3 UX review init wizard OAuth flow
- [ ] 10.4 Documentation review
- [ ] 10.5 Final approval от stakeholders
