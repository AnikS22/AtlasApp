// File: AtlasApp/Services/Security/SecureURLSession.swift

import Foundation

final class SecureURLSession: NSObject {
    static let shared = SecureURLSession()

    lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.tlsMinimumSupportedProtocolVersion = .TLSv13
        config.tlsMaximumSupportedProtocolVersion = .TLSv13
        config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30.0

        return URLSession(
            configuration: config,
            delegate: self,
            delegateQueue: nil
        )
    }()
}

extension SecureURLSession: URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Certificate pinning validation
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        let host = challenge.protectionSpace.host

        // Validate certificate for known hosts
        let policy = MCPSecurityManager.shared.getPolicy(for: host)
        let isValid = MCPSecurityManager.shared.validateServerCertificate(
            serverTrust,
            for: host,
            policy: policy
        )

        if isValid {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            SecurityAuditLogger.shared.logCertificateValidationFailure(host: host)
        }
    }
}
