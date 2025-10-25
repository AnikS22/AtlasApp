// File: AtlasApp/Services/Security/DatabaseManager.swift

import Foundation
import SQLite

final class DatabaseManager {
    static let shared = DatabaseManager()

    private var db: Connection?
    private let encryptionManager = EncryptionManager.shared

    enum DatabaseError: Error {
        case notInitialized
        case encryptionFailed
        case invalidMasterKey
        case connectionFailed
    }

    // MARK: - Database Initialization

    func initialize() throws {
        let fileURL = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, create: true)
            .appendingPathComponent("atlas.db")

        // Get master key from Keychain (biometric protected)
        let masterKey = try KeychainManager.shared.retrieveMasterKey()
        let keyString = masterKey.base64EncodedString()

        db = try Connection(fileURL.path)

        // Enable SQLCipher encryption
        try db?.execute("PRAGMA key = '\(keyString)'")

        // Security hardening
        try db?.execute("PRAGMA cipher_page_size = 4096")
        try db?.execute("PRAGMA kdf_iter = 256000") // PBKDF2 iterations
        try db?.execute("PRAGMA cipher_hmac_algorithm = HMAC_SHA512")
        try db?.execute("PRAGMA cipher_kdf_algorithm = PBKDF2_HMAC_SHA512")

        // Verify encryption
        try db?.execute("SELECT count(*) FROM sqlite_master")

        // Set file protection
        try setFileProtection(for: fileURL)
    }

    // MARK: - File Protection

    private func setFileProtection(for url: URL) throws {
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }

    // MARK: - Database Operations

    func execute(_ sql: String) throws {
        guard let db = db else {
            throw DatabaseError.notInitialized
        }
        try db.execute(sql)
    }

    func prepare(_ sql: String) throws -> Statement {
        guard let db = db else {
            throw DatabaseError.notInitialized
        }
        return try db.prepare(sql)
    }

    // MARK: - Secure Shutdown

    func close() {
        // Clear any cached data
        db = nil
    }
}
