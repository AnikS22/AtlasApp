// File: AtlasApp/Services/Security/FileAccessManager.swift

import Foundation

final class FileAccessManager {
    static let shared = FileAccessManager()

    enum Directory {
        case database
        case mcpCache
        case tempFiles

        var url: URL {
            let fm = FileManager.default
            switch self {
            case .database:
                return try! fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            case .mcpCache:
                let appSupport = try! fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                let cache = appSupport.appendingPathComponent("mcp_cache", isDirectory: true)
                try? fm.createDirectory(at: cache, withIntermediateDirectories: true)
                return cache
            case .tempFiles:
                return fm.temporaryDirectory
            }
        }
    }

    enum FileAccessError: Error {
        case invalidPath
        case permissionDenied
        case fileNotFound
    }

    // MARK: - File Protection

    func setFileProtection(_ protection: FileProtectionType, for url: URL) throws {
        try FileManager.default.setAttributes(
            [.protectionKey: protection],
            ofItemAtPath: url.path
        )
    }

    // MARK: - Secure File Operations

    func securePurgeTempFiles() {
        let tmpDir = FileManager.default.temporaryDirectory
        try? FileManager.default.contentsOfDirectory(at: tmpDir, includingPropertiesForKeys: nil)
            .forEach { try? FileManager.default.removeItem(at: $0) }
    }

    func secureDeleteFile(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FileAccessError.fileNotFound
        }

        // Overwrite file contents before deletion
        if let fileHandle = try? FileHandle(forWritingTo: url) {
            let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64 ?? 0
            let zeros = Data(repeating: 0, count: Int(fileSize))
            fileHandle.write(zeros)
            try? fileHandle.close()
        }

        // Delete the file
        try FileManager.default.removeItem(at: url)
    }

    // MARK: - Directory Management

    func createSecureDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
    }
}
