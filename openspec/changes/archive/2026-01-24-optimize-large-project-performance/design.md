## Context

SwiftIndex показывает bottlenecks при работе с большими проектами (100K+ файлов):

1. Path filtering создаёт `NSRegularExpression` для каждого результата
2. Reindex вызывает `vectorStore.get()` последовательно в цикле
3. FollowUpGenerator использует FIFO eviction, вытесняя hot queries

Изменения затрагивают Search, Storage и LLM модули.

## Goals / Non-Goals

**Goals:**

- Устранить O(n) regex компиляций при path filtering
- Добавить batch API для vector retrieval
- LRU eviction для follow-up cache (сохранять hot queries)

**Non-Goals:**

- Шардирование базы данных
- Distributed vector search
- Incremental parsing
- Изменение defaults конфигурации (это рекомендации, не code changes)

## Decisions

### Decision 1: LRU Cache для Glob Patterns

**What**: Добавить `GlobMatcher` класс с LRU кэшем скомпилированных regex

**Why**: `NSRegularExpression` compilation стоит ~0.1-0.5ms, при 100 результатах = 10-50ms лишних

**Implementation**:

```swift
actor GlobMatcher {
    private var cache: [String: NSRegularExpression] = [:]
    private var accessOrder: [String] = []
    private let maxSize: Int

    func matches(_ path: String, pattern: String) -> Bool {
        let regex = getOrCompile(pattern)
        return regex.firstMatch(in: path, range: ...) != nil
    }

    private func getOrCompile(_ pattern: String) -> NSRegularExpression {
        if let cached = cache[pattern] {
            // Move to end of access order (LRU)
            accessOrder.removeAll { $0 == pattern }
            accessOrder.append(pattern)
            return cached
        }
        // Compile and cache...
    }
}
```

**Alternatives considered**:

- Foundation `NSCache` — не поддерживает LRU eviction policy
- Dictionary без eviction — неограниченный рост памяти

### Decision 2: Batch Vector Protocol Extension

**What**: Добавить `getBatch(ids:)` в `VectorStore` protocol

**Why**: Sequential gets = N round-trips к USearch actor, batch = 1 round-trip

**Implementation**:

```swift
protocol VectorStore {
    // Existing
    func get(id: String) async throws -> [Float]?

    // New
    func getBatch(ids: [String]) async throws -> [String: [Float]]
}

// USearchVectorStore implementation
func getBatch(ids: [String]) async throws -> [String: [Float]] {
    var result: [String: [Float]] = [:]
    result.reserveCapacity(ids.count)

    for id in ids {
        if let key = idToKey[id] {
            let vector = try index.get(key: key)
            result[id] = vector
        }
    }
    return result
}
```

**Note**: USearch не имеет native batch get, но один actor hop для всех гораздо быстрее чем N hops.

### Decision 3: LRU Eviction for FollowUpGenerator

**What**: Заменить FIFO eviction на LRU в кэше follow-up suggestions

**Why**: FIFO вытесняет первый добавленный элемент, даже если он часто используется. При активной работе hot queries (authentication, login, etc.) постоянно вытесняются и требуют повторных LLM вызовов (~2-5s каждый).

**Implementation**:

```swift
// FollowUpGenerator.swift
private var cache: [String: [FollowUpSuggestion]] = [:]
private var accessOrder: [String] = []  // NEW: track access order

func generate(query: String, results: [SearchResult]) async throws -> [FollowUpSuggestion] {
    let cacheKey = "\(query.lowercased())|\(resultSummary.prefix(100))"

    if let cached = cache[cacheKey] {
        // Move to end (most recently used)
        accessOrder.removeAll { $0 == cacheKey }
        accessOrder.append(cacheKey)
        return cached
    }

    // Generate via LLM...
    let suggestions = try await llmProvider.complete(prompt)

    // Evict LRU if full
    if cache.count >= maxCacheSize {
        let lruKey = accessOrder.removeFirst()  // CHANGED: was cache.keys.first
        cache.removeValue(forKey: lruKey)
    }

    cache[cacheKey] = suggestions
    accessOrder.append(cacheKey)
    return suggestions
}
```

**Complexity**: O(n) for removeAll, but n ≤ 50 (cache size), so negligible.

**Alternatives considered**:

- OrderedDictionary — добавляет зависимость, overcomplicated для 50 элементов
- LinkedHashMap pattern — Swift не имеет built-in, слишком много кода

## Risks / Trade-offs

| Risk                                | Mitigation                                       |
| ----------------------------------- | ------------------------------------------------ |
| LRU cache memory (GlobMatcher)      | Hard-coded 100 patterns (~10KB max)              |
| getBatch не atomic                  | USearch actor isolation обеспечивает consistency |
| O(n) removeAll in FollowUpGenerator | n ≤ 50 (cache size), ~microseconds               |

## Migration Plan

1. Add new APIs (backwards compatible)
2. Update internal callers to use batch/cached versions
3. No database schema changes required

**Rollback**: Revert to sequential calls, no data impact
