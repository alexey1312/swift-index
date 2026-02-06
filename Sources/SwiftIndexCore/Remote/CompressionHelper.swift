import Foundation
import zstd

public enum CompressionHelper {
    public static func compressFile(
        source: URL,
        destination: URL,
        level: Int = 3
    ) throws {
        try ensureParentDirectory(for: destination)
        try ZStd.compress(from: source, to: destination, compressionLevel: level, threads: 4)
    }

    public static func decompressFile(
        source: URL,
        destination: URL
    ) throws {
        try ensureParentDirectory(for: destination)
        guard let input = InputStream(url: source) else {
            throw RemoteStorageError.ioFailure(
                underlying: NSError(domain: "CompressionHelper", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to open input stream for \(source.path)",
                ])
            )
        }
        guard let output = OutputStream(url: destination, append: false) else {
            throw RemoteStorageError.ioFailure(
                underlying: NSError(domain: "CompressionHelper", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to open output stream for \(destination.path)",
                ])
            )
        }

        try ZStd.decompress(src: input, dst: output)
    }

    private static func ensureParentDirectory(for destination: URL) throws {
        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
