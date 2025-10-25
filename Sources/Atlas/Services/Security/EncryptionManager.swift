// File: AtlasApp/Services/Security/EncryptionManager.swift

import CryptoKit
import Foundation

final class EncryptionManager {
    static let shared = EncryptionManager()

    enum EncryptionError: Error {
        case encryptionFailed
        case decryptionFailed
        case invalidKey
    }

    // MARK: - AES-256-GCM Encryption

    func encrypt(_ plaintext: String, key: SymmetricKey) throws -> Data {
        guard let data = plaintext.data(using: .utf8) else {
            throw EncryptionError.encryptionFailed
        }

        let sealedBox = try AES.GCM.seal(data, using: key)

        // Format: nonce (12 bytes) + ciphertext + tag (16 bytes)
        guard let combined = sealedBox.combined else {
            throw EncryptionError.encryptionFailed
        }

        return combined
    }

    func decrypt(_ ciphertext: Data, key: SymmetricKey) throws -> String {
        let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
        let decryptedData = try AES.GCM.open(sealedBox, using: key)

        guard let plaintext = String(data: decryptedData, encoding: .utf8) else {
            throw EncryptionError.decryptionFailed
        }

        return plaintext
    }

    // MARK: - Master Key Derivation

    func deriveConversationKey(from masterKey: Data, conversationID: UUID) throws -> SymmetricKey {
        let info = "conversation_encryption_\(conversationID.uuidString)"
        let salt = Data(conversationID.uuidString.utf8)

        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: masterKey),
            salt: salt,
            info: Data(info.utf8),
            outputByteCount: 32 // 256 bits
        )

        return derivedKey
    }

    // MARK: - Secure Memory Handling

    func secureErase(_ data: inout Data) {
        data.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            memset_s(baseAddress, bytes.count, 0, bytes.count)
        }
    }

    func secureErase(_ string: inout String) {
        var data = Data(string.utf8)
        secureErase(&data)
        string = ""
    }
}
