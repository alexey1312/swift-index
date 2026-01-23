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
        "embedding": ["provider", "model", "dimension"],
        "search": ["semantic_weight", "rrf_k", "multi_hop_enabled", "multi_hop_depth", "output_format"],
        "indexing": ["exclude", "include_extensions", "max_file_size", "chunk_size", "chunk_overlap"],
        "storage": ["index_path", "cache_path"],
        "watch": ["debounce_ms"],
        "logging": ["level"],
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

            for (key, _) in sectionTable {
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
                }
            }
        }

        if let formattingDiagnostic = formattingDiagnostic(contents: contents) {
            diagnostics.append(formattingDiagnostic)
        }

        return diagnostics
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
