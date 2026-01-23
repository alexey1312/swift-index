// MARK: - ClaudeCodeCLIProvider

import Foundation

/// LLM provider that uses the Claude Code CLI tool.
///
/// This provider invokes the `claude` command-line tool as a subprocess
/// to generate completions. It requires Claude Code to be installed and
/// configured with valid credentials.
///
/// ## Prerequisites
///
/// 1. Install Claude Code: `npm install -g @anthropic-ai/claude-code`
/// 2. Authenticate: `claude auth login`
///
/// ## Usage
///
/// ```swift
/// let provider = ClaudeCodeCLIProvider()
/// if await provider.isAvailable() {
///     let response = try await provider.complete(messages: [
///         .user("What is the capital of France?")
///     ])
/// }
/// ```
public struct ClaudeCodeCLIProvider: LLMProvider, Sendable {
    // MARK: - Properties

    public let id: String = "claude-code-cli"
    public let name: String = "Claude Code CLI"

    /// Path to the claude executable.
    private let executablePath: String

    /// Default model to use if none specified.
    private let defaultModel: String?

    // MARK: - Initialization

    /// Creates a Claude Code CLI provider.
    ///
    /// - Parameters:
    ///   - executablePath: Path to the claude executable. If nil, searches PATH.
    ///   - defaultModel: Default model to use if none specified in complete().
    public init(
        executablePath: String? = nil,
        defaultModel: String? = nil
    ) {
        self.executablePath = executablePath ?? "claude"
        self.defaultModel = defaultModel
    }

    // MARK: - LLMProvider

    public func isAvailable() async -> Bool {
        // Check if claude CLI is installed and accessible
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
        var arguments = ["--print"]

        // Add model if specified
        if let modelName = model ?? defaultModel {
            arguments.append(contentsOf: ["--model", modelName])
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
            throw LLMError.unknown("Empty response from Claude Code CLI")
        }

        return response
    }

    // MARK: - Private Methods

    private func buildPrompt(from messages: [LLMMessage]) -> String {
        // For claude CLI, we concatenate messages into a single prompt
        // System messages become instructions, user/assistant form the conversation
        var parts: [String] = []

        for message in messages {
            switch message.role {
            case .system:
                parts.append("Instructions: \(message.content)")
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
