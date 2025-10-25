//
//  StreamingGenerator.swift
//  Atlas
//
//  Created by Atlas Development Team
//  Copyright © 2025 Atlas. All rights reserved.
//
//  Streaming token generation for real-time inference
//

import Foundation
import Combine
import os.log

/// Handles streaming token generation for real-time user feedback
@available(iOS 17.0, *)
public final class StreamingGenerator {

    private let logger = Logger(subsystem: "io.atlas.trm", category: "Streaming")
    private let tokenProcessor: TokenProcessor

    // Streaming control
    private var streamContinuation: AsyncStream<TokenChunk>.Continuation?
    private var isStreaming = false
    private let streamLock = NSLock()

    // Configuration
    private let bufferSize: Int
    private let chunkInterval: TimeInterval

    // MARK: - Types

    public struct TokenChunk: Sendable {
        public let token: String
        public let tokenId: Int
        public let confidence: Float
        public let iteration: Int
        public let timestamp: Date
        public let isComplete: Bool

        public init(token: String, tokenId: Int, confidence: Float, iteration: Int, timestamp: Date = Date(), isComplete: Bool = false) {
            self.token = token
            self.tokenId = tokenId
            self.confidence = confidence
            self.iteration = iteration
            self.timestamp = timestamp
            self.isComplete = isComplete
        }
    }

    public struct StreamingConfiguration {
        let bufferSize: Int
        let chunkInterval: TimeInterval
        let enableBuffering: Bool

        public static let `default` = StreamingConfiguration(
            bufferSize: 5,
            chunkInterval: 0.05, // 50ms
            enableBuffering: true
        )

        public static let realtime = StreamingConfiguration(
            bufferSize: 1,
            chunkInterval: 0.01, // 10ms
            enableBuffering: false
        )
    }

    // MARK: - Initialization

    public init(tokenProcessor: TokenProcessor, config: StreamingConfiguration = .default) {
        self.tokenProcessor = tokenProcessor
        self.bufferSize = config.bufferSize
        self.chunkInterval = config.chunkInterval

        logger.info("StreamingGenerator initialized with buffer size: \(bufferSize)")
    }

    // MARK: - Streaming API

    /// Create an async stream for token generation
    public func createStream() -> AsyncStream<TokenChunk> {
        streamLock.lock()
        defer { streamLock.unlock() }

        guard !isStreaming else {
            logger.warning("Stream already active, returning empty stream")
            return AsyncStream { _ in }
        }

        isStreaming = true

        return AsyncStream { continuation in
            self.streamContinuation = continuation

            continuation.onTermination = { [weak self] _ in
                self?.stopStreaming()
            }
        }
    }

    /// Emit a token chunk to the stream
    public func emitToken(_ tokenId: Int, confidence: Float, iteration: Int) async throws {
        streamLock.lock()
        guard isStreaming, let continuation = streamContinuation else {
            streamLock.unlock()
            return
        }
        streamLock.unlock()

        // Convert token ID to text
        guard let tokenText = tokenProcessor.getText(for: tokenId) else {
            logger.warning("Failed to convert token ID \(tokenId) to text")
            return
        }

        let chunk = TokenChunk(
            token: tokenText,
            tokenId: tokenId,
            confidence: confidence,
            iteration: iteration,
            isComplete: false
        )

        continuation.yield(chunk)

        // Add small delay for chunk interval
        if chunkInterval > 0 {
            try await Task.sleep(nanoseconds: UInt64(chunkInterval * 1_000_000_000))
        }

        logger.debug("Emitted token: '\(tokenText)' (confidence: \(String(format: "%.2f", confidence)))")
    }

    /// Emit multiple tokens as a batch
    public func emitTokenBatch(_ tokenIds: [Int], confidence: Float, iteration: Int) async throws {
        for tokenId in tokenIds {
            try await emitToken(tokenId, confidence: confidence, iteration: iteration)
        }
    }

