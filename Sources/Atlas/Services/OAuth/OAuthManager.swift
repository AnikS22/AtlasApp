//
//  OAuthManager.swift
//  Atlas
//
//  Manages OAuth flows for Gmail, Google Drive, Notion, etc.
//

import Foundation
import AuthenticationServices
import SwiftUI

@MainActor
public final class OAuthManager: NSObject, ObservableObject {
    
    @Published public var isAuthenticating = false
    @Published public var connectedServices: Set<ServiceType> = []
    @Published public var lastError: Error?
    
    private let credentialManager = MCPCredentialManager.shared
    private var authSession: ASWebAuthenticationSession?
    
    public enum ServiceType: String, CaseIterable {
        case gmail = "Gmail"
        case googleDrive = "Google Drive"
        case notion = "Notion"
        
        var icon: String {
            switch self {
            case .gmail: return "envelope.fill"
            case .googleDrive: return "folder.fill"
            case .notion: return "doc.text.fill"
            }
        }
        
        var color: String {
            switch self {
            case .gmail: return "red"
            case .googleDrive: return "blue"
            case .notion: return "gray"
            }
        }
        
        var serverId: String {
            return rawValue.lowercased().replacingOccurrences(of: " ", with: "_")
        }
    }
    
    public override init() {
        super.init()
        loadConnectedServices()
    }
    
    // MARK: - Connection Management
    
    public func connect(service: ServiceType) async throws {
        isAuthenticating = true
        defer { isAuthenticating = false }
        
        do {
            switch service {
            case .gmail:
                try await connectGmail()
            case .googleDrive:
                try await connectGoogleDrive()
            case .notion:
                try await connectNotion()
            }
            
            connectedServices.insert(service)
            lastError = nil
            
        } catch {
            lastError = error
            throw error
        }
    }
    
    public func disconnect(service: ServiceType) throws {
        try credentialManager.delete(for: service.serverId)
        connectedServices.remove(service)
    }
    
    public func isConnected(_ service: ServiceType) -> Bool {
        return credentialManager.hasValidCredential(for: service.serverId)
    }
    
    // MARK: - Gmail OAuth
    
    private func connectGmail() async throws {
        let config = MCPOAuthHelper.getGmailConfig()
        let authURL = MCPOAuthHelper.generateAuthURL(config: config, state: UUID().uuidString)
        
        let callbackURL = try await performOAuthFlow(authURL: authURL)
        
        guard let code = extractCode(from: callbackURL) else {
            throw OAuthError.invalidCallback
        }
        
        let tokens = try await MCPOAuthHelper.exchangeCodeForTokens(config: config, code: code)
        
        let credential = MCPCredential(
            serverId: "gmail",
            type: .oauth,
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            apiKey: nil,
            expiresAt: Date().addingTimeInterval(TimeInterval(tokens.expiresIn))
        )
        
        try credentialManager.store(credential, for: "gmail")
    }
    
    // MARK: - Google Drive OAuth
    
    private func connectGoogleDrive() async throws {
        let config = MCPOAuthHelper.getDriveConfig()
        let authURL = MCPOAuthHelper.generateAuthURL(config: config, state: UUID().uuidString)
        
        let callbackURL = try await performOAuthFlow(authURL: authURL)
        
        guard let code = extractCode(from: callbackURL) else {
            throw OAuthError.invalidCallback
        }
        
        let tokens = try await MCPOAuthHelper.exchangeCodeForTokens(config: config, code: code)
        
        let credential = MCPCredential(
            serverId: "google_drive",
            type: .oauth,
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            apiKey: nil,
            expiresAt: Date().addingTimeInterval(TimeInterval(tokens.expiresIn))
        )
        
        try credentialManager.store(credential, for: "google_drive")
    }
    
    // MARK: - Notion OAuth
    
    private func connectNotion() async throws {
        // Notion uses OAuth 2.0 with different endpoints
        let authURL = URL(string: "https://api.notion.com/v1/oauth/authorize?client_id=YOUR_CLIENT_ID&response_type=code&owner=user&redirect_uri=io.atlas.oauth:/oauth2redirect")!
        
        let callbackURL = try await performOAuthFlow(authURL: authURL)
        
        guard let code = extractCode(from: callbackURL) else {
            throw OAuthError.invalidCallback
        }
        
        // Exchange code for token (Notion-specific)
        let tokens = try await exchangeNotionCode(code)
        
        let credential = MCPCredential(
            serverId: "notion",
            type: .oauth,
            accessToken: tokens.accessToken,
            refreshToken: nil, // Notion tokens don't expire
            apiKey: nil,
            expiresAt: nil
        )
        
        try credentialManager.store(credential, for: "notion")
    }
    
    // MARK: - OAuth Flow
    
    private func performOAuthFlow(authURL: URL) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "io.atlas.oauth"
            ) { callbackURL, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let callbackURL = callbackURL else {
                    continuation.resume(throwing: OAuthError.noCallback)
                    return
                }
                
                continuation.resume(returning: callbackURL)
            }
            
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            
            self.authSession = session
            session.start()
        }
    }
    
    private func extractCode(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return nil
        }
        
        return queryItems.first(where: { $0.name == "code" })?.value
    }
    
    private func exchangeNotionCode(_ code: String) async throws -> (accessToken: String, refreshToken: String?) {
        // Notion-specific token exchange
        // This is a simplified version
        let url = URL(string: "https://api.notion.com/v1/oauth/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": "io.atlas.oauth:/oauth2redirect"
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            throw OAuthError.tokenExchangeFailed
        }
        
        return (accessToken, nil)
    }
    
    // MARK: - Persistence
    
    private func loadConnectedServices() {
        connectedServices.removeAll()
        for service in ServiceType.allCases {
            if isConnected(service) {
                connectedServices.insert(service)
            }
        }
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension OAuthManager: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(iOS)
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        #else
        return NSApplication.shared.windows.first ?? ASPresentationAnchor()
        #endif
    }
}

// MARK: - Errors

public enum OAuthError: LocalizedError {
    case invalidCallback
    case noCallback
    case tokenExchangeFailed
    case userCancelled
    
    public var errorDescription: String? {
        switch self {
        case .invalidCallback:
            return "Invalid OAuth callback received"
        case .noCallback:
            return "No callback URL received"
        case .tokenExchangeFailed:
            return "Failed to exchange authorization code for tokens"
        case .userCancelled:
            return "OAuth flow cancelled by user"
        }
    }
}

