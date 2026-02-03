import ArgumentParser
import Crypto
import Foundation
import Logging
import SwiftIndexCore
import TOML

enum RemoteCLI {
    static func loadConfigOrThrow(
        configPath: String?,
        logger: Logger
    ) throws -> Config {
        do {
            return try CLIUtils.loadConfig(
                from: configPath,
                projectDirectory: FileManager.default.currentDirectoryPath,
                logger: logger,
                requireInitialization: true
            )
        } catch ConfigError.notInitialized {
            print("Run 'swiftindex init' first to create a configuration file.")
            print("")
            print("Example:")
            print("  swiftindex init              # Interactive setup")
            print("  swiftindex init --provider mlx  # Use MLX defaults")
            throw ExitCode.failure
        }
    }

    static func resolveProjectPath(_ path: String) throws -> String {
        let resolved = CLIUtils.resolvePath(path)
        guard FileManager.default.fileExists(atPath: resolved) else {
            throw ValidationError("Path does not exist: \(resolved)")
        }
        return resolved
    }

    static func requireRemoteConfig(_ config: Config) throws -> RemoteConfig {
        guard let remote = config.remote, remote.enabled else {
            throw ValidationError(
                "Remote storage not configured. Run 'swiftindex remote config' first."
            )
        }
        return remote
    }

    static func makeProvider(from remote: RemoteConfig) throws -> RemoteStorageProvider {
        try RemoteStorageProviderFactory.makeProvider(config: remote)
    }

    static func indexDirectory(for repoPath: String, config: Config) -> URL {
        let indexPath = (repoPath as NSString).appendingPathComponent(config.indexPath)
        return URL(fileURLWithPath: indexPath, isDirectory: true)
    }

    static func cacheDirectory(for repoPath: String, config: Config) -> URL {
        let cacheRoot = CLIUtils.resolvePath(config.cachePath)
        let rootURL = URL(fileURLWithPath: cacheRoot, isDirectory: true)
            .appendingPathComponent("shared", isDirectory: true)
        let cachePaths = RemoteCachePaths(root: rootURL)
        return cachePaths.cacheDirectory(forRepoPath: URL(fileURLWithPath: repoPath, isDirectory: true))
    }

    static func loadLocalManifest(from cacheDirectory: URL) throws -> RemoteManifest? {
        let manifestURL = cacheDirectory.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: manifestURL)
        return try JSONCodec.decode(RemoteManifest.self, from: data)
    }

    static func saveLocalManifest(_ manifest: RemoteManifest, to cacheDirectory: URL) throws {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let manifestURL = cacheDirectory.appendingPathComponent("manifest.json")
        let data = try JSONCodec.encodePrettySorted(manifest)
        try data.write(to: manifestURL, options: [.atomic])
    }

    static func fileSize(at url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attributes[.size] as? NSNumber {
            return size.int64Value
        }
        return 0
    }

    static func checksum(at url: URL) throws -> String {
        guard let stream = InputStream(url: url) else {
            throw RemoteStorageError.ioFailure(
                underlying: NSError(domain: "RemoteCLI", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to open file: \(url.path)",
                ])
            )
        }
        stream.open()
        defer { stream.close() }

        var hasher = SHA256()
        let bufferSize = 1024 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read < 0 {
                throw RemoteStorageError.ioFailure(
                    underlying: stream.streamError ?? NSError(domain: "RemoteCLI", code: 2, userInfo: nil)
                )
            }
            if read == 0 {
                break
            }
            hasher.update(data: Data(bytes: buffer, count: read))
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func gitCommit(for repoPath: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", repoPath, "rev-parse", "HEAD"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    static func formatDuration(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        let minutes = seconds / 60
        let remaining = seconds % 60
        if minutes > 0 {
            return "\(minutes)m \(remaining)s"
        }
        return "\(remaining)s"
    }
}
