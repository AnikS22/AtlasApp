// File: AtlasApp/Services/Security/SecurityAuditLogger.swift

import Foundation
import os.log
import OSLog

final class SecurityAuditLogger {
    static let shared = SecurityAuditLogger()

    private let logger = Logger(subsystem: "com.atlas.security", category: "audit")
    private let auditLog: OSLog

    private init() {
        auditLog = OSLog(subsystem: "com.atlas.security", category: "audit")
    }

    // MARK: - Audit Events

    func logKeychainAccess(item: String, operation: String) {
        os_log(.info, log: auditLog, "Keychain access: %{public}@ - %{public}@", item, operation)
    }

    func logDatabaseAccess(operation: String) {
        os_log(.info, log: auditLog, "Database access: %{public}@", operation)
    }

    func logMCPRequest(serverID: String, tool: String) {
        os_log(.info, log: auditLog, "MCP request: server=%{public}@ tool=%{public}@", serverID, tool)
    }

    func logAPICall(endpoint: String, success: Bool) {
        os_log(.info, log: auditLog, "API call: %{public}@ success=%{public}@", endpoint, String(success))
    }

    func logAuthenticationAttempt(method: String, success: Bool) {
        os_log(.info, log: auditLog, "Authentication: %{public}@ success=%{public}@", method, String(success))
    }

    // MARK: - Security Violations

    func logSuspiciousActivity(serverID: String, pattern: String, output: String) {
        os_log(.error, log: auditLog, "SUSPICIOUS: MCP server %{public}@ matched pattern %{public}@", serverID, pattern)
        // Redact output to avoid logging sensitive data
    }

    func logCertificateValidationFailure(host: String) {
        os_log(.error, log: auditLog, "Certificate validation failed for host: %{public}@", host)
    }

    func logUnauthorizedAccess(resource: String) {
        os_log(.error, log: auditLog, "Unauthorized access attempt: %{public}@", resource)
    }

    // MARK: - Export Audit Log

    func exportAuditLog(completion: @escaping (URL?) -> Void) {
        // Export OSLog entries to file for user transparency
        let store = try? OSLogStore(scope: .currentProcessIdentifier)
        let position = store?.position(timeIntervalSinceLatestBoot: 0)

        guard let store = store, let position = position else {
            completion(nil)
            return
        }

        let entries = try? store.getEntries(at: position)
            .compactMap { $0 as? OSLogEntryLog }
            .filter { $0.subsystem == "com.atlas.security" }

        // Write to temp file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("audit_log.txt")

        var logText = "Atlas Security Audit Log\n"
        logText += "Generated: \(Date())\n\n"

        entries?.forEach { entry in
            logText += "[\(entry.date)] \(entry.composedMessage)\n"
        }

        try? logText.write(to: tempURL, atomically: true, encoding: .utf8)
        completion(tempURL)
    }
}
