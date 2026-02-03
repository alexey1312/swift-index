import Foundation
import TOML

public enum TOMLConfigDiagnosticSeverity: String, Sendable {
    case error
    case warning
}

public struct TOMLConfigDiagnostic: Sendable, Equatable {
    public let severity: TOMLConfigDiagnosticSeverity
    public let message: String
    public let keyPath: String?

    public init(severity: TOMLConfigDiagnosticSeverity, message: String, keyPath: String? = nil) {
        self.severity = severity
        self.message = message
        self.keyPath = keyPath
    }
}

public enum TOMLConfigValidator {
    private static let allowedSections: [String: Set<String>] = [
        "embedding": ["provider", "model", "dimension", "batch_size", "batch_timeout_ms", "batch_memory_limit_mb"],
        "search": [
            "semantic_weight", "rrf_k", "multi_hop_enabled", "multi_hop_depth", "output_format",
            "limit", "expand_query_by_default", "synthesize_by_default",
            "default_extensions", "default_path_filter", "enhancement",
        ],
        "indexing": [
            "exclude",
            "include_extensions",
            "max_file_size",
            "chunk_size",
            "chunk_overlap",
            "max_concurrent_tasks",
        ],
        "storage": ["index_path", "cache_path"],
        "watch": ["debounce_ms"],
        "logging": ["level"],
        "remote": ["enabled", "provider", "bucket", "region", "project", "prefix", "sync"],
    ]

    /// Allowed keys for nested subsections (e.g., search.enhancement.utility).
    /// Structure: ["parent.child": ["key1", "key2", ...]]
    private static let allowedNestedSections: [String: Set<String>] = [
        "search.enhancement": ["enabled", "utility", "synthesis"],
        "search.enhancement.utility": ["provider", "model", "timeout"],
        "search.enhancement.synthesis": ["provider", "model", "timeout"],
        "remote.sync": ["compression", "auto_pull"],
    ]

    private static let forbiddenSections: Set<String> = ["api_keys"]

    private static let forbiddenKeySuffixes: Set<String> = ["api_key", "api_key_env"]

    public static func lint(contents: String, filePath: String) throws -> [TOMLConfigDiagnostic] {
        var diagnostics: [TOMLConfigDiagnostic] = []

        let decoder = TOMLDecoder()
        let rootValue: TOMLValue
        do {
            rootValue = try decoder.decode(TOMLValue.self, from: contents)
        } catch {
            throw ConfigError.invalidSyntax("Invalid TOML: \(error.localizedDescription)")
        }

        guard case let .table(rootTable) = rootValue else {
            diagnostics.append(
                TOMLConfigDiagnostic(
                    severity: .error,
                    message: "Root of TOML must be a table",
                    keyPath: nil
                )
            )
            return diagnostics
        }

        for (section, value) in rootTable {
            if forbiddenSections.contains(section) {
                diagnostics.append(
                    TOMLConfigDiagnostic(
                        severity: .error,
                        message: "API keys must be provided via environment variables (VOYAGE_API_KEY, OPENAI_API_KEY)",
                        keyPath: section
                    )
                )
                continue
            }

            guard let allowedKeys = allowedSections[section] else {
                if section == "voyage" || section == "openai" {
                    if case let .table(sectionTable) = value,
                       sectionTable.keys.contains("api_key")
                    {
                        diagnostics.append(
                            TOMLConfigDiagnostic(
                                severity: .error,
                                message: "API keys must be set via environment variables",
                                keyPath: "\(section).api_key"
                            )
                        )
                    } else {
                        diagnostics.append(
                            TOMLConfigDiagnostic(
                                severity: .error,
                                message: "Unknown configuration section: \(section)",
                                keyPath: section
                            )
                        )
                    }
                    continue
                }
                diagnostics.append(
                    TOMLConfigDiagnostic(
                        severity: .error,
                        message: "Unknown configuration section: \(section)",
                        keyPath: section
                    )
                )
                continue
            }

            guard case let .table(sectionTable) = value else {
                diagnostics.append(
                    TOMLConfigDiagnostic(
                        severity: .error,
                        message: "Section must be a table",
                        keyPath: section
                    )
                )
                continue
            }

            for (key, value) in sectionTable {
                if forbiddenKeySuffixes.contains(key) {
                    let path = "\(section).\(key)"
                    diagnostics.append(
                        TOMLConfigDiagnostic(
                            severity: .error,
                            message: "API keys must be set via environment variables",
                            keyPath: path
                        )
                    )
                    continue
                }

                if !allowedKeys.contains(key) {
                    let path = "\(section).\(key)"
                    diagnostics.append(
                        TOMLConfigDiagnostic(
                            severity: .error,
                            message: "Unknown configuration key: \(path)",
                            keyPath: path
                        )
                    )
                    continue
                }

                // Handle nested sections (e.g., search.enhancement)
                if case let .table(nestedTable) = value {
                    let nestedPath = "\(section).\(key)"
                    validateNestedSection(
                        nestedTable,
                        path: nestedPath,
                        diagnostics: &diagnostics
                    )
                }
            }
        }

        if let formattingDiagnostic = formattingDiagnostic(contents: contents) {
            diagnostics.append(formattingDiagnostic)
        }

        return diagnostics
    }

