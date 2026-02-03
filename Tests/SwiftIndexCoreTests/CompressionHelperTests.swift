@testable import SwiftIndexCore
import XCTest

final class CompressionHelperTests: XCTestCase {
    func testCompressAndDecompressFile() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let sourceURL = tempDirectory.appendingPathComponent("source.txt")
        let compressedURL = tempDirectory.appendingPathComponent("source.txt.zst")
        let decompressedURL = tempDirectory.appendingPathComponent("source.out")

        let payload = Data(repeating: 0xAB, count: 64 * 1024)
        try payload.write(to: sourceURL)

        try CompressionHelper.compressFile(source: sourceURL, destination: compressedURL, level: 1)
        try CompressionHelper.decompressFile(source: compressedURL, destination: decompressedURL)

        let decoded = try Data(contentsOf: decompressedURL)
        XCTAssertEqual(decoded, payload)
    }
}
