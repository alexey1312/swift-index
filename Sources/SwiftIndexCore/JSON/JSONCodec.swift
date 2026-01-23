import Foundation
import YYJSON

// MARK: - JSON Codec Adapter

/// Provides fast JSON encoding/decoding using YYJSON with RFC 8259 strict mode.
///
/// This adapter centralizes JSON codec configuration and provides drop-in
/// replacements for Foundation's JSONEncoder/JSONDecoder with significantly
/// better performance and lower memory usage.
///
/// Usage:
/// ```swift
/// let data = try JSONCodec.encode(value)
/// let value = try JSONCodec.decode(MyType.self, from: data)
/// ```
///
/// Note: YYJSONEncoder does not support sorted keys directly. For deterministic
/// output with sorted keys, use `JSONCodec.serialize()` with `.sortedKeys` option
/// or the two-step `encodeSorted()` method.
public enum JSONCodec {
    // MARK: - Factory Methods

    /// Create a new encoder with default configuration.
    public static func makeEncoder() -> YYJSONEncoder {
        YYJSONEncoder()
    }

    /// Create a new encoder with pretty-printed output.
    public static func makePrettyEncoder() -> YYJSONEncoder {
        var encoder = YYJSONEncoder()
        encoder.writeOptions = [.prettyPrinted]
        return encoder
    }

    /// Create a new decoder.
    public static func makeDecoder() -> YYJSONDecoder {
        YYJSONDecoder()
    }

    // MARK: - Convenience Methods

    /// Encode a value to JSON data.
    public static func encode(_ value: some Encodable) throws -> Data {
        try makeEncoder().encode(value)
    }

    /// Encode a value to pretty-printed JSON data.
    public static func encodePretty(_ value: some Encodable) throws -> Data {
        try makePrettyEncoder().encode(value)
    }

    /// Encode a value to JSON data with sorted keys for deterministic output.
    ///
    /// This uses a two-step process: encode to JSON, then re-serialize with sorted keys.
    /// Use this only when deterministic output is required (e.g., for hashing or diffs).
    public static func encodeSorted(_ value: some Encodable) throws -> Data {
        let data = try makeEncoder().encode(value)
        let object = try YYJSONSerialization.jsonObject(with: data)
        return try YYJSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    /// Encode a value to pretty-printed JSON data with sorted keys.
    public static func encodePrettySorted(_ value: some Encodable) throws -> Data {
        let data = try makeEncoder().encode(value)
        let object = try YYJSONSerialization.jsonObject(with: data)
        return try YYJSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    /// Decode a value from JSON data.
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try makeDecoder().decode(type, from: data)
    }
}

// MARK: - Serialization Helpers

public extension JSONCodec {
    /// Options for JSON serialization (mirrors YYJSONSerialization.WritingOptions).
    typealias WritingOptions = YYJSONSerialization.WritingOptions

    /// Convert a dictionary or array to JSON data.
    static func serialize(_ object: Any, options: WritingOptions = []) throws -> Data {
        try YYJSONSerialization.data(withJSONObject: object, options: options)
    }

    /// Parse JSON data to a dictionary or array.
    static func deserialize(_ data: Data) throws -> Any {
        try YYJSONSerialization.jsonObject(with: data)
    }
}
