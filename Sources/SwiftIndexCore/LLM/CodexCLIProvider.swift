// MARK: - CodexCLIProvider

import Foundation

/// LLM provider that uses the Codex CLI tool.
///
/// This provider invokes the `codex` command-line tool as a subprocess
/// to generate completions. It requires Codex CLI to be installed and
/// configured with valid OpenAI credentials.
///
/// ## Prerequisites
///
/// 1. Install Codex CLI: `npm install -g @openai/codex`
/// 2. Set API key: `export OPENAI_API_KEY=your_key`
///
/// ## Usage
///
/// ```swift
/// let provider = CodexCLIProvider()
/// if await provider.isAvailable() {
///     let response = try await provider.complete(messages: [
///         .user("Explain this code")
///     ])
/// }
/// ```
public struct CodexCLIProvider: LLMProvider, Sendable {
    // MARK: - Properties

    public let id: String = "codex-cli"
    public let name: String = "Codex CLI"

    /// Path to the codex executable.
    private let executablePath: String

    /// Default model to use if none specified.
    private let defaultModel: String?

    /// Reasoning effort level for o-series models.
    public enum ReasoningEffort: String, Sendable {
        case low
        case medium
        case high
    }

    /// Reasoning effort for o-series models.
    private let reasoningEffort: ReasoningEffort?

    // MARK: - Initialization

    /// Creates a Codex CLI provider.
    ///
    /// - Parameters:
    ///   - executablePath: Path to the codex executable. If nil, searches PATH.
    ///   - defaultModel: Default model to use if none specified in complete().
    ///   - reasoningEffort: Reasoning effort for o-series models.
    public init(
        executablePath: String? = nil,
        defaultModel: String? = nil,
        reasoningEffort: ReasoningEffort? = nil
    ) {
        self.executablePath = executablePath ?? "codex"
        self.defaultModel = defaultModel
        self.reasoningEffort = reasoningEffort
    }

    // MARK: - LLMProvider

    public func isAvailable() async -> Bool {
        // Check if codex CLI is installed and accessible
        do {
            let result = try await runProcess(
                arguments: ["--version"],
                timeout: 5
            )
            return result.exitCode == 0
        } catch {
            return false
        }
    }

    public func complete(
        messages: [LLMMessage],
        model: String?,
        timeout: TimeInterval
    ) async throws -> String {
        guard !messages.isEmpty else {
            throw LLMError.invalidInput("Messages cannot be empty")
        }

        // Build the prompt from messages
        let prompt = buildPrompt(from: messages)

        // Build arguments
        var arguments = ["--quiet"]

        // Add model if specified
        if let modelName = model ?? defaultModel {
            arguments.append(contentsOf: ["--model", modelName])
        }

        // Add reasoning effort for o-series models
        if let effort = reasoningEffort {
            arguments.append(contentsOf: ["--reasoning-effort", effort.rawValue])
        }

        // Add the prompt
        arguments.append(prompt)

        // Run the CLI
        let result = try await runProcess(
            arguments: arguments,
            timeout: timeout
        )

        guard result.exitCode == 0 else {
            throw LLMError.processError(
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        let response = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if response.isEmpty {
            throw LLMError.unknown("Empty response from Codex CLI")
        }

        return response
    }

    // MARK: - Private Methods

    private func buildPrompt(from messages: [LLMMessage]) -> String {
        // For codex CLI, we concatenate messages into a single prompt
        var parts: [String] = []

        for message in messages {
            switch message.role {
            case .system:
                parts.append("System: \(message.content)")
            case .user:
                parts.append("User: \(message.content)")
            case .assistant:
                parts.append("Assistant: \(message.content)")
            }
        }

        return parts.joined(separator: "\n\n")
    }

    private func runProcess(
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executablePath] + arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return try await withCheckedThrowingContinuation { continuation in
            // Set up timeout
            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if process.isRunning {
                    process.terminate()
                }
            }

            do {
                try process.run()
            } catch {
                timeoutTask.cancel()
                continuation.resume(throwing: LLMError.cliNotFound(tool: executablePath))
                return
            }

            process.waitUntilExit()
            timeoutTask.cancel()

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""

            if process.terminationStatus == 15 { // SIGTERM
                continuation.resume(throwing: LLMError.timeout(seconds: timeout))
                return
            }

            continuation.resume(returning: ProcessResult(
                exitCode: process.terminationStatus,
                stdout: stdout,
                stderr: stderr
            ))
        }
    }
}

// MARK: - ProcessResult

private struct ProcessResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}
