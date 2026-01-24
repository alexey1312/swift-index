// MARK: - GeminiCLIProvider

import Foundation

/// LLM provider that uses the Gemini CLI tool.
///
/// This provider invokes the `gemini` command-line tool.
public struct GeminiCLIProvider: LLMProvider, Sendable {
    // MARK: - Properties

    public let id: String = "gemini-cli"
    public let name: String = "Gemini CLI"

    private let executablePath: String
    private let defaultModel: String?

    // MARK: - Initialization

    public init(
        executablePath: String? = nil,
        defaultModel: String? = nil
    ) {
        self.executablePath = executablePath ?? "gemini"
        self.defaultModel = defaultModel
    }

    // MARK: - LLMProvider

    public func isAvailable() async -> Bool {
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["which", executablePath]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    public func complete(
        messages: [LLMMessage],
        model: String?,
        timeout: TimeInterval
    ) async throws -> String {
        let prompt = buildPrompt(from: messages)
        var arguments = ["prompt", prompt]

        if let modelName = model ?? defaultModel {
            arguments.append(contentsOf: ["--model", modelName])
        }

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

        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func buildPrompt(from messages: [LLMMessage]) -> String {
        messages.map { "\($0.role): \($0.content)" }.joined(separator: "\n\n")
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
            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if process.isRunning { process.terminate() }
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

            let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            continuation.resume(returning: ProcessResult(
                exitCode: process.terminationStatus,
                stdout: stdout,
                stderr: stderr
            ))
        }
    }
}

private struct ProcessResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}
