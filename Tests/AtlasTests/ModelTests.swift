//
//  ModelTests.swift
//  AtlasTests
//
//  Unit tests for Llama 3.2 1B model integration
//

import XCTest
@testable import Atlas

@available(iOS 17.0, *)
final class ModelTests: XCTestCase {

    var adapter: Llama32Adapter?

    override func setUpWithError() throws {
        // Initialize Llama adapter
        do {
            adapter = try Llama32Adapter()
        } catch {
            XCTFail("Failed to initialize Llama adapter: \(error)")
        }
    }

    override func tearDownWithError() throws {
        adapter?.unloadModels()
        adapter = nil
    }

    func testModelInitialization() throws {
        XCTAssertNotNil(adapter, "Llama adapter should be initialized")
    }

    func testSimpleGeneration() async throws {
        guard let adapter = adapter else {
            XCTFail("Adapter not initialized")
            return
        }

        let prompt = "Hello, how are you?"
        let response = try await adapter.generate(prompt: prompt, context: nil)

        XCTAssertFalse(response.isEmpty, "Response should not be empty")
        XCTAssertGreaterThan(response.count, 0, "Response should have content")
    }

    func testEmbeddingGeneration() async throws {
        guard let adapter = adapter else {
            XCTFail("Adapter not initialized")
            return
        }

        let text = "This is a test sentence for embedding generation."
        let embedding = try await adapter.generateEmbedding(for: text)

        XCTAssertFalse(embedding.isEmpty, "Embedding should not be empty")
        XCTAssertGreaterThan(embedding.count, 0, "Embedding should have dimensions")
    }

    func testCancellation() async throws {
        guard let adapter = adapter else {
            XCTFail("Adapter not initialized")
            return
        }

        // Start a long generation
        Task {
            do {
                _ = try await adapter.generate(prompt: "Generate a very long story about", context: nil)
            } catch {
                // Expected to be cancelled
            }
        }

        // Cancel it
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        adapter.cancelGeneration()

        // Should be able to generate again
        let response = try await adapter.generate(prompt: "Hello", context: nil)
        XCTAssertFalse(response.isEmpty)
    }

    func testPerformanceMetrics() async throws {
        guard let adapter = adapter else {
            XCTFail("Adapter not initialized")
            return
        }

        // Generate a few responses
        for i in 0..<3 {
            _ = try await adapter.generate(prompt: "Test \(i)", context: nil)
        }

        let metrics = adapter.getPerformanceMetrics()
        XCTAssertGreaterThan(metrics.totalInferences, 0, "Should have inference count")
    }
}
