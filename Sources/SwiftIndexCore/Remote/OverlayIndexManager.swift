import Foundation

public actor OverlayIndexManager {
    public let localIndex: IndexManager
    public let remoteIndex: IndexManager?
    private let searchEngine: HybridSearchEngine

    public init(
        localIndex: IndexManager,
        remoteIndex: IndexManager?,
        embeddingProvider: any EmbeddingProvider,
        rrfK: Int = 60
    ) async {
        self.localIndex = localIndex
        self.remoteIndex = remoteIndex

        let localChunkStore = await localIndex.chunkStore
        let localVectorStore = await localIndex.vectorStore

        if let remoteIndex {
            let remoteChunkStore = await remoteIndex.chunkStore
            let remoteVectorStore = await remoteIndex.vectorStore
            searchEngine = HybridSearchEngine(
                chunkStore: localChunkStore,
                vectorStore: localVectorStore,
                embeddingProvider: embeddingProvider,
                remoteChunkStore: remoteChunkStore,
                remoteVectorStore: remoteVectorStore,
                rrfK: rrfK
            )
        } else {
            searchEngine = HybridSearchEngine(
                chunkStore: localChunkStore,
                vectorStore: localVectorStore,
                embeddingProvider: embeddingProvider,
                rrfK: rrfK
            )
        }
    }

    public func search(query: String, options: SearchOptions) async throws -> [SearchResult] {
        try await searchEngine.search(query: query, options: options)
    }

    public static func loadRemoteIndexIfAvailable(
        cacheDirectory: URL,
        dimension: Int
    ) async throws -> IndexManager? {
        let chunksPath = cacheDirectory.appendingPathComponent("chunks.db").path
        let vectorsPath = cacheDirectory.appendingPathComponent("vectors.usearch").path
        let mappingPath = cacheDirectory.appendingPathComponent("vectors.usearch.mapping").path

        let fm = FileManager.default
        guard fm.fileExists(atPath: chunksPath),
              fm.fileExists(atPath: vectorsPath),
              fm.fileExists(atPath: mappingPath)
        else {
            return nil
        }

        let index = try IndexManager(
            directory: cacheDirectory.path,
            dimension: dimension,
            config: IndexManagerConfig(readOnly: true, autoSave: false)
        )
        try await index.load()
        return index
    }
}
