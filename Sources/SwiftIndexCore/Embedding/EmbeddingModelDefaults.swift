// MARK: - EmbeddingModelDefaults

import Foundation

/// Default model and dimension for each local embedding provider.
///
/// `Config` carries one `embeddingModel` for every provider, and its default is the
/// swift-embeddings model. Under `auto` the same config can select MLX, which needs
/// a Hugging Face repo ID, so each provider maps a foreign short name onto its own
/// default.
public enum EmbeddingModelDefaults {
    public static let mlxModel = "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ"
    public static let mlxDimension = 1024

    /// Cloud providers `auto` tries, in order, with their default model and dimension.
    ///
    /// A cloud provider embeds a whole project in seconds, where a local model can
    /// take minutes. `auto` uses the first one that has an API key.
    public static let cloudPreference: [(provider: String, model: String, dimension: Int)] = [
        ("openai", "text-embedding-3-small", 1536),
        ("voyage", "voyage-code-2", 1024),
        ("gemini", "text-embedding-004", 768),
    ]

    /// Printed when `auto` falls back to a local model because no key is set.
    public static let cloudKeyHint = """
    Tip: no cloud API key is set, so indexing uses a local embedding model, which is \
    slow on large projects. Set OPENAI_API_KEY, VOYAGE_API_KEY or GEMINI_API_KEY to \
    index with a cloud provider. An existing index changes provider with --force.
    """

    /// Default model for a provider identifier, or `nil` when it has no local default.
    public static func model(for provider: String) -> String? {
        switch provider.lowercased() {
        case "mlx":
            mlxModel
        case "swift", "swift-embeddings", "swiftembeddings":
            SwiftEmbeddingsProvider.Model.miniLM.rawValue
        default:
            nil
        }
    }

    /// Model and dimension MLX should use for a configured model.
    ///
    /// A value without `/` is not a Hugging Face repo (for example the shared default
    /// `all-MiniLM-L6-v2`), so MLX uses its own default instead.
    static func mlxSelection(configuredModel: String, configuredDimension: Int) -> (model: String, dimension: Int) {
        guard configuredModel.contains("/") else {
            return (mlxModel, mlxDimension)
        }
        return (configuredModel, configuredDimension)
    }

    /// swift-embeddings model for a configured name, matched by short name or repo ID.
    static func swiftEmbeddingsModel(for configuredModel: String) -> SwiftEmbeddingsProvider.Model? {
        let name = configuredModel.lowercased()
        return SwiftEmbeddingsProvider.Model.allCases.first {
            $0.rawValue.lowercased() == name || $0.huggingFaceId.lowercased() == name
        }
    }
}

/// Public view of MLX runtime readiness for targets outside SwiftIndexCore.
public enum MLXSupport {
    /// Whether this binary can run MLX: Apple Silicon and a Metal library beside it.
    ///
    /// The Metal toolchain is not needed here. It only builds the library, and
    /// release artifacts already ship it.
    public static var isRuntimeAvailable: Bool {
        #if arch(arm64)
            MLXRuntime.isMetalLibraryAvailable
        #else
            false
        #endif
    }
}
