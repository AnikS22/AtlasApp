//
//  TokenProcessor.swift
//  Atlas
//
//  Created by Atlas Development Team
//  Copyright © 2025 Atlas. All rights reserved.
//
//  Token processing utilities for TRM inference
//

import Foundation
import os.log
import Accelerate

/// Handles tokenization, detokenization, and embedding lookups
public final class TokenProcessor {

    private let logger = Logger(subsystem: "io.atlas.trm", category: "TokenProcessor")

    // Vocabulary and embeddings
    private let vocabulary: [String: Int]
    private let reverseVocabulary: [Int: String]
    private let embeddings: [[Float]]
    private let config: TokenProcessorConfig

    // Special tokens
    public let bosToken: Int  // Begin of sequence
    public let eosToken: Int  // End of sequence
    public let padToken: Int  // Padding
    public let unkToken: Int  // Unknown

    // MARK: - Configuration

    public struct TokenProcessorConfig {
        let vocabularySize: Int
        let embeddingDim: Int
        let maxTokenLength: Int
        let caseSensitive: Bool
        let useSubwordTokenization: Bool

        public static let `default` = TokenProcessorConfig(
            vocabularySize: 32_000,
            embeddingDim: 256,
            maxTokenLength: 2048,
            caseSensitive: false,
            useSubwordTokenization: false
        )
    }

    // MARK: - Initialization

    public init(config: TokenProcessorConfig = .default) throws {
        self.config = config

        // Load vocabulary from bundle
        guard let vocabURL = Bundle.main.url(forResource: "vocabulary", withExtension: "json") else {
            throw TokenProcessorError.vocabularyNotFound
        }

        let vocabData = try Data(contentsOf: vocabURL)
        let vocabDict = try JSONDecoder().decode([String: Int].self, from: vocabData)

        self.vocabulary = vocabDict
        self.reverseVocabulary = Dictionary(uniqueKeysWithValues: vocabDict.map { ($1, $0) })

        // Special token IDs (standard BPE/SentencePiece convention)
        self.bosToken = vocabulary["<bos>"] ?? 0
        self.eosToken = vocabulary["<eos>"] ?? 2
        self.padToken = vocabulary["<pad>"] ?? 1
        self.unkToken = vocabulary["<unk>"] ?? 3

        // Load pre-computed embeddings
        self.embeddings = try Self.loadEmbeddings(vocabularySize: config.vocabularySize, embeddingDim: config.embeddingDim)

        logger.info("TokenProcessor initialized with vocabulary size: \(self.vocabulary.count)")
    }

    // MARK: - Tokenization

    /// Convert text to token IDs
    public func tokenize(_ text: String) throws -> [Int] {
        guard !text.isEmpty else {
            return [bosToken, eosToken]
        }

        let processedText = config.caseSensitive ? text : text.lowercased()

        var tokens: [Int] = [bosToken]

        if config.useSubwordTokenization {
            // Use subword tokenization (BPE/WordPiece)
            let subwords = try tokenizeSubwords(processedText)
            tokens.append(contentsOf: subwords)
        } else {
            // Simple word-level tokenization
            let words = processedText.components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }

            for word in words {
                if let tokenId = vocabulary[word] {
                    tokens.append(tokenId)
                } else {
                    // Handle unknown words
                    tokens.append(unkToken)
                    logger.debug("Unknown word: \(word)")
                }

                if tokens.count >= config.maxTokenLength - 1 {
                    logger.warning("Reached max token length, truncating")
                    break
                }
            }
        }

        tokens.append(eosToken)

