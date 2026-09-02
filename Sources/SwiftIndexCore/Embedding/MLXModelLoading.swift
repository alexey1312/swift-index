// MARK: - MLXModelLoading

import Foundation
import Hub
import MLXLMCommon
import Tokenizers

/// Bridges swift-transformers' Hub client and tokenizers into the `Downloader`
/// and `TokenizerLoader` protocols that mlx-swift-lm 3.x requires.
///
/// mlx-swift-lm 3.x no longer bundles a Hugging Face integration; callers supply
/// their own. Routing downloads through `HubApi` with `ModelCacheLocation.base`
/// keeps MLX models in the same on-disk location as every other provider, so
/// `HubModelManager.isRepoCached` keeps answering correctly for MLX model ids.
enum MLXModelLoading {
    /// Downloads model snapshots via swift-transformers' `HubApi`.
    static var downloader: any Downloader {
        HubApiDownloader(hub: HubApi(downloadBase: ModelCacheLocation.base))
    }

    /// Loads tokenizers via swift-transformers' `AutoTokenizer`.
    static var tokenizerLoader: any TokenizerLoader {
        TransformersTokenizerLoader()
    }
}

// MARK: - HubApiDownloader

/// `Downloader` backed by swift-transformers' `HubApi`.
struct HubApiDownloader: Downloader {
    let hub: HubApi

    func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        try await hub.snapshot(
            from: Hub.Repo(id: id),
            revision: revision ?? "main",
            matching: patterns,
            progressHandler: progressHandler
        )
    }
}

// MARK: - TransformersTokenizerLoader

/// `TokenizerLoader` backed by swift-transformers' `AutoTokenizer`.
struct TransformersTokenizerLoader: TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let upstream = try await AutoTokenizer.from(modelFolder: directory)
        return TransformersTokenizerBridge(upstream: upstream)
    }
}

/// Adapts a swift-transformers tokenizer to the mlx-swift-lm `Tokenizer` protocol.
struct TransformersTokenizerBridge: MLXLMCommon.Tokenizer {
    let upstream: any Tokenizers.Tokenizer

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    var bosToken: String? {
        upstream.bosToken
    }

    var eosToken: String? {
        upstream.eosToken
    }

    var unknownToken: String? {
        upstream.unknownToken
    }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(
                messages: messages,
                tools: tools,
                additionalContext: additionalContext
            )
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}
