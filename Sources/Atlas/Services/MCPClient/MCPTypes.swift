import Foundation

// MARK: - MCP Protocol Types

/// MCP message type enumeration
enum MCPMessageType: String, Codable {
    case request
    case response
    case notification
    case error
}

/// MCP protocol version
struct MCPVersion {
    static let current = "1.0"
}

/// MCP request message
struct MCPRequest: Codable {
    let jsonrpc: String
    let id: String
    let method: String
    let params: AnyCodable?

    init(id: String = UUID().uuidString, method: String, params: AnyCodable? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }
}

/// MCP response message
struct MCPResponse: Codable {
    let jsonrpc: String
    let id: String
    let result: AnyCodable?
    let error: MCPError?

    var isSuccess: Bool { error == nil }
}

/// MCP notification message (no response expected)
struct MCPNotification: Codable {
    let jsonrpc: String
    let method: String
    let params: AnyCodable?

    init(method: String, params: AnyCodable? = nil) {
        self.jsonrpc = "2.0"
        self.method = method
        self.params = params
    }
}

/// MCP error structure
struct MCPError: Codable, Error {
    let code: Int
    let message: String
    let data: AnyCodable?

    /// Standard JSON-RPC error codes
    enum StandardCode: Int {
        case parseError = -32700
        case invalidRequest = -32600
        case methodNotFound = -32601
        case invalidParams = -32602
        case internalError = -32603

        // MCP-specific codes
        case toolNotFound = -32001
        case toolExecutionError = -32002
        case authenticationFailed = -32003
        case rateLimitExceeded = -32004
    }

    init(code: Int, message: String, data: AnyCodable? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }

    init(standardCode: StandardCode, message: String, data: AnyCodable? = nil) {
        self.code = standardCode.rawValue
        self.message = message
        self.data = data
    }
}

// MARK: - MCP Tool Types

/// MCP tool definition
struct MCPTool: Codable, Identifiable {
    let name: String
    let description: String
    let inputSchema: JSONSchema

    var id: String { name }
}

/// JSON Schema representation
struct JSONSchema: Codable {
    let type: String
    let properties: [String: SchemaProperty]?
    let required: [String]?
    let additionalProperties: Bool?

    struct SchemaProperty: Codable {
        let type: String
        let description: String?
        let items: Items?
        let `enum`: [String]?

        struct Items: Codable {
            let type: String
        }
    }
}

/// Tool execution result
struct MCPToolResult: Codable {
    let content: [MCPContent]
    let isError: Bool

    init(content: [MCPContent], isError: Bool = false) {
        self.content = content
        self.isError = isError
    }
}

/// MCP content block
struct MCPContent: Codable {
    let type: ContentType
    let text: String?
    let data: String? // Base64 encoded
    let mimeType: String?

    enum ContentType: String, Codable {
        case text
        case image
        case resource
    }

    init(type: ContentType, text: String? = nil, data: String? = nil, mimeType: String? = nil) {
        self.type = type
        self.text = text
        self.data = data
        self.mimeType = mimeType
    }
}

// MARK: - MCP Server Configuration

/// Configuration for connecting to an MCP server
struct MCPServerConfig: Codable, Identifiable {
    let id: String
    let name: String
    let transport: TransportType
    let endpoint: String
    let credentialType: CredentialType
    let metadata: [String: String]?

    enum TransportType: String, Codable {
        case websocket
        case stdio
        case http
    }

    enum CredentialType: String, Codable {
        case none
        case oauth
        case apiKey
        case basic
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        transport: TransportType,
        endpoint: String,
        credentialType: CredentialType,
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.name = name
        self.transport = transport
        self.endpoint = endpoint
        self.credentialType = credentialType
        self.metadata = metadata
    }
}

// MARK: - MCP Credentials

/// Credential storage for MCP servers
struct MCPCredential: Codable {
    let serverId: String
    let type: MCPServerConfig.CredentialType
    let accessToken: String?
    let refreshToken: String?
    let apiKey: String?
    let expiresAt: Date?

    var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() >= expiresAt
    }
}

// MARK: - AnyCodable Wrapper

/// Type-erased Codable wrapper for dynamic JSON values
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            self.value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "AnyCodable value cannot be decoded"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            let context = EncodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "AnyCodable value cannot be encoded"
            )
            throw EncodingError.invalidValue(value, context)
        }
    }
}

// MARK: - MCP Client Errors

enum MCPClientError: Error, LocalizedError {
    case notConnected
    case connectionFailed(Error)
    case transportError(String)
    case authenticationRequired
    case credentialExpired
    case invalidResponse
    case requestTimeout
    case serverError(MCPError)
    case toolNotFound(String)
    case invalidToolParameters
    case rateLimitExceeded

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "MCP client is not connected to server"
        case .connectionFailed(let error):
            return "Failed to connect to MCP server: \(error.localizedDescription)"
        case .transportError(let message):
            return "Transport error: \(message)"
        case .authenticationRequired:
            return "Authentication is required for this MCP server"
        case .credentialExpired:
            return "Credential has expired and needs refresh"
        case .invalidResponse:
            return "Received invalid response from MCP server"
        case .requestTimeout:
            return "Request to MCP server timed out"
        case .serverError(let mcpError):
            return "Server error: \(mcpError.message)"
        case .toolNotFound(let name):
            return "Tool '\(name)' not found on MCP server"
        case .invalidToolParameters:
            return "Invalid parameters provided for tool"
        case .rateLimitExceeded:
            return "Rate limit exceeded for MCP server"
        }
    }
}

// MARK: - MCP Audit Log

/// Audit log entry for MCP requests
struct MCPAuditLog: Codable {
    let id: String
    let timestamp: Date
    let serverId: String
    let method: String
    let redactedParams: String // Privacy: only parameter names, no values
    let success: Bool
    let errorCode: Int?
    let durationMs: Int

    init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        serverId: String,
        method: String,
        redactedParams: String,
        success: Bool,
        errorCode: Int? = nil,
        durationMs: Int
    ) {
        self.id = id
        self.timestamp = timestamp
        self.serverId = serverId
        self.method = method
        self.redactedParams = redactedParams
        self.success = success
        self.errorCode = errorCode
        self.durationMs = durationMs
    }
}

// MARK: - Helper Extensions

extension Dictionary where Key == String, Value == Any {
    /// Convert to AnyCodable-compatible dictionary
    func toAnyCodable() -> [String: AnyCodable] {
        return mapValues { AnyCodable($0) }
    }
}

extension AnyCodable {
    /// Extract dictionary from AnyCodable if possible
    var dictionaryValue: [String: Any]? {
        return value as? [String: Any]
    }

    /// Extract array from AnyCodable if possible
    var arrayValue: [Any]? {
        return value as? [Any]
    }

    /// Extract string from AnyCodable if possible
    var stringValue: String? {
        return value as? String
    }
}
