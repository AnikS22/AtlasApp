//
//  CachedEmbedding.swift
//  AtlasApp
//
//  Created by Claude Code on 2025-10-25.
//  Copyright © 2025 Atlas. All rights reserved.
//

import Foundation

/// Cached embedding with timestamp for TTL management
final class CachedEmbedding {
    let embedding: [Float]
    let timestamp: Date

    var isExpired: Bool {
        // Embeddings expire after 1 hour
        Date().timeIntervalSince(timestamp) > 3600
    }

    init(embedding: [Float], timestamp: Date) {
        self.embedding = embedding
        self.timestamp = timestamp
    }
}

/// Simple LRU cache implementation
final class LRUCache<Key: Hashable, Value> {
    private struct CacheEntry {
        let key: Key
        let value: Value
    }

    private let capacity: Int
    private var cache: [Key: Value] = [:]
    private var accessOrder: [Key] = []
    private let lock = NSLock()

    init(capacity: Int) {
        self.capacity = capacity
    }

    func get(_ key: Key) -> Value? {
        lock.lock()
        defer { lock.unlock() }

        guard let value = cache[key] else {
            return nil
        }

        // Update access order
        if let index = accessOrder.firstIndex(of: key) {
            accessOrder.remove(at: index)
        }
        accessOrder.append(key)

        return value
    }

    func set(_ key: Key, value: Value) {
        lock.lock()
        defer { lock.unlock() }

        // If key exists, update value and access order
        if cache[key] != nil {
            cache[key] = value

            if let index = accessOrder.firstIndex(of: key) {
                accessOrder.remove(at: index)
            }
            accessOrder.append(key)
            return
        }

        // If at capacity, remove least recently used
        if cache.count >= capacity, let lruKey = accessOrder.first {
            cache.removeValue(forKey: lruKey)
            accessOrder.removeFirst()
        }

        // Add new entry
        cache[key] = value
        accessOrder.append(key)
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }

        cache.removeAll()
        accessOrder.removeAll()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }

        return cache.count
    }
}
