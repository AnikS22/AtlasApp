//
//  VectorStore.swift
//  AtlasApp
//
//  Created by Claude Code on 2025-10-25.
//  Copyright © 2025 Atlas. All rights reserved.
//

import Foundation
import SQLite3

// SQLite constants
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Local vector storage with SQLite backend
/// Provides efficient vector similarity search with FTS5 integration
final class VectorStore {

    // MARK: - Properties

    private var database: OpaquePointer?
    private let databaseURL: URL
    private let embeddingDimension: Int

    private let queue = DispatchQueue(label: "io.atlas.vectorstore", qos: .userInitiated)

    // MARK: - Initialization

    init(databaseURL: URL, embeddingDimension: Int) {
        self.databaseURL = databaseURL
        self.embeddingDimension = embeddingDimension

        do {
            try openDatabase()
            try createTables()
            try createIndexes()
        } catch {
            fatalError("Failed to initialize VectorStore: \(error)")
        }
    }

    deinit {
        sqlite3_close(database)
    }

    // MARK: - Public API

    /// Insert a new memory entry
    func insert(_ entry: MemoryEntry) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try self.insertSync(entry)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Batch insert multiple entries
    func batchInsert(_ entries: [MemoryEntry]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try self.executeInTransaction {
                        for entry in entries {
                            try self.insertSync(entry)
                        }
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Search for similar vectors using cosine similarity
    func search(
        embedding: [Float],
        limit: Int,
        threshold: Float = 0.7
    ) async throws -> [VectorSearchResult] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let results = try self.searchSync(
                        embedding: embedding,
                        limit: limit,
                        threshold: threshold
                    )
                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Full-text search using SQLite FTS5
    func fullTextSearch(
        query: String,
        limit: Int
    ) async throws -> [VectorSearchResult] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let results = try self.fullTextSearchSync(
                        query: query,
                        limit: limit
                    )
                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Prune old or low-importance entries
    func prune(
        olderThan date: Date,
        minImportance: MemoryImportance,
        category: MemoryCategory? = nil
    ) async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let count = try self.pruneSync(
                        olderThan: date,
                        minImportance: minImportance,
                        category: category
                    )
                    continuation.resume(returning: count)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Optimize database (VACUUM and ANALYZE)
    func optimize() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try self.execute("VACUUM")
                    try self.execute("ANALYZE")
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Get total entry count
    func count() async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let count = try self.countSync()
                    continuation.resume(returning: count)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Private Synchronous Methods

    private func insertSync(_ entry: MemoryEntry) throws {
        let sql = """
        INSERT INTO memories (
            id, query, response, embedding, timestamp,
            category, importance, tags, metadata_json
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw VectorStoreError.prepareFailed(String(cString: sqlite3_errmsg(database)))
        }

        // Bind values
        sqlite3_bind_text(statement, 1, entry.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, entry.query, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, entry.response, -1, SQLITE_TRANSIENT)

        // Bind embedding as blob
        let embeddingData = entry.embedding.withUnsafeBytes { Data($0) }
        embeddingData.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, 4, bytes.baseAddress, Int32(embeddingData.count), SQLITE_TRANSIENT)
        }

        sqlite3_bind_double(statement, 5, entry.timestamp.timeIntervalSince1970)
        sqlite3_bind_text(statement, 6, entry.metadata.category.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 7, Int32(entry.metadata.importance.rawValue))
        sqlite3_bind_text(statement, 8, entry.metadata.tags.joined(separator: ","), -1, SQLITE_TRANSIENT)

        // Bind metadata JSON
        if let metadataData = try? JSONEncoder().encode(entry.metadata),
           let metadataString = String(data: metadataData, encoding: .utf8) {
            sqlite3_bind_text(statement, 9, metadataString, -1, SQLITE_TRANSIENT)
        }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw VectorStoreError.executeFailed(String(cString: sqlite3_errmsg(database)))
        }

        // Update FTS index
        try updateFTSIndex(entry: entry)
    }

    private func searchSync(
        embedding: [Float],
        limit: Int,
        threshold: Float
    ) throws -> [VectorSearchResult] {
        let sql = """
        SELECT id, query, response, embedding, timestamp,
               category, importance, tags, metadata_json
        FROM memories
        ORDER BY rowid DESC
        LIMIT 1000
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw VectorStoreError.prepareFailed(String(cString: sqlite3_errmsg(database)))
        }

        var results: [VectorSearchResult] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let entry = try extractMemoryEntry(from: statement) else {
                continue
            }

            // Calculate cosine similarity
            let similarity = cosineSimilarity(embedding, entry.embedding)

            if similarity >= threshold {
                results.append(VectorSearchResult(entry: entry, similarity: similarity))
            }
        }

        // Sort by similarity and limit
        return results
            .sorted { $0.similarity > $1.similarity }
            .prefix(limit)
            .map { $0 }
    }

