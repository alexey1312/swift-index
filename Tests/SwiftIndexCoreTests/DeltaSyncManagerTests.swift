@testable import SwiftIndexCore
import XCTest

final class DeltaSyncManagerTests: XCTestCase {
    func testComputeDeltaDetectsChangedAndMissingFiles() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let localManifest = RemoteManifest(
            version: 1,
            gitCommit: "abc",
            createdAt: Date(timeIntervalSince1970: 1),
            files: [
                .init(name: "chunks.db.zst", size: 10, compressedSize: 5, checksum: "aaa"),
                .init(name: "vectors.usearch.zst", size: 20, compressedSize: 10, checksum: "bbb"),
            ]
        )

        let localManifestURL = tempDirectory.appendingPathComponent("manifest.json")
        let localData = try JSONCodec.encodePrettySorted(localManifest)
        try localData.write(to: localManifestURL, options: [.atomic])

        let localFile = tempDirectory.appendingPathComponent("chunks.db.zst")
        try Data([0x01]).write(to: localFile, options: [.atomic])

        let remoteManifest = RemoteManifest(
            version: 2,
            gitCommit: "def",
            createdAt: Date(timeIntervalSince1970: 2),
            files: [
                .init(name: "chunks.db.zst", size: 10, compressedSize: 5, checksum: "aaa"),
                .init(name: "vectors.usearch.zst", size: 20, compressedSize: 10, checksum: "ccc"),
                .init(name: "vectors.mapping.json", size: 5, compressedSize: 0, checksum: "ddd"),
            ]
        )

        let manager = DeltaSyncManager()
        let delta = await manager.computeDelta(remote: remoteManifest, localCache: tempDirectory)
        let names = delta.map(\.name).sorted()

        XCTAssertEqual(names, ["vectors.mapping.json", "vectors.usearch.zst"])
    }
}
