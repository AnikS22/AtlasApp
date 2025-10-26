//
//  MemoryService.swift
//  AtlasApp
//
//  Created by Claude Code on 2025-10-25.
//  Copyright © 2025 Atlas. All rights reserved.
//

import Foundation
import CoreData
import Combine

/// Main memory and context management service
/// Coordinates between vector store, context manager, and persistence layer
@MainActor
final class MemoryService: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var currentContext: ConversationContext?
    @Published private(set) var memoryStats: MemoryServiceStatistics
    @Published private(set) var isProcessing: Bool = false

    // MARK: - Dependencies

    private let vectorStore: VectorStore
    private let contextManager: ContextManager
    private let summarizer: MemorySummarizer
    private let persistenceController: PersistenceController

    // MARK: - Configuration

    private let config: MemoryConfiguration

    // MARK: - Caching

    private var embeddingCache: NSCache<NSString, CachedEmbedding>
    private var recentQueries: LRUCache<String, [MemoryResult]>

    // MARK: - Initialization

    init(
        persistenceController: PersistenceController = .shared,
        config: MemoryConfiguration = .default
    ) {
        self.persistenceController = persistenceController
        self.config = config

        // Initialize vector store
        self.vectorStore = VectorStore(
            databaseURL: FileManager.default.documentsDirectory
                .appendingPathComponent("atlas_vectors.db"),
            embeddingDimension: config.embeddingDimension
        )

        // Initialize context manager
        self.contextManager = ContextManager(
            maxTokens: config.maxContextTokens,
            slidingWindowSize: config.slidingWindowSize
        )

        // Initialize summarizer
        self.summarizer = MemorySummarizer(
            maxSummaryTokens: config.maxSummaryTokens
        )

        // Initialize caches
        self.embeddingCache = NSCache<NSString, CachedEmbedding>()
        self.embeddingCache.countLimit = config.embeddingCacheSize

        self.recentQueries = LRUCache<String, [MemoryResult]>(capacity: 100)

        // Initialize stats
        self.memoryStats = MemoryServiceStatistics()

        // Setup background optimization
        setupBackgroundOptimization()
    }

    // MARK: - Public API

    /// Store a new memory entry with automatic embedding generation
    func store(
        query: String,
        response: String,
        metadata: MemoryMetadata? = nil
    ) async throws {
        isProcessing = true
        defer { isProcessing = false }

        let startTime = Date()

        // Generate embedding for query
        let embedding = try await generateEmbedding(for: query)

        // Create memory entry
        let entry = MemoryEntry(
            id: UUID(),
            query: query,
            response: response,
            embedding: embedding,
            metadata: metadata ?? MemoryMetadata(),
            timestamp: Date()
        )

        // Store in vector database
        try await vectorStore.insert(entry)

        // Update context manager
        await contextManager.addInteraction(query: query, response: response)

        // Update statistics
        let duration = Date().timeIntervalSince(startTime)
        memoryStats.recordStore(duration: duration)

        // Invalidate relevant caches
        recentQueries.removeAll()

        // Trigger background optimization if needed
        if memoryStats.totalEntries % config.optimizationInterval == 0 {
            Task.detached(priority: .background) { [weak self] in
                try? await self?.optimize()
            }
        }
    }

    /// Retrieve relevant memories for a query
    func retrieve(
        for query: String,
        limit: Int = 5,
        threshold: Float = 0.7
    ) async throws -> [MemoryResult] {
        // Check cache first
        if let cached = recentQueries.get(query) {
            return cached
        }

        isProcessing = true
        defer { isProcessing = false }

        let startTime = Date()

        // Generate query embedding
        let queryEmbedding = try await generateEmbedding(for: query)

        // Search vector store
        let results = try await vectorStore.search(
            embedding: queryEmbedding,
            limit: limit * 2, // Fetch more for post-filtering
            threshold: threshold
        )

        // Apply relevance scoring
        let scoredResults = results.map { result in
            MemoryResult(
                entry: result.entry,
                similarity: result.similarity,
                relevanceScore: calculateRelevanceScore(
                    similarity: result.similarity,
                    recency: result.entry.timestamp,
                    metadata: result.entry.metadata
                )
            )
        }

        // Sort by relevance and limit
        let topResults = scoredResults
            .sorted { $0.relevanceScore > $1.relevanceScore }
            .prefix(limit)
            .map { $0 }

        // Update cache
        recentQueries.set(query, value: topResults)

        // Update statistics
        let duration = Date().timeIntervalSince(startTime)
        memoryStats.recordRetrieval(duration: duration, count: topResults.count)

        return topResults
    }

    /// Get current conversation context with smart pruning
    func getCurrentContext(
        maxTokens: Int? = nil
    ) async throws -> ConversationContext {
        let limit = maxTokens ?? config.maxContextTokens

        // Get recent conversation with sliding window
        let recentContext = await contextManager.getContext(maxTokens: limit)

        // Get relevant long-term memories if space allows
        if recentContext.tokenCount < limit {
            let _ = limit - recentContext.tokenCount

            if let lastQuery = recentContext.interactions.last?.query {
                let memories = try await retrieve(
                    for: lastQuery,
                    limit: 3,
                    threshold: 0.75
                )

                // Add memories that fit in remaining space
                var additionalContext = [ContextInteraction]()
                var currentTokens = recentContext.tokenCount

                for memory in memories {
                    let memoryTokens = estimateTokens(memory.entry.query + memory.entry.response)
                    if currentTokens + memoryTokens <= limit {
                        additionalContext.append(
                            ContextInteraction(
                                query: memory.entry.query,
                                response: memory.entry.response,
                                timestamp: memory.entry.timestamp,
                                isFromMemory: true
                            )
                        )
                        currentTokens += memoryTokens
                    }
                }

                // Merge contexts
                return ConversationContext(
                    interactions: additionalContext + recentContext.interactions,
                    tokenCount: currentTokens,
                    isTruncated: recentContext.isTruncated
                )
            }
        }

        currentContext = recentContext
        return recentContext
    }

    /// Search memories using semantic search
    func search(
        query: String,
        limit: Int = 10,
        filters: MemoryFilters? = nil
    ) async throws -> [MemoryResult] {
        isProcessing = true
        defer { isProcessing = false }

        // Full-text search with FTS5
        let ftsResults = try await vectorStore.fullTextSearch(
            query: query,
            limit: limit * 2
        )

        // Vector similarity search
        let embedding = try await generateEmbedding(for: query)
        let vectorResults = try await vectorStore.search(
            embedding: embedding,
            limit: limit * 2,
            threshold: 0.5
        )

        // Combine and deduplicate results
        var combined = [UUID: MemoryResult]()

        // Add FTS results with boosted scores
        for result in ftsResults {
            let score = calculateRelevanceScore(
                similarity: result.similarity * 1.2, // Boost FTS matches
                recency: result.entry.timestamp,
                metadata: result.entry.metadata
            )
            combined[result.entry.id] = MemoryResult(
                entry: result.entry,
                similarity: result.similarity,
                relevanceScore: score
            )
        }

        // Add vector results
        for result in vectorResults {
            if let existing = combined[result.entry.id] {
                // Average the scores if duplicate
                let avgSimilarity = (existing.similarity + result.similarity) / 2
                let score = calculateRelevanceScore(
                    similarity: avgSimilarity,
                    recency: result.entry.timestamp,
                    metadata: result.entry.metadata
                )
                combined[result.entry.id] = MemoryResult(
                    entry: result.entry,
                    similarity: avgSimilarity,
                    relevanceScore: score
                )
            } else {
                let score = calculateRelevanceScore(
                    similarity: result.similarity,
                    recency: result.entry.timestamp,
                    metadata: result.entry.metadata
                )
                combined[result.entry.id] = MemoryResult(
                    entry: result.entry,
                    similarity: result.similarity,
                    relevanceScore: score
                )
            }
        }

        // Apply filters if provided
        var results = Array(combined.values)
        if let filters = filters {
            results = results.filter { filters.matches($0.entry) }
        }

        // Sort and limit
        return results
            .sorted { $0.relevanceScore > $1.relevanceScore }
            .prefix(limit)
            .map { $0 }
    }

    /// Create a summary of conversation history
    func summarizeConversation(
        maxLength: Int? = nil
    ) async throws -> ConversationSummary {
        let context = await contextManager.getFullHistory()

        let summary = try await summarizer.summarize(
            interactions: context.interactions,
            maxLength: maxLength ?? config.maxSummaryTokens
        )

        // Store summary as long-term memory
        try await store(
            query: "Conversation summary",
            response: summary.text,
            metadata: MemoryMetadata(
                category: .summary,
                importance: .high,
                tags: summary.keyTopics
            )
        )

        return summary
    }

    /// Clear conversation context (but keep long-term memories)
    func clearContext() async {
        await contextManager.clear()
        currentContext = nil
        recentQueries.removeAll()
    }

    /// Prune old or low-importance memories
    func pruneMemories(
        olderThan days: Int = 90,
        minImportance: MemoryImportance = .low
    ) async throws {
        isProcessing = true
        defer { isProcessing = false }

        let cutoffDate = Calendar.current.date(
            byAdding: .day,
            value: -days,
            to: Date()
        ) ?? Date()

        let pruned = try await vectorStore.prune(
            olderThan: cutoffDate,
            minImportance: minImportance
        )

        memoryStats.totalEntries -= pruned

        // Optimize database after pruning
        try await vectorStore.optimize()
    }

    /// Get current memory statistics
    func getStatistics() -> MemoryServiceStatistics {
        return memoryStats
    }

    // MARK: - Private Methods

    private func generateEmbedding(for text: String) async throws -> [Float] {
        // Check cache first
        let cacheKey = NSString(string: text)
        if let cached = embeddingCache.object(forKey: cacheKey) {
            return cached.embedding
        }

        // Generate new embedding (simplified - would use actual model)
        let embedding = await simpleEmbedding(for: text)

        // Cache result
        let cached = CachedEmbedding(embedding: embedding, timestamp: Date())
        embeddingCache.setObject(cached, forKey: cacheKey)

        return embedding
    }

    private func simpleEmbedding(for text: String) async -> [Float] {
        // Simplified embedding generation
        // In production, this would use the TRM model's embedding layer
        let normalized = text.lowercased()
        var embedding = [Float](repeating: 0.0, count: config.embeddingDimension)

        // Simple hash-based embedding (replace with actual model)
        for (index, char) in normalized.unicodeScalars.enumerated() {
            let pos = index % config.embeddingDimension
            embedding[pos] += Float(char.value) / 1000.0
        }

        // Normalize
        let magnitude = sqrt(embedding.map { $0 * $0 }.reduce(0, +))
        if magnitude > 0 {
            embedding = embedding.map { $0 / magnitude }
        }

        return embedding
    }

    private func calculateRelevanceScore(
        similarity: Float,
        recency: Date,
        metadata: MemoryMetadata
    ) -> Float {
        // Base score from similarity
        var score = similarity * 0.6

        // Recency bonus (decay over time)
        let daysSince = Date().timeIntervalSince(recency) / 86400
        let recencyScore = exp(-daysSince / 30.0) // 30-day half-life
        score += Float(recencyScore) * 0.2

        // Importance bonus
        score += metadata.importance.rawValue * 0.1

        // Category bonus for specific types
        if metadata.category == .important {
            score += 0.1
        }

        return min(score, 1.0)
    }

    private func estimateTokens(_ text: String) -> Int {
        // Rough estimation: ~4 characters per token
        return text.count / 4
    }

    private func setupBackgroundOptimization() {
        // Schedule periodic optimization
        Task.detached(priority: .background) { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(3600)) // Every hour
                try? await self?.optimize()
            }
        }
    }

    private func optimize() async throws {
        // Optimize vector store
        try await vectorStore.optimize()

        // Clean up old summaries
        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -30,
            to: Date()
        ) ?? Date()

        let _ = try await vectorStore.prune(
            olderThan: cutoff,
            minImportance: .low,
            category: .summary
        )

        // Update statistics
        memoryStats.lastOptimization = Date()
    }
}

