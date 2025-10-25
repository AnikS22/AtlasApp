// File: AtlasApp/Services/Security/MCPSecurityManager.swift

import Foundation
import CryptoKit

final class MCPSecurityManager {
    static let shared = MCPSecurityManager()

    struct MCPServerPolicy {
        let allowedHosts: [String]
        let requireTLS: Bool
        let certificatePinning: [String: Data] // Host -> SHA256 hash
        let maxRequestSize: Int
        let timeout: TimeInterval
        let dataRedactionRules: [RedactionRule]
    }

    struct RedactionRule {
        let pattern: String // Regex pattern
        let replacement: String
    }

    enum MCPError: Error {
        case unauthorizedHost
        case insecureConnection
        case requestTooLarge
        case validationFailed
    }

    // MARK: - Request Validation

    func validateMCPRequest(
        _ request: URLRequest,
        policy: MCPServerPolicy
    ) throws -> URLRequest {
        // 1. Validate host whitelist
        guard let host = request.url?.host,
              policy.allowedHosts.contains(host) else {
            throw MCPError.unauthorizedHost
        }

        // 2. Enforce TLS
        guard request.url?.scheme == "https" || !policy.requireTLS else {
            throw MCPError.insecureConnection
        }

        // 3. Request size limit
        if let bodySize = request.httpBody?.count,
           bodySize > policy.maxRequestSize {
            throw MCPError.requestTooLarge
        }

        // 4. Apply data redaction
        var sanitizedRequest = request
        if let body = request.httpBody,
           let jsonString = String(data: body, encoding: .utf8) {
            var redacted = jsonString
            for rule in policy.dataRedactionRules {
                redacted = redacted.replacingOccurrences(
                    of: rule.pattern,
                    with: rule.replacement,
                    options: .regularExpression
                )
            }
            sanitizedRequest.httpBody = redacted.data(using: .utf8)
        }

        // 5. Add security headers
        sanitizedRequest.setValue("no-store, no-cache, must-revalidate", forHTTPHeaderField: "Cache-Control")
        sanitizedRequest.setValue("Atlas/1.0", forHTTPHeaderField: "User-Agent")

        return sanitizedRequest
    }

    // MARK: - Certificate Pinning

    func validateServerCertificate(
        _ trust: SecTrust,
        for host: String,
        policy: MCPServerPolicy
    ) -> Bool {
        guard let pinnedHash = policy.certificatePinning[host] else {
            return false // No pinning configured = deny
        }

        guard let serverCert = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let firstCert = serverCert.first else {
            return false
        }

        let serverCertData = SecCertificateCopyData(firstCert) as Data
        let serverHash = SHA256.hash(data: serverCertData)

        return Data(serverHash) == pinnedHash
    }

    // MARK: - Policy Management

    func getPolicy(for host: String) -> MCPServerPolicy {
        // Default policy for unknown hosts
        return MCPServerPolicy(
            allowedHosts: [host],
            requireTLS: true,
            certificatePinning: [:],
            maxRequestSize: 10 * 1024 * 1024, // 10MB
            timeout: 30.0,
            dataRedactionRules: defaultRedactionRules()
        )
    }

    // MARK: - Data Redaction

    func redactSensitiveData(_ content: String) -> String {
        var redacted = content

        // Remove API keys
        redacted = redacted.replacingOccurrences(
            of: "sk-ant-[a-zA-Z0-9-_]+",
            with: "[REDACTED_API_KEY]",
            options: .regularExpression
        )

        // Remove potential PII patterns
        let patterns = [
            ("\\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Z|a-z]{2,}\\b", "[EMAIL]"),
            ("\\b\\d{3}-\\d{2}-\\d{4}\\b", "[SSN]"),
            ("\\b\\d{16}\\b", "[CARD_NUMBER]")
        ]

        for (pattern, replacement) in patterns {
            redacted = redacted.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }

        return redacted
    }

    // MARK: - Default Redaction Rules

    private func defaultRedactionRules() -> [RedactionRule] {
        return [
            RedactionRule(pattern: "sk-ant-[a-zA-Z0-9-_]+", replacement: "[REDACTED_API_KEY]"),
            RedactionRule(pattern: "\\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Z|a-z]{2,}\\b", replacement: "[EMAIL]"),
            RedactionRule(pattern: "\\b\\d{3}-\\d{2}-\\d{4}\\b", replacement: "[SSN]"),
            RedactionRule(pattern: "\\b\\d{16}\\b", replacement: "[CARD_NUMBER]")
        ]
    }
}
