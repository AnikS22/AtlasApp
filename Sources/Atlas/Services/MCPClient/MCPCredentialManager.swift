import Foundation
import Security

// MARK: - Credential Manager

/// Manages secure storage and retrieval of MCP server credentials
final class MCPCredentialManager {
    static let shared = MCPCredentialManager()

    private let keychainService = "io.atlas.mcp.credentials"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Credential Operations

    /// Store credential securely in Keychain
    func store(_ credential: MCPCredential, for serverId: String) throws {
        let data = try encoder.encode(credential)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: serverId,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        // Delete existing item if present
        SecItemDelete(query as CFDictionary)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    /// Retrieve credential from Keychain
    func retrieve(for serverId: String) throws -> MCPCredential {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: serverId,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            throw KeychainError.loadFailed(status)
        }

        guard let data = result as? Data else {
            throw KeychainError.invalidData
        }

        return try decoder.decode(MCPCredential.self, from: data)
    }

    /// Delete credential from Keychain
    func delete(for serverId: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: serverId
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    /// Check if credential exists and is valid
    func hasValidCredential(for serverId: String) -> Bool {
        guard let credential = try? retrieve(for: serverId) else {
            return false
        }
        return !credential.isExpired
    }

    // MARK: - OAuth Token Management

    /// Refresh OAuth token if expired
    func refreshTokenIfNeeded(for serverId: String, refreshHandler: @escaping (String) async throws -> (accessToken: String, expiresIn: Int)) async throws -> MCPCredential {
        let credential = try retrieve(for: serverId)

        guard credential.isExpired else {
            return credential
        }

        guard let refreshToken = credential.refreshToken else {
            throw MCPClientError.authenticationRequired
        }

        // Call refresh handler
        let (newAccessToken, expiresIn) = try await refreshHandler(refreshToken)

        // Create new credential
        let newCredential = MCPCredential(
            serverId: serverId,
            type: credential.type,
            accessToken: newAccessToken,
            refreshToken: refreshToken,
            apiKey: credential.apiKey,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn))
        )

        // Store updated credential
        try store(newCredential, for: serverId)

        return newCredential
    }

    // MARK: - API Key Management

    /// Store API key for server
    func storeAPIKey(_ apiKey: String, for serverId: String) throws {
        let credential = MCPCredential(
            serverId: serverId,
            type: .apiKey,
            accessToken: nil,
            refreshToken: nil,
            apiKey: apiKey,
            expiresAt: nil
        )
        try store(credential, for: serverId)
    }

    /// Retrieve API key for server
    func retrieveAPIKey(for serverId: String) throws -> String {
        let credential = try retrieve(for: serverId)
        guard let apiKey = credential.apiKey else {
            throw MCPClientError.authenticationRequired
        }
        return apiKey
    }
}

// MARK: - OAuth Helper

/// Helper for OAuth2 flow (Gmail, Google Drive)
final class MCPOAuthHelper {
    struct OAuthConfig {
        let clientId: String
        let clientSecret: String
        let scopes: [String]
        let redirectUri: String
        let authEndpoint: URL
        let tokenEndpoint: URL
    }

    static func getGmailConfig() -> OAuthConfig {
        OAuthConfig(
            clientId: "<YOUR_CLIENT_ID>",
            clientSecret: "<YOUR_CLIENT_SECRET>",
            scopes: ["https://www.googleapis.com/auth/gmail.modify"],
            redirectUri: "io.atlas.oauth:/oauth2redirect",
            authEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!
        )
    }

    static func getDriveConfig() -> OAuthConfig {
        OAuthConfig(
            clientId: "<YOUR_CLIENT_ID>",
            clientSecret: "<YOUR_CLIENT_SECRET>",
            scopes: [
                "https://www.googleapis.com/auth/drive.readonly",
                "https://www.googleapis.com/auth/drive.file"
            ],
            redirectUri: "io.atlas.oauth:/oauth2redirect",
            authEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!
        )
    }

    /// Generate authorization URL for OAuth flow
    static func generateAuthURL(config: OAuthConfig, state: String) -> URL {
        var components = URLComponents(url: config.authEndpoint, resolvingAgainstBaseURL: false)!

        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "redirect_uri", value: config.redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]

        return components.url!
    }

    /// Exchange authorization code for tokens
    static func exchangeCodeForTokens(config: OAuthConfig, code: String) async throws -> (accessToken: String, refreshToken: String, expiresIn: Int) {
        var request = URLRequest(url: config.tokenEndpoint)
        request.httpMethod = "POST"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let parameters = [
            "client_id": config.clientId,
            "client_secret": config.clientSecret,
            "code": code,
            "redirect_uri": config.redirectUri,
            "grant_type": "authorization_code"
        ]

        request.httpBody = parameters
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw MCPClientError.authenticationRequired
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard let accessToken = json?["access_token"] as? String,
              let refreshToken = json?["refresh_token"] as? String,
              let expiresIn = json?["expires_in"] as? Int else {
            throw MCPClientError.invalidResponse
        }

        return (accessToken, refreshToken, expiresIn)
    }

    /// Refresh access token using refresh token
    static func refreshAccessToken(config: OAuthConfig, refreshToken: String) async throws -> (accessToken: String, expiresIn: Int) {
        var request = URLRequest(url: config.tokenEndpoint)
        request.httpMethod = "POST"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let parameters = [
            "client_id": config.clientId,
            "client_secret": config.clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]

        request.httpBody = parameters
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw MCPClientError.authenticationRequired
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard let accessToken = json?["access_token"] as? String,
              let expiresIn = json?["expires_in"] as? Int else {
            throw MCPClientError.invalidResponse
        }

        return (accessToken, expiresIn)
    }
}

// MARK: - Keychain Errors

enum KeychainError: Error, LocalizedError {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save to Keychain: \(status)"
        case .loadFailed(let status):
            return "Failed to load from Keychain: \(status)"
        case .deleteFailed(let status):
            return "Failed to delete from Keychain: \(status)"
        case .invalidData:
            return "Invalid data retrieved from Keychain"
        }
    }
}
