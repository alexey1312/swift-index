import Foundation
@testable import SwiftIndexCore
import Testing

@Suite("HybridParser Benchmark Tests")
struct HybridParserBenchmarkTests {
    @Test("Measure supportedExtensions access performance", .tags(.benchmark))
    func measureSupportedExtensionsPerformance() async throws {
        let parser = HybridParser()
        let iterations = 100_000

        print("Starting benchmark: Accessing supportedExtensions \(iterations) times")

        let clock = ContinuousClock()
        let result = try await clock.measure {
            for _ in 0 ..< iterations {
                _ = parser.supportedExtensions
            }
        }

        print("Accessing supportedExtensions took: \(result)")

        // Calculate average time per access
        let seconds = Double(result.components.attoseconds) / 1e18
        let averageTime = seconds / Double(iterations)
        print("Average time per access: \(averageTime * 1e9) ns")
    }
}

// Helper to define benchmark tag if not exists
extension Tag {
    @available(macOS 13.0, *)
    @Tag static var benchmark: Tag
}
