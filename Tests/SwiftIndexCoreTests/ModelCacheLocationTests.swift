// MARK: - ModelCacheLocationTests

import Foundation
@testable import SwiftIndexCore
import Testing

@Suite("ModelCacheLocation")
struct ModelCacheLocationTests {
    private let home = URL(fileURLWithPath: "/Users/tester")

    @Test("Defaults to ~/.cache/huggingface, not iCloud-synced Documents")
    func defaultsToCacheDirectory() {
        let base = ModelCacheLocation.configuredBase(environment: [:], homeDirectory: home)

        #expect(base.path == "/Users/tester/.cache/huggingface")
        #expect(!base.path.contains("Documents"))
    }

    @Test("XDG_CACHE_HOME relocates the cache")
    func honorsXDGCacheHome() {
        let base = ModelCacheLocation.configuredBase(
            environment: ["XDG_CACHE_HOME": "/Volumes/Big/cache"],
            homeDirectory: home
        )

        #expect(base.path == "/Volumes/Big/cache/huggingface")
    }

    @Test("Explicit override wins over XDG_CACHE_HOME")
    func overrideWins() {
        let base = ModelCacheLocation.configuredBase(
            environment: [
                ModelCacheLocation.overrideVariable: "/Volumes/Models",
                "XDG_CACHE_HOME": "/Volumes/Big/cache",
            ],
            homeDirectory: home
        )

        #expect(base.path == "/Volumes/Models")
    }

    @Test("Empty environment values are ignored")
    func emptyValuesIgnored() {
        let base = ModelCacheLocation.configuredBase(
            environment: [ModelCacheLocation.overrideVariable: "", "XDG_CACHE_HOME": ""],
            homeDirectory: home
        )

        #expect(base.path == "/Users/tester/.cache/huggingface")
    }

    @Test("Tilde in an override expands to the home directory")
    func expandsTilde() {
        let base = ModelCacheLocation.configuredBase(
            environment: [ModelCacheLocation.overrideVariable: "~/models"],
            homeDirectory: home
        )

        #expect(base.path == "/Users/tester/models")
    }

    @Test("Legacy base is the HubApi default under Documents")
    func legacyBaseIsDocuments() {
        #expect(ModelCacheLocation.legacyBase(homeDirectory: home).path == "/Users/tester/Documents/huggingface")
    }
}
