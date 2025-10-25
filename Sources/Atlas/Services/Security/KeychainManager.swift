// File: AtlasApp/Services/Security/KeychainManager.swift

import Security
import Foundation
import LocalAuthentication

final class KeychainManager {
    static let shared = KeychainManager()

    private let service = "com.atlas.credentials"
    private let accessGroup: String? = nil // App-specific, no sharing

    enum KeychainError: Error {
        case itemNotFound
        case duplicateItem
        case invalidData
        case authenticationFailed
        case unexpectedError(OSStatus)
    }

    // MARK: - API Key Storage

    func storeClaudeAPIKey(_ key: String) throws {
        guard let data = key.data(using: .utf8) else {
            throw KeychainError.invalidData
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "claude_api_key",
            kSecAttrService as String: service,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false
        ]

        // Delete existing item
        SecItemDelete(query as CFDictionary)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedError(status)
        }
    }

    func retrieveClaudeAPIKey() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "claude_api_key",
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw KeychainError.itemNotFound
        }

        return key
    }

    // MARK: - Biometric Protected Master Key

    func storeMasterKey(_ key: Data, requireBiometric: Bool = true) throws {
        var accessControl: SecAccessControl?

        if requireBiometric {
            accessControl = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                .biometryCurrentSet, // Invalidate if biometrics change
                nil
            )
        }

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "encryption_master_key",
            kSecAttrService as String: service,
            kSecValueData as String: key,
            kSecAttrSynchronizable as String: false
        ]

        if let accessControl = accessControl {
            query[kSecAttrAccessControl as String] = accessControl
        } else {
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }

        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedError(status)
        }
    }

    func retrieveMasterKey(prompt: String = "Authenticate to unlock Atlas") throws -> Data {
        let context = LAContext()
        context.localizedReason = prompt

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "encryption_master_key",
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let keyData = result as? Data else {
            throw KeychainError.authenticationFailed
        }

        return keyData
    }

    // MARK: - MCP Server Credentials

    func storeMCPCredential(_ credential: String, for serverID: String) throws {
        guard let data = credential.data(using: .utf8) else {
            throw KeychainError.invalidData
        }

        let account = "mcp_\(serverID)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: false
        ]

        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedError(status)
        }
    }

    func retrieveMCPCredential(for serverID: String) throws -> String {
        let account = "mcp_\(serverID)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let credential = String(data: data, encoding: .utf8) else {
            throw KeychainError.itemNotFound
        }

        return credential
    }

    // MARK: - Secure Deletion

    func deleteAllCredentials() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedError(status)
        }
    }
}
