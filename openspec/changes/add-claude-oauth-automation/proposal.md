# Change: Автоматическое Управление Claude Code OAuth Токенами

## Why

Claude Code Pro/Max пользователи могут генерировать OAuth токены через `claude setup-token`, которые более безопасны и автоматически обновляются. Однако SwiftIndex требует ручной настройки этих токенов через environment variables, что создаёт трение для пользователей и увеличивает риск утечки токенов через файлы конфигурации.

Интеграция автоматического управления OAuth токенами через macOS Keychain улучшит user experience для Claude Code пользователей и повысит безопасность за счёт:

- Безопасного хранения токенов в системном Keychain
- Автоматического запуска OAuth flow из init wizard
- Устранения необходимости ручного копирования токенов
- Поддержки как автоматического, так и ручного ввода токенов

## What Changes

- **ADDED**: `KeychainManager` модуль для безопасной работы с macOS Keychain через Security.framework
- **ADDED**: `ClaudeCodeAuthManager` для управления OAuth flow (запуск `claude setup-token`, парсинг, валидация)
- **ADDED**: `swiftindex auth` command с subcommands: `status`, `login`, `logout`
- **ADDED**: Новая опция "Claude Code OAuth (Pro/Max)" в init wizard LLM provider selection
- **MODIFIED**: `EnvironmentConfigLoader` теперь читает токены из Keychain как fallback
- **MODIFIED**: `LLMProviderFactory` использует Keychain токены при создании Anthropic provider
- **MODIFIED**: `InitCommand` wizard добавляет OAuth setup flow с manual fallback

Приоритет источников аутентификации (от высшего к низшему):

1. Keychain OAuth Token (macOS Keychain) — новое
2. `SWIFTINDEX_ANTHROPIC_API_KEY` — проект-специфичный override
3. `CLAUDE_CODE_OAUTH_TOKEN` — OAuth токен из environment
4. `ANTHROPIC_API_KEY` — стандартный API ключ

**Platform Support**: macOS only в initial release (использует Security.framework). Linux/Windows продолжают использовать environment variables.

## Impact

**Affected specs:**

- `security` (NEW) — новая capability для authentication и credential storage
- `cli` — добавление auth command, обновление init wizard
- `configuration` — обновление приоритета источников конфигурации

**Affected code:**

- `Sources/SwiftIndexCore/Security/` (новый модуль)
  - `KeychainManager.swift` — Keychain обёртка
  - `ClaudeCodeAuthManager.swift` — OAuth flow management
- `Sources/swiftindex/Commands/`
  - `AuthCommand.swift` (новый) — CLI auth commands
  - `InitCommand.swift` — добавление OAuth опции в wizard
  - `SwiftIndexCommand.swift` — регистрация AuthCommand
- `Sources/SwiftIndexCore/Configuration/`
  - `EnvironmentConfigLoader.swift` — Keychain fallback
- `Sources/SwiftIndexCore/LLM/`
  - `LLMProviderFactory.swift` — Keychain priority
- `AGENTS.md` — документация OAuth + CLI commands
- `docs/search-enhancement.md` — обновление Anthropic секции

**Breaking Changes**: None. Полностью обратно совместимо — существующие API keys и environment variables продолжают работать.

**Migration**: Не требуется. Пользователи могут продолжать использовать API keys или opt-in в OAuth токены через `swiftindex auth login` или init wizard.

**User Benefits:**

- ✅ Более безопасное хранение токенов (system Keychain vs plaintext env vars)
- ✅ Автоматическое управление токенами через init wizard
- ✅ Нет необходимости вручную копировать токены из терминала
- ✅ Поддержка Claude Code Pro/Max features out-of-the-box
- ✅ Manual fallback для случаев когда `claude` CLI недоступен

**Technical Benefits:**

- ✅ Следует Apple security best practices (Keychain для credentials)
- ✅ Минимальные изменения — переиспользует существующую `AnthropicLLMProvider` инфраструктуру
- ✅ Прозрачно для API — OAuth токены используют тот же `x-api-key` заголовок
- ✅ Тестируемо — Keychain operations изолированы в отдельном модуле
