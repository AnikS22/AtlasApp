// File: AtlasApp/Services/Security/SecureMemory.swift

import Foundation

/// Utilities for secure memory handling and scrubbing
final class SecureMemory {

    // MARK: - Memory Scrubbing

    /// Securely erase data from memory
    static func scrub(_ data: inout Data) {
        data.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            memset_s(baseAddress, bytes.count, 0, bytes.count)
        }
    }

    /// Securely erase string from memory
    static func scrub(_ string: inout String) {
        var data = Data(string.utf8)
        scrub(&data)
        string = ""
    }

    /// Securely erase array of bytes
    static func scrub<T>(_ array: inout [T]) {
        array.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            memset_s(baseAddress, bytes.count, 0, bytes.count)
        }
        array.removeAll()
    }

    // MARK: - Secure Comparison

    /// Constant-time comparison to prevent timing attacks
    static func constantTimeCompare(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else {
            return false
        }

        var result: UInt8 = 0
        for (a, b) in zip(lhs, rhs) {
            result |= a ^ b
        }

        return result == 0
    }

    // MARK: - Secure Random Generation

    /// Generate cryptographically secure random bytes
    static func randomBytes(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)

        guard status == errSecSuccess else {
            fatalError("Unable to generate random bytes")
        }

        return Data(bytes)
    }

    /// Generate a secure random string of specified length
    static func randomString(length: Int) -> String {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        let randomBytes = randomBytes(count: length)

        return randomBytes.map { byte in
            letters[letters.index(letters.startIndex, offsetBy: Int(byte) % letters.count)]
        }.reduce("") { $0 + String($1) }
    }

    // MARK: - Clipboard Security

    /// Copy to clipboard with auto-clear after timeout
    static func copyToClipboard(_ string: String, clearAfter seconds: TimeInterval = 60) {
        #if os(iOS)
        UIPasteboard.general.string = string

        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            if UIPasteboard.general.string == string {
                UIPasteboard.general.string = ""
            }
        }
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)

        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            if NSPasteboard.general.string(forType: .string) == string {
                NSPasteboard.general.clearContents()
            }
        }
        #endif
    }

    // MARK: - Memory Lock

    /// Lock memory page to prevent swapping to disk (where supported)
    static func lockMemory(_ data: Data) -> Bool {
        return data.withUnsafeBytes { bytes -> Bool in
            guard let baseAddress = bytes.baseAddress else { return false }
            return mlock(baseAddress, bytes.count) == 0
        }
    }

    /// Unlock previously locked memory
    static func unlockMemory(_ data: Data) -> Bool {
        return data.withUnsafeBytes { bytes -> Bool in
            guard let baseAddress = bytes.baseAddress else { return false }
            return munlock(baseAddress, bytes.count) == 0
        }
    }
}

// MARK: - Secure String Wrapper

/// A string wrapper that automatically scrubs memory on deallocation
final class SecureString {
    private var storage: String

    var value: String {
        get { storage }
        set {
            SecureMemory.scrub(&storage)
            storage = newValue
        }
    }

    init(_ string: String) {
        self.storage = string
    }

    deinit {
        SecureMemory.scrub(&storage)
    }
}

// MARK: - Secure Data Wrapper

/// A data wrapper that automatically scrubs memory on deallocation
final class SecureData {
    private var storage: Data

    var value: Data {
        get { storage }
        set {
            SecureMemory.scrub(&storage)
            storage = newValue
        }
    }

    init(_ data: Data) {
        self.storage = data
    }

    deinit {
        SecureMemory.scrub(&storage)
    }
}