    private func fullTextSearchSync(query: String, limit: Int) throws -> [VectorSearchResult] {
        let sql = """
        SELECT m.id, m.query, m.response, m.embedding, m.timestamp,
               m.category, m.importance, m.tags, m.metadata_json,
               fts.rank
        FROM memories_fts fts
        JOIN memories m ON fts.rowid = m.rowid
        WHERE memories_fts MATCH ?
        ORDER BY rank
        LIMIT ?
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw VectorStoreError.prepareFailed(String(cString: sqlite3_errmsg(database)))
        }

        sqlite3_bind_text(statement, 1, query, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 2, Int32(limit))

        var results: [VectorSearchResult] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let entry = try extractMemoryEntry(from: statement) else {
                continue
            }

            // Use rank as similarity score (normalized)
            let rank = sqlite3_column_double(statement, 9)
            let similarity = Float(1.0 / (1.0 + abs(rank)))

            results.append(VectorSearchResult(entry: entry, similarity: similarity))
        }

        return results
    }

    private func pruneSync(
        olderThan date: Date,
        minImportance: MemoryImportance,
        category: MemoryCategory?
    ) throws -> Int {
        var sql = """
        DELETE FROM memories
        WHERE timestamp < ?
        AND importance < ?
        """

        var bindIndex: Int32 = 3
        if category != nil {
            sql += " AND category = ?"
            bindIndex += 1
        }

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw VectorStoreError.prepareFailed(String(cString: sqlite3_errmsg(database)))
        }

        sqlite3_bind_double(statement, 1, date.timeIntervalSince1970)
        sqlite3_bind_int(statement, 2, Int32(minImportance.rawValue))

        if let category = category {
            sqlite3_bind_text(statement, 3, category.rawValue, -1, SQLITE_TRANSIENT)
        }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw VectorStoreError.executeFailed(String(cString: sqlite3_errmsg(database)))
        }

        return Int(sqlite3_changes(database))
    }

    private func countSync() throws -> Int {
        let sql = "SELECT COUNT(*) FROM memories"

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw VectorStoreError.prepareFailed(String(cString: sqlite3_errmsg(database)))
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw VectorStoreError.executeFailed(String(cString: sqlite3_errmsg(database)))
        }

        return Int(sqlite3_column_int(statement, 0))
    }

    // MARK: - Database Setup

    private func openDatabase() throws {
        let result = sqlite3_open(databaseURL.path, &database)
        guard result == SQLITE_OK else {
            throw VectorStoreError.openFailed(String(cString: sqlite3_errmsg(database)))
        }

        // Enable WAL mode for better concurrency
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA synchronous=NORMAL")
    }

    private func createTables() throws {
        let createMemoriesTable = """
        CREATE TABLE IF NOT EXISTS memories (
            rowid INTEGER PRIMARY KEY AUTOINCREMENT,
            id TEXT NOT NULL UNIQUE,
            query TEXT NOT NULL,
            response TEXT NOT NULL,
            embedding BLOB NOT NULL,
            timestamp REAL NOT NULL,
            category TEXT NOT NULL,
            importance INTEGER NOT NULL,
            tags TEXT,
            metadata_json TEXT
        )
        """

        let createFTSTable = """
        CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts USING fts5(
            query, response,
            content='memories',
            content_rowid='rowid',
            tokenize='porter unicode61'
        )
        """

        try execute(createMemoriesTable)
        try execute(createFTSTable)
    }

    private func createIndexes() throws {
        let indexes = [
            "CREATE INDEX IF NOT EXISTS idx_timestamp ON memories(timestamp DESC)",
            "CREATE INDEX IF NOT EXISTS idx_category ON memories(category)",
            "CREATE INDEX IF NOT EXISTS idx_importance ON memories(importance DESC)",
            "CREATE INDEX IF NOT EXISTS idx_id ON memories(id)"
        ]

        for index in indexes {
            try execute(index)
        }
    }

    private func updateFTSIndex(entry: MemoryEntry) throws {
        let sql = """
        INSERT INTO memories_fts(rowid, query, response)
        SELECT rowid, query, response FROM memories WHERE id = ?
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw VectorStoreError.prepareFailed(String(cString: sqlite3_errmsg(database)))
        }