// MARK: - Supporting Types

struct MemoryConfiguration {
    let embeddingDimension: Int
    let maxContextTokens: Int
    let slidingWindowSize: Int
    let maxSummaryTokens: Int
    let embeddingCacheSize: Int
    let optimizationInterval: Int

    static let `default` = MemoryConfiguration(
        embeddingDimension: 384,
        maxContextTokens: 4000,
        slidingWindowSize: 10,
        maxSummaryTokens: 500,
        embeddingCacheSize: 1000,
        optimizationInterval: 100
    )
}

struct MemoryServiceStatistics {
    var totalEntries: Int = 0
    var averageStoreTime: TimeInterval = 0
    var averageRetrievalTime: TimeInterval = 0
    var cacheHitRate: Float = 0
    var lastOptimization: Date?

    private var storeTimes: [TimeInterval] = []
    private var retrievalTimes: [TimeInterval] = []
    private var cacheHits: Int = 0
    private var cacheMisses: Int = 0

    mutating func recordStore(duration: TimeInterval) {
        totalEntries += 1
        storeTimes.append(duration)
        if storeTimes.count > 100 {
            storeTimes.removeFirst()
        }
        averageStoreTime = storeTimes.reduce(0, +) / Double(storeTimes.count)
    }

    mutating func recordRetrieval(duration: TimeInterval, count: Int) {
        retrievalTimes.append(duration)
        if retrievalTimes.count > 100 {
            retrievalTimes.removeFirst()
        }
        averageRetrievalTime = retrievalTimes.reduce(0, +) / Double(retrievalTimes.count)
    }
}

struct MemoryResult {
    let entry: MemoryEntry
    let similarity: Float
    let relevanceScore: Float
}

struct MemoryFilters {
    let categories: Set<MemoryCategory>?
    let minImportance: MemoryImportance?
    let dateRange: ClosedRange<Date>?
    let tags: Set<String>?

    func matches(_ entry: MemoryEntry) -> Bool {
        if let categories = categories, !categories.contains(entry.metadata.category) {
            return false
        }

        if let minImportance = minImportance, entry.metadata.importance.rawValue < minImportance.rawValue {
            return false
        }

        if let dateRange = dateRange, !dateRange.contains(entry.timestamp) {
            return false
        }

        if let tags = tags, tags.intersection(Set(entry.metadata.tags)).isEmpty {
            return false
        }

        return true
    }
}

// MARK: - Extensions

extension FileManager {
    var documentsDirectory: URL {
        urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}
