// MARK: - SwiftIndex CLI

import ArgumentParser
import Foundation
import SwiftIndexCore
import SwiftIndexMCP

@main
struct SwiftIndex: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swiftindex",
        abstract: "Semantic code search for Swift codebases",
        version: "0.1.0",
        subcommands: [
            // TODO: Add subcommands in Phase 4
        ]
    )
}