        sqlite3_bind_text(statement, 1, entry.id.uuidString, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw VectorStoreError.executeFailed(String(cString: sqlite3_errmsg(database)))
        }
    }

    // MARK: - Helper Methods

    private func execute(_ sql: String) throws {
        var errorMsg: UnsafeMutablePointer<Int8>?
        defer { sqlite3_free(errorMsg) }

        guard sqlite3_exec(database, sql, nil, nil, &errorMsg) == SQLITE_OK else {
            if let error = errorMsg {
                throw VectorStoreError.executeFailed(String(cString: error))
            }
            throw VectorStoreError.executeFailed("Unknown error")
        }
    }

    private func executeInTransaction(_ block: () throws -> Void) throws {
        try execute("BEGIN TRANSACTION")

        do {
            try block()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func extractMemoryEntry(from statement: OpaquePointer?) throws -> MemoryEntry? {
        guard let statement = statement else { return nil }

        guard let idPtr = sqlite3_column_text(statement, 0),
              let queryPtr = sqlite3_column_text(statement, 1),
              let responsePtr = sqlite3_column_text(statement, 2) else {
            return nil
        }

        let id = UUID(uuidString: String(cString: idPtr)) ?? UUID()
        let query = String(cString: queryPtr)
        let response = String(cString: responsePtr)

        // Extract embedding blob
        let blobPtr = sqlite3_column_blob(statement, 3)
        let blobSize = sqlite3_column_bytes(statement, 3)
        guard let ptr = blobPtr else { return nil }

        let embeddingData = Data(bytes: ptr, count: Int(blobSize))
        let embedding = embeddingData.withUnsafeBytes {
            Array($0.bindMemory(to: Float.self))
        }

        let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))

        // Extract metadata
        let categoryStr = String(cString: sqlite3_column_text(statement, 5))
        let category = MemoryCategory(rawValue: categoryStr) ?? .general
        let importance = MemoryImportance(rawValue: Float(sqlite3_column_int(statement, 6))) ?? .medium

        var tags: [String] = []
        if let tagsPtr = sqlite3_column_text(statement, 7) {
            let tagsStr = String(cString: tagsPtr)
            tags = tagsStr.components(separatedBy: ",").filter { !$0.isEmpty }
        }

        let metadata = MemoryMetadata(
            category: category,
            importance: importance,
            tags: tags
        )

        return MemoryEntry(
            id: id,
            query: query,
            response: response,
            embedding: embedding,
            metadata: metadata,
            timestamp: timestamp
        )
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }

        let dotProduct = zip(a, b).map(*).reduce(0, +)
        let magnitudeA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let magnitudeB = sqrt(b.map { $0 * $0 }.reduce(0, +))

        guard magnitudeA > 0 && magnitudeB > 0 else { return 0 }

        return dotProduct / (magnitudeA * magnitudeB)
    }
}

// MARK: - Supporting Types

struct VectorSearchResult {
    let entry: MemoryEntry
    let similarity: Float
}

struct MemoryEntry: Codable {
    let id: UUID
    let query: String
    let response: String
    let embedding: [Float]
    let metadata: MemoryMetadata
    let timestamp: Date
}

struct MemoryMetadata: Codable {
    let category: MemoryCategory
    let importance: MemoryImportance
    let tags: [String]

    init(
        category: MemoryCategory = .general,
        importance: MemoryImportance = .medium,
        tags: [String] = []
    ) {
        self.category = category
        self.importance = importance
        self.tags = tags
    }
}

enum MemoryCategory: String, Codable {
    case general
    case important
    case summary
    case context
    case fact
    case preference
}

enum MemoryImportance: Float, Codable, Comparable {
    case low = 1.0
    case medium = 2.0
    case high = 3.0
    case critical = 4.0

    static func < (lhs: MemoryImportance, rhs: MemoryImportance) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum VectorStoreError: Error, LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case executeFailed(String)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .openFailed(let message):
            return "Failed to open database: \(message)"
        case .prepareFailed(let message):
            return "Failed to prepare statement: \(message)"
        case .executeFailed(let message):
            return "Failed to execute statement: \(message)"
        case .invalidData:
            return "Invalid data format"
        }
    }
}
