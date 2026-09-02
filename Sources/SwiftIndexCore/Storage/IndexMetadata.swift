// MARK: - IndexMetadata

import Foundation

/// Facts about how an index was built, stored alongside it as `meta.json`.
///
/// The vector store already refuses to load an index whose dimension does not match
/// the current provider, but it can only report raw numbers. Recording *which*
/// provider and model produced the index turns an opaque `dimensionMismatch` into an
/// actionable message, and pins `auto` selections so an index does not silently mean
/// something different on another machine.
public struct IndexMetadata: Codable, Sendable, Equatable {
    /// Format version of this sidecar.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var providerID: String
    public var modelID: String
    public var dimension: Int
    public var createdAt: Date
    public var lastIndexedAt: Date
    public var swiftindexVersion: String

    public init(
        schemaVersion: Int = IndexMetadata.currentSchemaVersion,
        providerID: String,
        modelID: String,
        dimension: Int,
        createdAt: Date = Date(),
        lastIndexedAt: Date = Date(),
        swiftindexVersion: String
    ) {
        self.schemaVersion = schemaVersion
        self.providerID = providerID
        self.modelID = modelID
        self.dimension = dimension
        self.createdAt = createdAt
        self.lastIndexedAt = lastIndexedAt
        self.swiftindexVersion = swiftindexVersion
    }

    // MARK: - Persistence

    /// File name of the sidecar inside the index directory.
    public static let fileName = "meta.json"

    /// Path of the sidecar for an index directory.
    public static func path(inIndexDirectory directory: String) -> String {
        (directory as NSString).appendingPathComponent(fileName)
    }

    /// Loads metadata for an index directory.
    ///
    /// - Returns: The metadata, or `nil` when the index predates this sidecar.
    public static func load(fromIndexDirectory directory: String) -> IndexMetadata? {
        let path = path(inIndexDirectory: directory)
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? JSONCodec.makeDecoder().decode(IndexMetadata.self, from: data)
    }

    /// Writes metadata for an index directory.
    public func save(toIndexDirectory directory: String) throws {
        let data = try JSONCodec.encodePretty(self)
        try data.write(to: URL(fileURLWithPath: Self.path(inIndexDirectory: directory)), options: .atomic)
    }

    // MARK: - Compatibility

    /// Describes why a stored index is incompatible with the current selection, if it is.
    ///
    /// - Parameters:
    ///   - resolvedProviderID: Provider the current configuration resolves to.
    ///   - resolvedModelID: Model the current configuration resolves to.
    ///   - resolvedDimension: Dimension of the resolved provider.
    /// - Returns: A human-readable explanation, or `nil` when compatible.
    public func incompatibilityReason(
        providerID resolvedProviderID: String,
        modelID resolvedModelID: String,
        dimension resolvedDimension: Int
    ) -> String? {
        // Dimension is the only difference that actually breaks the vector index; a
        // model change at the same dimension degrades quality but still searches, so
        // it is reported as a mismatch only when the dimension also moved.
        guard dimension != resolvedDimension else { return nil }

        return """
        Index was built with \(providerID)/\(modelID) (\(dimension)-dim), but the current \
        configuration resolves to \(resolvedProviderID)/\(resolvedModelID) (\(resolvedDimension)-dim).

        Rebuild the index to use the new provider:
          swiftindex index --force
        """
    }
}
