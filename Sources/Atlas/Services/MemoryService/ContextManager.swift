//
//  ContextManager.swift
//  AtlasApp
//
//  Created by Claude Code on 2025-10-25.
//  Copyright © 2025 Atlas. All rights reserved.
//

import Foundation

/// Manages conversation context with sliding window and smart pruning
actor ContextManager {

    // MARK: - Properties

    private var interactions: [ContextInteraction] = []
    private let maxTokens: Int
    private let slidingWindowSize: Int

    private var currentTokenCount: Int = 0

    // MARK: - Initialization

    init(maxTokens: Int, slidingWindowSize: Int) {
        self.maxTokens = maxTokens
        self.slidingWindowSize = slidingWindowSize
    }

    // MARK: - Public API

    /// Add a new interaction to the context
    func addInteraction(query: String, response: String) {
        let interaction = ContextInteraction(
            query: query,
            response: response,
            timestamp: Date(),
            isFromMemory: false
        )

        interactions.append(interaction)
        currentTokenCount += interaction.tokenCount

        // Prune if necessary
        pruneIfNeeded()
    }

    /// Get current context within token limit
    func getContext(maxTokens: Int? = nil) -> ConversationContext {
        let limit = maxTokens ?? self.maxTokens

        var selectedInteractions: [ContextInteraction] = []
        var tokenCount = 0
        var wasTruncated = false

        // Start from most recent and work backwards
        for interaction in interactions.reversed() {
            let newTokenCount = tokenCount + interaction.tokenCount

            if newTokenCount <= limit {
                selectedInteractions.insert(interaction, at: 0)
                tokenCount = newTokenCount
            } else {
                wasTruncated = true
                break
            }
        }

        return ConversationContext(
            interactions: selectedInteractions,
            tokenCount: tokenCount,
            isTruncated: wasTruncated
        )
    }

    /// Get full conversation history (no token limit)
    func getFullHistory() -> ConversationContext {
        return ConversationContext(
            interactions: interactions,
            tokenCount: currentTokenCount,
            isTruncated: false
        )
    }

    /// Get recent interactions using sliding window
    func getRecentWindow() -> ConversationContext {
        let recent = interactions.suffix(slidingWindowSize).map { $0 }
        let tokenCount = recent.reduce(0) { $0 + $1.tokenCount }

        return ConversationContext(
            interactions: recent,
            tokenCount: tokenCount,
            isTruncated: interactions.count > slidingWindowSize
        )
    }

    /// Clear all context
    func clear() {
        interactions.removeAll()
        currentTokenCount = 0
    }

    /// Remove old interactions beyond sliding window
    func pruneOld(keepCount: Int? = nil) {
        let keep = keepCount ?? slidingWindowSize

        if interactions.count > keep {
            let removeCount = interactions.count - keep
            let removed = interactions.prefix(removeCount)

            currentTokenCount -= removed.reduce(0) { $0 + $1.tokenCount }
            interactions.removeFirst(removeCount)
        }
    }

    /// Get context summary for specific time range
    func getContextForDateRange(_ range: ClosedRange<Date>) -> ConversationContext {
        let filtered = interactions.filter { range.contains($0.timestamp) }
        let tokenCount = filtered.reduce(0) { $0 + $1.tokenCount }

        return ConversationContext(
            interactions: filtered,
            tokenCount: tokenCount,
            isTruncated: false
        )
    }

    /// Get statistics about current context
    func getStatistics() -> ContextStatistics {
        return ContextStatistics(
            totalInteractions: interactions.count,
            totalTokens: currentTokenCount,
            averageTokensPerInteraction: interactions.isEmpty ? 0 : currentTokenCount / interactions.count,
            oldestTimestamp: interactions.first?.timestamp,
            newestTimestamp: interactions.last?.timestamp,
            memoryInteractions: interactions.filter { $0.isFromMemory }.count
        )
    }

    // MARK: - Private Methods

    private func pruneIfNeeded() {
        // Remove oldest interactions if we exceed token limit
        while currentTokenCount > maxTokens && !interactions.isEmpty {
            let removed = interactions.removeFirst()
            currentTokenCount -= removed.tokenCount
        }

        // Keep only sliding window size for memory efficiency
        if interactions.count > slidingWindowSize * 2 {
            let removeCount = interactions.count - slidingWindowSize
            let removed = interactions.prefix(removeCount)

            currentTokenCount -= removed.reduce(0) { $0 + $1.tokenCount }
            interactions.removeFirst(removeCount)
        }
    }

    private func estimateTokens(_ text: String) -> Int {
        // Rough estimation: ~4 characters per token
        // This should be replaced with actual tokenizer
        return max(1, text.count / 4)
    }
}

// MARK: - Supporting Types

struct ContextInteraction: Codable, Identifiable {
    let id: UUID
    let query: String
    let response: String
    let timestamp: Date
    let isFromMemory: Bool

    var tokenCount: Int {
        // Estimate tokens for query + response
        (query.count + response.count) / 4
    }

    init(
        id: UUID = UUID(),
        query: String,
        response: String,
        timestamp: Date,
        isFromMemory: Bool
    ) {
        self.id = id
        self.query = query
        self.response = response
        self.timestamp = timestamp
        self.isFromMemory = isFromMemory
    }
}

struct ConversationContext: Codable {
    let interactions: [ContextInteraction]
    let tokenCount: Int
    let isTruncated: Bool

    var isEmpty: Bool {
        interactions.isEmpty
    }

    var interactionCount: Int {
        interactions.count
    }

    /// Format context as a string for prompt inclusion
    func formatForPrompt() -> String {
        return interactions.map { interaction in
            """
            User: \(interaction.query)
            Assistant: \(interaction.response)
            """
        }.joined(separator: "\n\n")
    }

    /// Get summary of context
    func getSummary() -> String {
        let count = interactions.count
        let tokens = tokenCount
        let timespan = getTimespan()

        return "Context: \(count) interactions, \(tokens) tokens, \(timespan)"
    }

    private func getTimespan() -> String {
        guard let oldest = interactions.first?.timestamp,
              let newest = interactions.last?.timestamp else {
            return "unknown timespan"
        }

        let interval = newest.timeIntervalSince(oldest)
        let hours = Int(interval / 3600)
        let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

struct ContextStatistics {
    let totalInteractions: Int
    let totalTokens: Int
    let averageTokensPerInteraction: Int
    let oldestTimestamp: Date?
    let newestTimestamp: Date?
    let memoryInteractions: Int

    var percentageFromMemory: Double {
        guard totalInteractions > 0 else { return 0 }
        return Double(memoryInteractions) / Double(totalInteractions) * 100
    }
}

struct ConversationSummary {
    let text: String
    let keyTopics: [String]
    let tokenCount: Int
    let originalInteractionCount: Int
    let compressionRatio: Double
}
