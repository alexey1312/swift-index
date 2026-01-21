// MARK: - Providers Command

import ArgumentParser
import Foundation
import Logging
import SwiftIndexCore

/// Command to list available embedding providers and their status.
///
/// Usage:
///   swiftindex providers
///   swiftindex providers --verbose
struct ProvidersCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "providers",
        abstract: "List available embedding providers and their status",
        discussion: """
        Shows all registered embedding providers with their availability
        status, dimensions, and configuration requirements.

        Providers are checked for availability based on hardware support
        (e.g., Apple Silicon for MLX), network connectivity, and API key
        configuration.
        """
    )

    // MARK: - Options

    @Option(
        name: .shortAndLong,
        help: "Path to configuration file"
    )
    var config: String?

    @Flag(
        name: .shortAndLong,
        help: "Enable verbose debug output"
    )
    var verbose: Bool = false

    // MARK: - Execution

    mutating func run() async throws {
        let logger = CLIUtils.makeLogger(verbose: verbose)
        logger.info("Listing embedding providers")

        // Load configuration
        let configuration = try CLIUtils.loadConfig(from: config, logger: logger)

        print("Embedding Providers")
        print("===================")
        print("")

        // TODO: Replace with actual provider registry
        // let registry = EmbeddingProviderRegistry(config: configuration)
        // let providers = await registry.allProviders()

        // Placeholder provider information
        let providers: [(id: String, name: String, dimension: Int, available: Bool, notes: String)] = [
            (
                id: "mlx-minilm",
                name: "MLX MiniLM-L6",
                dimension: 384,
                available: true,
                notes: "Local, Apple Silicon required"
            ),
            (
                id: "mlx-bge-small",
                name: "MLX BGE-Small",
                dimension: 384,
                available: true,
                notes: "Local, Apple Silicon required"
            ),
            (
                id: "voyage-code-3",
                name: "Voyage Code 3",
                dimension: 1024,
                available: configuration.voyageAPIKey != nil,
                notes: "Cloud, API key required"
            ),
            (
                id: "openai-ada-002",
                name: "OpenAI Ada 002",
                dimension: 1536,
                available: configuration.openAIAPIKey != nil,
                notes: "Cloud, API key required"
            ),
        ]

        for provider in providers {
            let status = provider.available ? "[OK]" : "[--]"
            print("\(status) \(provider.id)")
            print("    Name: \(provider.name)")
            print("    Dimension: \(provider.dimension)")
            print("    Notes: \(provider.notes)")
            print("")
        }

        // Show current configuration
        print("Current Configuration")
        print("---------------------")
        print("Provider: \(configuration.embeddingProvider)")
        print("Model: \(configuration.embeddingModel)")
        print("Dimension: \(configuration.embeddingDimension)")

        logger.info("Provider listing completed")
    }
}
