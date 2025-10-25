//
//  MemorySummarizer.swift
//  AtlasApp
//
//  Created by Claude Code on 2025-10-25.
//  Copyright © 2025 Atlas. All rights reserved.
//

import Foundation

/// Creates compressed summaries of conversation history
actor MemorySummarizer {

    // MARK: - Properties

    private let maxSummaryTokens: Int

    // MARK: - Initialization

    init(maxSummaryTokens: Int) {
        self.maxSummaryTokens = maxSummaryTokens
    }

    // MARK: - Public API

    /// Summarize a list of interactions
    func summarize(
        interactions: [ContextInteraction],
        maxLength: Int? = nil
    ) async throws -> ConversationSummary {
        let limit = maxLength ?? maxSummaryTokens

        guard !interactions.isEmpty else {
            return ConversationSummary(
                text: "",
                keyTopics: [],
                tokenCount: 0,
                originalInteractionCount: 0,
                compressionRatio: 0
            )
        }

        // Extract key topics
        let topics = extractKeyTopics(from: interactions)

        // Create summary based on strategy
        let summaryText = if interactions.count <= 3 {
            // For short conversations, use full context
            await createFullSummary(interactions: interactions)
        } else {
            // For longer conversations, use extractive summarization
            await createExtractedSummary(interactions: interactions, limit: limit)
        }

        let tokenCount = estimateTokens(summaryText)
        let originalTokens = interactions.reduce(0) { $0 + $1.tokenCount }
        let compressionRatio = Double(tokenCount) / Double(max(1, originalTokens))

        return ConversationSummary(
            text: summaryText,
            keyTopics: topics,
            tokenCount: tokenCount,
            originalInteractionCount: interactions.count,
            compressionRatio: compressionRatio
        )
    }

    /// Summarize conversation by time period
    func summarizeByPeriod(
        interactions: [ContextInteraction],
        period: SummarizationPeriod
    ) async throws -> [PeriodSummary] {
        let grouped = groupByPeriod(interactions, period: period)

        var summaries: [PeriodSummary] = []

        for (periodStart, periodInteractions) in grouped.sorted(by: { $0.key < $1.key }) {
            let summary = try await summarize(interactions: periodInteractions)

            summaries.append(
                PeriodSummary(
                    period: period,
                    startDate: periodStart,
                    summary: summary
                )
            )
        }

        return summaries
    }

    // MARK: - Private Methods

    private func createFullSummary(interactions: [ContextInteraction]) async -> String {
        var summary = ""

        for (index, interaction) in interactions.enumerated() {
            summary += "[\(index + 1)] "
            summary += "Q: \(interaction.query)\n"
            summary += "A: \(interaction.response)\n"

            if index < interactions.count - 1 {
                summary += "\n"
            }
        }

        return summary
    }

    private func createExtractedSummary(
        interactions: [ContextInteraction],
        limit: Int
    ) async -> String {
        // Score each interaction by importance
        let scored = interactions.map { interaction in
            (
                interaction: interaction,
                score: calculateImportanceScore(interaction, in: interactions)
            )
        }

        // Sort by score and select top ones that fit in limit
        let sorted = scored.sorted { $0.score > $1.score }

        var selectedInteractions: [ContextInteraction] = []
        var currentTokens = 0

        for item in sorted {
            let tokens = item.interaction.tokenCount
            if currentTokens + tokens <= limit {
                selectedInteractions.append(item.interaction)
                currentTokens += tokens
            }
        }

        // Sort selected by chronological order
        selectedInteractions.sort { $0.timestamp < $1.timestamp }

        // Create summary
        var summary = "Conversation Summary (\(interactions.count) interactions):\n\n"

        for (index, interaction) in selectedInteractions.enumerated() {
            summary += "[\(index + 1)] "

            // Compress if needed
            let compressedQuery = compress(interaction.query, maxTokens: 50)
            let compressedResponse = compress(interaction.response, maxTokens: 100)

            summary += "Q: \(compressedQuery)\n"
            summary += "A: \(compressedResponse)\n"

            if index < selectedInteractions.count - 1 {
                summary += "\n"
            }
        }

        if selectedInteractions.count < interactions.count {
            let omitted = interactions.count - selectedInteractions.count
            summary += "\n\n[... \(omitted) less important interactions omitted ...]"
        }

        return summary
    }

    private func calculateImportanceScore(
        _ interaction: ContextInteraction,
        in context: [ContextInteraction]
    ) -> Double {
        var score: Double = 0.5 // Base score

        // Recency bonus (more recent = higher score)
        if let lastTimestamp = context.last?.timestamp {
            let recencyFactor = 1.0 - (lastTimestamp.timeIntervalSince(interaction.timestamp) / 86400.0)
            score += max(0, min(recencyFactor * 0.3, 0.3))
        }

        // Length bonus (longer responses often more important)
        let avgLength = context.map { $0.response.count }.reduce(0, +) / max(1, context.count)
        if interaction.response.count > avgLength {
            score += 0.2
        }

        // Question complexity bonus
        if interaction.query.contains("?") {
            score += 0.1
        }

        // Key terms bonus
        let keyTerms = ["important", "remember", "note", "summary", "explain", "why", "how"]
        for term in keyTerms {
            if interaction.query.lowercased().contains(term) {
                score += 0.1
                break
            }
        }

        return score
    }

    private func extractKeyTopics(from interactions: [ContextInteraction]) -> [String] {
        var wordFrequency: [String: Int] = [:]

        // Combine all queries and responses
        let allText = interactions.map { $0.query + " " + $0.response }.joined(separator: " ")

        // Simple word extraction (in production, use NLP)
        let words = allText
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.count > 3 } // Skip short words

        // Count frequencies
        for word in words {
            wordFrequency[word, default: 0] += 1
        }

        // Remove common stop words
        let stopWords = Set(["this", "that", "with", "from", "have", "they", "what", "when", "where", "which", "about", "their", "would", "there"])

        // Get top 5 most frequent non-stop words
        return wordFrequency
            .filter { !stopWords.contains($0.key) }
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key }
    }

    private func compress(_ text: String, maxTokens: Int) -> String {
        let estimatedTokens = estimateTokens(text)

        if estimatedTokens <= maxTokens {
            return text
        }

        // Simple compression: take first part and add ellipsis
        let ratio = Double(maxTokens) / Double(estimatedTokens)
        let targetLength = Int(Double(text.count) * ratio)

        if targetLength < text.count {
            let index = text.index(text.startIndex, offsetBy: targetLength)
            return String(text[..<index]) + "..."
        }

        return text
    }

    private func groupByPeriod(
        _ interactions: [ContextInteraction],
        period: SummarizationPeriod
    ) -> [Date: [ContextInteraction]] {
        var grouped: [Date: [ContextInteraction]] = [:]

        for interaction in interactions {
            let periodStart = period.startOfPeriod(for: interaction.timestamp)
            grouped[periodStart, default: []].append(interaction)
        }

        return grouped
    }

    private func estimateTokens(_ text: String) -> Int {
        // Rough estimation: ~4 characters per token
        return max(1, text.count / 4)
    }
}

// MARK: - Supporting Types

enum SummarizationPeriod {
    case hourly
    case daily
    case weekly

    func startOfPeriod(for date: Date) -> Date {
        let calendar = Calendar.current

        switch self {
        case .hourly:
            let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
            return calendar.date(from: components) ?? date

        case .daily:
            return calendar.startOfDay(for: date)

        case .weekly:
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            return calendar.date(from: components) ?? date
        }
    }
}

struct PeriodSummary {
    let period: SummarizationPeriod
    let startDate: Date
    let summary: ConversationSummary

    var endDate: Date {
        let calendar = Calendar.current

        switch period {
        case .hourly:
            return calendar.date(byAdding: .hour, value: 1, to: startDate) ?? startDate
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: startDate) ?? startDate
        }
    }
}
