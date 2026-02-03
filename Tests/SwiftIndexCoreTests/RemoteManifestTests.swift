@testable import SwiftIndexCore
import XCTest

final class RemoteManifestTests: XCTestCase {
    func testRoundTripEncoding() throws {
        let manifest = RemoteManifest(
            version: 3,
            gitCommit: "abc123",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            files: [
                .init(
                    name: "chunks.db.zst",
                    size: 1_048_576,
                    compressedSize: 524_288,
                    checksum: "deadbeef"
                ),
                .init(
                    name: "vectors.usearch.zst",
                    size: 2_097_152,
                    compressedSize: 1_048_576,
                    checksum: "cafebabe"
                ),
            ]
        )

        let data = try JSONCodec.encode(manifest)
        let decoded = try JSONCodec.decode(RemoteManifest.self, from: data)

        XCTAssertEqual(decoded, manifest)
    }
}
