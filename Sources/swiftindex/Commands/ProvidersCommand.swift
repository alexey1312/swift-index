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
        let configuration = try CLIUtils.loadConfig(
            from: config,
            logger: logger,
            requireInitialization: false
        )

        print("Embedding Providers")
        print("===================")
        print("")

        // Use the provider registry
        let registry = EmbeddingProviderRegistry(config: configuration)
        let providers = await registry.allProviders()

        for provider in providers {
            let status = provider.isAvailable ? "[OK]" : "[--]"
            print("\(status) \(provider.id)")
            print("    Name: \(provider.name)")
            print("    Dimension: \(provider.dimension)")
            if let modelId = provider.modelId {
                print("    Model: \(modelId)")
            }
            print("    Type: \(provider.providerType.rawValue)")
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