    /// Complete the stream
    public func completeStream() {
        streamLock.lock()
        defer { streamLock.unlock() }

        guard isStreaming, let continuation = streamContinuation else {
            return
        }

        // Emit completion marker
        let completionChunk = TokenChunk(
            token: "",
            tokenId: tokenProcessor.eosToken,
            confidence: 1.0,
            iteration: 0,
            isComplete: true
        )

        continuation.yield(completionChunk)
        continuation.finish()

        streamContinuation = nil
        isStreaming = false

        logger.info("Stream completed")
    }

    /// Stop streaming
    public func stopStreaming() {
        streamLock.lock()
        defer { streamLock.unlock() }

        streamContinuation?.finish()
        streamContinuation = nil
        isStreaming = false

        logger.info("Streaming stopped")
    }

    // MARK: - Buffered Streaming

    private var tokenBuffer: [TokenChunk] = []
    private var bufferTask: Task<Void, Never>?

    /// Start buffered streaming for smoother output
    public func startBufferedStreaming() {
        bufferTask = Task {
            while !Task.isCancelled && isStreaming {
                await flushBuffer()
                try? await Task.sleep(nanoseconds: UInt64(chunkInterval * 1_000_000_000))
            }
        }
    }

    /// Add token to buffer
    public func bufferToken(_ tokenId: Int, confidence: Float, iteration: Int) throws {
        guard let tokenText = tokenProcessor.getText(for: tokenId) else {
            throw StreamingError.invalidToken(tokenId)
        }

        let chunk = TokenChunk(
            token: tokenText,
            tokenId: tokenId,
            confidence: confidence,
            iteration: iteration
        )

        streamLock.lock()
        tokenBuffer.append(chunk)
        streamLock.unlock()

        // Auto-flush if buffer is full
        if tokenBuffer.count >= bufferSize {
            Task {
                await flushBuffer()
            }
        }
    }

    /// Flush token buffer to stream
    private func flushBuffer() async {
        streamLock.lock()
        guard !tokenBuffer.isEmpty, let continuation = streamContinuation else {
            streamLock.unlock()
            return
        }

        let chunksToFlush = tokenBuffer
        tokenBuffer.removeAll()
        streamLock.unlock()

        for chunk in chunksToFlush {
            continuation.yield(chunk)
        }

        logger.debug("Flushed \(chunksToFlush.count) tokens from buffer")
    }

    // MARK: - Combine Publisher Support

    /// Create a Combine publisher for token streaming
    public func createPublisher() -> AnyPublisher<TokenChunk, Never> {
        let subject = PassthroughSubject<TokenChunk, Never>()

        Task {
            let stream = createStream()

            for await chunk in stream {
                subject.send(chunk)
            }

            subject.send(completion: .finished)
        }

        return subject.eraseToAnyPublisher()
    }

    // MARK: - Utilities

    public func isCurrentlyStreaming() -> Bool {
        streamLock.lock()
        defer { streamLock.unlock() }
        return isStreaming
    }

    public func getBufferSize() -> Int {
        streamLock.lock()
        defer { streamLock.unlock() }
        return tokenBuffer.count
    }

    deinit {
        stopStreaming()
        bufferTask?.cancel()
        logger.info("StreamingGenerator deinitialized")
    }
}

// MARK: - Error Types

public enum StreamingError: LocalizedError {
    case streamNotActive
    case invalidToken(Int)
    case bufferOverflow
    case streamAlreadyActive

    public var errorDescription: String? {
        switch self {
        case .streamNotActive:
            return "No active stream available"
        case .invalidToken(let tokenId):
            return "Invalid token ID: \(tokenId)"
        case .bufferOverflow:
            return "Token buffer overflow"
        case .streamAlreadyActive:
            return "A stream is already active"
        }
    }
}

// MARK: - Stream Utilities

extension AsyncStream where Element == StreamingGenerator.TokenChunk {
    /// Collect all tokens into a single string
    public func collectTokens() async -> String {
        var result = ""

        for await chunk in self {
            if !chunk.isComplete {
                result += chunk.token
            }
        }

        return result
    }

    /// Filter by confidence threshold
    public func filterByConfidence(threshold: Float) -> AsyncStream<Element> {
        AsyncStream { continuation in
            Task {
                for await chunk in self {
                    if chunk.confidence >= threshold {
                        continuation.yield(chunk)
                    }
                }
                continuation.finish()
            }
        }
    }
}