        return tokens
    }

    /// Tokenize using subword approach (simplified BPE)
    private func tokenizeSubwords(_ text: String) throws -> [Int] {
        var tokens: [Int] = []
        var remainingText = text

        while !remainingText.isEmpty && tokens.count < config.maxTokenLength - 2 {
            var matchFound = false

            // Try to match longest subword first (greedy approach)
            for length in stride(from: min(remainingText.count, 20), through: 1, by: -1) {
                let endIndex = remainingText.index(remainingText.startIndex, offsetBy: length)
                let subword = String(remainingText[..<endIndex])

                if let tokenId = vocabulary[subword] {
                    tokens.append(tokenId)
                    remainingText = String(remainingText[endIndex...])
                    matchFound = true
                    break
                }
            }

            if !matchFound {
                // No match found, use unknown token and skip character
                tokens.append(unkToken)
                remainingText = String(remainingText.dropFirst())
            }
        }

        return tokens
    }

    // MARK: - Detokenization

    /// Convert token IDs back to text
    public func detokenize(_ tokens: [Int]) throws -> String {
        guard !tokens.isEmpty else {
            return ""
        }

        var words: [String] = []

        for token in tokens {
            // Skip special tokens
            if token == bosToken || token == eosToken || token == padToken {
                continue
            }

            if let word = reverseVocabulary[token] {
                // Handle subword merging if needed
                if config.useSubwordTokenization && word.hasPrefix("##") {
                    // Merge with previous word (WordPiece style)
                    if !words.isEmpty {
                        words[words.count - 1] += word.dropFirst(2)
                    } else {
                        words.append(String(word.dropFirst(2)))
                    }
                } else {
                    words.append(word)
                }
            } else {
                logger.warning("Unknown token ID: \(token)")
                words.append("<unk>")
            }
        }

        return words.joined(separator: " ")
    }

    // MARK: - Embedding Operations

    /// Get embedding vector for a token ID
    public func getEmbedding(for tokenId: Int) throws -> [Float] {
        guard tokenId >= 0 && tokenId < embeddings.count else {
            logger.warning("Token ID \(tokenId) out of range, using unknown token embedding")
            return embeddings[unkToken]
        }

        return embeddings[tokenId]
    }

    /// Convert hidden state back to token ID (for generation)
    public func hiddenToToken(_ hiddenState: [Float]) throws -> Int {
        guard !hiddenState.isEmpty else {
            throw TokenProcessorError.invalidHiddenState
        }

        // Find most similar embedding using cosine similarity
        var maxSimilarity: Float = -1.0
        var bestToken = unkToken

        for (tokenId, embedding) in embeddings.enumerated() {
            let similarity = cosineSimilarity(hiddenState, embedding)

            if similarity > maxSimilarity {
                maxSimilarity = similarity
                bestToken = tokenId
            }
        }

        return bestToken
    }

    /// Batch embedding lookup
    public func getEmbeddings(for tokenIds: [Int]) throws -> [[Float]] {
        return try tokenIds.map { try getEmbedding(for: $0) }
    }

    // MARK: - Embedding Loading

    private static func loadEmbeddings(vocabularySize: Int, embeddingDim: Int) throws -> [[Float]] {
        // Try to load pre-computed embeddings from bundle
        if let embeddingsURL = Bundle.main.url(forResource: "embeddings", withExtension: "bin") {
            return try loadEmbeddingsFromFile(embeddingsURL, vocabularySize: vocabularySize, embeddingDim: embeddingDim)
        }

        // Fall back to random initialization (for development)
        Logger().warning("Pre-computed embeddings not found, using random initialization")
        return generateRandomEmbeddings(vocabularySize: vocabularySize, embeddingDim: embeddingDim)
    }

    private static func loadEmbeddingsFromFile(_ url: URL, vocabularySize: Int, embeddingDim: Int) throws -> [[Float]] {
        let data = try Data(contentsOf: url)

        let expectedSize = vocabularySize * embeddingDim * MemoryLayout<Float>.size
        guard data.count == expectedSize else {
            throw TokenProcessorError.invalidEmbeddingFile(expected: expectedSize, actual: data.count)
        }

        var embeddings: [[Float]] = []

        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            let floatBuffer = buffer.bindMemory(to: Float.self)

            for i in 0..<vocabularySize {
                let startIdx = i * embeddingDim
                let endIdx = startIdx + embeddingDim
                let embedding = Array(floatBuffer[startIdx..<endIdx])
                embeddings.append(embedding)
            }
        }

        return embeddings
    }

    private static func generateRandomEmbeddings(vocabularySize: Int, embeddingDim: Int) -> [[Float]] {
        var embeddings: [[Float]] = []

        // Xavier initialization
        let scale = sqrt(2.0 / Float(embeddingDim))

        for _ in 0..<vocabularySize {
            var embedding: [Float] = []
            for _ in 0..<embeddingDim {
                let value = Float.random(in: -scale...scale)
                embedding.append(value)
            }
            // Normalize
            let normalized = normalize(embedding)
            embeddings.append(normalized)
        }

        return embeddings
    }

    // MARK: - Utility Functions

    /// Calculate cosine similarity between two vectors
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0.0 }

        var dotProduct: Float = 0.0
        var magnitudeA: Float = 0.0
        var magnitudeB: Float = 0.0

        vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
        vDSP_measqv(a, 1, &magnitudeA, vDSP_Length(a.count))
        vDSP_measqv(b, 1, &magnitudeB, vDSP_Length(b.count))

        magnitudeA = sqrt(magnitudeA)
        magnitudeB = sqrt(magnitudeB)

        guard magnitudeA > 0 && magnitudeB > 0 else { return 0.0 }

        return dotProduct / (magnitudeA * magnitudeB)
    }

    /// Normalize a vector
    private static func normalize(_ vector: [Float]) -> [Float] {
        var result = vector
        var magnitude: Float = 0.0

        vDSP_measqv(vector, 1, &magnitude, vDSP_Length(vector.count))
        magnitude = sqrt(magnitude)

        if magnitude > 0 {
            var divisor = magnitude
            vDSP_vsdiv(vector, 1, &divisor, &result, 1, vDSP_Length(vector.count))
        }

        return result
    }

    // MARK: - Vocabulary Information

    public func getVocabularySize() -> Int {
        return vocabulary.count
    }

    public func getToken(for text: String) -> Int? {
        let processedText = config.caseSensitive ? text : text.lowercased()
        return vocabulary[processedText]
    }

    public func getText(for tokenId: Int) -> String? {
        return reverseVocabulary[tokenId]
    }

    public func isSpecialToken(_ tokenId: Int) -> Bool {
        return tokenId == bosToken || tokenId == eosToken || tokenId == padToken || tokenId == unkToken
    }
}

// MARK: - Error Types

public enum TokenProcessorError: LocalizedError {
    case vocabularyNotFound
    case invalidEmbeddingFile(expected: Int, actual: Int)
    case invalidHiddenState
    case tokenizationFailed(reason: String)
    case detokenizationFailed(reason: String)

    public var errorDescription: String? {
        switch self {
        case .vocabularyNotFound:
            return "Vocabulary file not found in app bundle"
        case .invalidEmbeddingFile(let expected, let actual):
            return "Invalid embedding file size. Expected: \(expected) bytes, got: \(actual) bytes"
        case .invalidHiddenState:
            return "Invalid hidden state for token conversion"
        case .tokenizationFailed(let reason):
            return "Tokenization failed: \(reason)"
        case .detokenizationFailed(let reason):
            return "Detokenization failed: \(reason)"
        }
    }
}
