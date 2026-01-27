# Implementation Tasks

## 1. Core Security Infrastructure

- [ ] 1.1 Создать `Sources/SwiftIndexCore/Security/` директорию
- [ ] 1.2 Реализовать `KeychainManager.swift` с методами: `saveClaudeCodeToken()`, `getClaudeCodeToken()`, `deleteClaudeCodeToken()`
- [ ] 1.3 Реализовать `ClaudeCodeAuthManager.swift` с методами: `isCLIAvailable()`, `setupOAuthToken()`, `getToken()`, `deleteToken()`, `validateToken()`
- [ ] 1.4 Добавить `KeychainError` enum для error handling
- [ ] 1.5 Добавить `ClaudeCodeAuthError` enum для OAuth-специфичных ошибок

## 2. Configuration Integration

- [ ] 2.1 Обновить `EnvironmentConfigLoader.swift` для чтения Keychain токенов как fallback после env vars
- [ ] 2.2 Обновить `LLMProviderFactory.swift` для использования Keychain токенов при создании Anthropic provider
- [ ] 2.3 Добавить `CLAUDE_CODE_OAUTH_TOKEN` в environment variable chain
- [ ] 2.4 Убедиться что приоритет корректный: SWIFTINDEX_ANTHROPIC_API_KEY > CLAUDE_CODE_OAUTH_TOKEN > ANTHROPIC_API_KEY > Keychain

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

- [ ] 5.1 `KeychainManagerTests.swift` — тесты CRUD операций Keychain
- [ ] 5.2 `ClaudeCodeAuthManagerTests.swift` — моки для subprocess, парсинг токенов
- [ ] 5.3 `EnvironmentConfigLoaderTests.swift` — добавить тесты для Keychain priority chain
- [ ] 5.4 `LLMProviderFactoryTests.swift` — проверка использования Keychain токенов

### Integration Tests

- [ ] 5.5 `ClaudeCodeOAuthE2ETests.swift` — полный OAuth flow (требует моков для `claude` CLI)
- [ ] 5.6 `AuthCommandE2ETests.swift` — тесты CLI commands (status, login, logout)
- [ ] 5.7 `InitWizardOAuthTests.swift` — OAuth integration в init wizard

### Manual Testing Scenarios

- [ ] 5.8 Проверить automatic OAuth flow: `swiftindex init` → Claude Code OAuth → automatic token generation
- [ ] 5.9 Проверить manual fallback: `swiftindex auth login --manual`
- [ ] 5.10 Проверить приоритет: Keychain token используется когда env vars не заданы
- [ ] 5.11 Проверить override: `SWIFTINDEX_ANTHROPIC_API_KEY` имеет приоритет над Keychain
- [ ] 5.12 Проверить auth status: `swiftindex auth status` показывает валидный/невалидный токен

## 6. Documentation

- [ ] 6.1 Обновить `AGENTS.md`:
  - [ ] 6.1.1 Добавить `CLAUDE_CODE_OAUTH_TOKEN` в Environment Variables таблицу
  - [ ] 6.1.2 Документировать приоритет источников аутентификации
  - [ ] 6.1.3 Добавить раздел про `swiftindex auth` commands
- [ ] 6.2 Обновить `docs/search-enhancement.md`:
  - [ ] 6.2.1 Документировать Claude Code OAuth как authentication метод
  - [ ] 6.2.2 Обновить Anthropic Requirements секцию
- [ ] 6.3 Обновить `README.md`:
  - [ ] 6.3.1 Добавить quick start для Claude Code OAuth users
  - [ ] 6.3.2 Документировать `auth` commands

## 7. Platform Considerations

- [ ] 7.1 Добавить platform check (macOS only) для Keychain operations
- [ ] 7.2 Graceful fallback на env vars на non-macOS platforms
- [ ] 7.3 Документировать platform limitations (Keychain only on macOS)

## 8. Error Handling & Edge Cases

- [ ] 8.1 Обработать случай когда `claude` CLI не установлен (показать инструкции)
- [ ] 8.2 Обработать случай когда Keychain locked (показать unlock инструкции)
- [ ] 8.3 Обработать парсинг ошибки токена (fallback на manual input)
- [ ] 8.4 Обработать token validation failure (показать re-authentication инструкции)
- [ ] 8.5 Обработать concurrent access к Keychain (Security.framework thread-safe, но tests должны изолировать)

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