    /// Recursively validates a nested TOML section.
    ///
    /// - Parameters:
    ///   - table: The nested table to validate.
    ///   - path: The dot-separated path to this section (e.g., "search.enhancement").
    ///   - diagnostics: Array to append any validation errors to.
    private static func validateNestedSection(
        _ table: [String: TOMLValue],
        path: String,
        diagnostics: inout [TOMLConfigDiagnostic]
    ) {
        guard let allowedKeys = allowedNestedSections[path] else {
            // If no nested rules defined, skip validation (allow any keys)
            return
        }

        for (key, value) in table {
            if !allowedKeys.contains(key) {
                let keyPath = "\(path).\(key)"
                diagnostics.append(
                    TOMLConfigDiagnostic(
                        severity: .error,
                        message: "Unknown configuration key: \(keyPath)",
                        keyPath: keyPath
                    )
                )
                continue
            }

            // Recursively validate deeper nested sections
            if case let .table(nestedTable) = value {
                let nestedPath = "\(path).\(key)"
                validateNestedSection(nestedTable, path: nestedPath, diagnostics: &diagnostics)
            }
        }
    }

    public static func format(contents: String) throws -> String {
        let decoder = TOMLDecoder()
        let value = try decoder.decode(TOMLValue.self, from: contents)

        let encoder = TOMLEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encodeToString(value)
    }

    private static func formattingDiagnostic(contents: String) -> TOMLConfigDiagnostic? {
        guard let formatted = try? format(contents: contents) else {
            return nil
        }

        let normalizedInput = normalize(contents)
        let normalizedFormatted = normalize(formatted)

        guard normalizedInput != normalizedFormatted else {
            return nil
        }

        return TOMLConfigDiagnostic(
            severity: .warning,
            message: "TOML formatting differs from canonical style. Run 'swiftindex config format' to fix.",
            keyPath: nil
        )
    }

    private static func normalize(_ contents: String) -> String {
        var normalizedLines: [String] = []

        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = stripInlineComments(String(rawLine))
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }
            normalizedLines.append(trimmed)
        }

        return normalizedLines.joined(separator: "\n")
    }

    private static func stripInlineComments(_ line: String) -> String {
        var inSingleQuote = false
        var inDoubleQuote = false
        var isEscaped = false

        for (index, character) in line.enumerated() {
            if isEscaped {
                isEscaped = false
                continue
            }

            if character == "\\" {
                isEscaped = true
                continue
            }

            if character == "\"", !inSingleQuote {
                inDoubleQuote.toggle()
                continue
            }

            if character == "'", !inDoubleQuote {
                inSingleQuote.toggle()
                continue
            }

            if character == "#", !inSingleQuote, !inDoubleQuote {
                return String(line.prefix(index))
            }
        }

        return line
    }
}
