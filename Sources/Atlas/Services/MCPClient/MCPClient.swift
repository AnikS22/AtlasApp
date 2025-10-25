import Foundation
import Combine

// MARK: - MCP Client Protocol

protocol MCPClientProtocol {
    /// Connect to MCP server
    func connect() async throws

    /// Disconnect from MCP server
    func disconnect() async

    /// List available tools
    func listTools() async throws -> [MCPTool]

    /// Call a tool with parameters
    func callTool(name: String, parameters: [String: Any]) async throws -> MCPToolResult

    /// Send raw MCP request
    func sendRequest(method: String, params: [String: Any]?) async throws -> MCPResponse

    /// Check connection status
    var isConnected: Bool { get }

    /// Server configuration
    var config: MCPServerConfig { get }
}

// MARK: - MCP Client Implementation

final class MCPClient: MCPClientProtocol {
    private let transport: MCPTransport
    private let credentialManager: MCPCredentialManager
    private let auditLogger: MCPAuditLogger
    private let redactor: MCPDataRedactor

    let config: MCPServerConfig

    private var cachedTools: [MCPTool]?
    private let toolCacheLock = NSLock()

    var isConnected: Bool {
        transport.isConnected
    }

    // MARK: - Initialization

    init(config: MCPServerConfig) throws {
        self.config = config
        self.credentialManager = .shared
        self.auditLogger = .shared
        self.redactor = MCPDataRedactor()

        // Initialize appropriate transport
        switch config.transport {
        case .websocket:
            guard let url = URL(string: config.endpoint) else {
                throw MCPClientError.transportError("Invalid WebSocket URL: \(config.endpoint)")
            }
            self.transport = WebSocketMCPTransport(url: url)

        case .stdio:
            let components = config.endpoint.split(separator: " ")
            guard !components.isEmpty else {
                throw MCPClientError.transportError("Invalid stdio command: \(config.endpoint)")
            }
            let executable = String(components[0])
            let arguments = components.dropFirst().map { String($0) }
            self.transport = StdioMCPTransport(executable: executable, arguments: arguments)

        case .http:
            guard let url = URL(string: config.endpoint) else {
                throw MCPClientError.transportError("Invalid HTTP URL: \(config.endpoint)")
            }
            self.transport = HTTPMCPTransport(baseURL: url)
        }
    }

    // MARK: - Connection Management

    func connect() async throws {
        // Authenticate if required
        if config.credentialType != .none {
            try await authenticateIfNeeded()
        }

        // Connect transport
        try await transport.connect()

        // Discover tools
        _ = try await listTools()
    }

    func disconnect() async {
        await transport.disconnect()
        toolCacheLock.lock()
        cachedTools = nil
        toolCacheLock.unlock()
    }

    // MARK: - Tool Operations

    func listTools() async throws -> [MCPTool] {
        // Check cache
        toolCacheLock.lock()
        if let cached = cachedTools {
            toolCacheLock.unlock()
            return cached
        }
        toolCacheLock.unlock()

        // Request tools from server
        let response = try await sendRequest(method: "tools/list", params: nil)

        guard let result = response.result else {
            throw MCPClientError.invalidResponse
        }

        guard let toolsArray = result.arrayValue as? [[String: Any]] else {
            throw MCPClientError.invalidResponse
        }

        let tools: [MCPTool] = try toolsArray.map { toolDict in
            guard let name = toolDict["name"] as? String,
                  let description = toolDict["description"] as? String,
                  let schemaDict = toolDict["inputSchema"] as? [String: Any] else {
                throw MCPClientError.invalidResponse
            }

            let schemaData = try JSONSerialization.data(withJSONObject: schemaDict)
            let schema = try JSONDecoder().decode(JSONSchema.self, from: schemaData)

            return MCPTool(name: name, description: description, inputSchema: schema)
        }

        // Cache tools
        toolCacheLock.lock()
        cachedTools = tools
        toolCacheLock.unlock()

        return tools
    }

    func callTool(name: String, parameters: [String: Any]) async throws -> MCPToolResult {
        let startTime = Date()

        // Validate tool exists
        let tools = try await listTools()
        guard tools.contains(where: { $0.name == name }) else {
            throw MCPClientError.toolNotFound(name)
        }

        // Redact parameters for audit log
        let redactedParams = redactor.redactParameters(parameters)

        do {
            // Send tool call request
            let response = try await sendRequest(
                method: "tools/call",
                params: [
                    "name": name,
                    "arguments": parameters
                ]
            )

            let duration = Int(Date().timeIntervalSince(startTime) * 1000)

            // Parse result
            guard let result = response.result else {
                // Log failure
                auditLogger.log(
                    serverId: config.id,
                    method: "tools/call:\(name)",
                    redactedParams: redactedParams,
                    success: false,
                    errorCode: response.error?.code,
                    durationMs: duration
                )

                if let error = response.error {
                    throw MCPClientError.serverError(error)
                }
                throw MCPClientError.invalidResponse
            }

            // Decode tool result
            let resultData = try JSONSerialization.data(withJSONObject: result.dictionaryValue ?? [:])
            let toolResult = try JSONDecoder().decode(MCPToolResult.self, from: resultData)

            // Log success
            auditLogger.log(
                serverId: config.id,
                method: "tools/call:\(name)",
                redactedParams: redactedParams,
                success: true,
                errorCode: nil,
                durationMs: duration
            )

            return toolResult

        } catch {
            let duration = Int(Date().timeIntervalSince(startTime) * 1000)

            // Log error
            auditLogger.log(
                serverId: config.id,
                method: "tools/call:\(name)",
                redactedParams: redactedParams,
                success: false,
                errorCode: (error as? MCPClientError)?.code,
                durationMs: duration
            )

            throw error
        }
    }

    func sendRequest(method: String, params: [String: Any]?) async throws -> MCPResponse {
        let request = MCPRequest(
            method: method,
            params: params?.toAnyCodable().mapValues { AnyCodable($0.value) }
        )

        return try await transport.send(request)
    }

    // MARK: - Authentication

    private func authenticateIfNeeded() async throws {
        guard config.credentialType != .none else { return }

        // Check if we have valid credentials
        if credentialManager.hasValidCredential(for: config.id) {
            return
        }

        // Credential expired or missing
        switch config.credentialType {
        case .oauth:
            throw MCPClientError.authenticationRequired

        case .apiKey:
            // Verify API key exists
            _ = try credentialManager.retrieveAPIKey(for: config.id)

        case .basic:
            throw MCPClientError.authenticationRequired

        case .none:
            break
        }
    }

    /// Attach authentication to request if needed
    private func attachAuthentication(to request: inout URLRequest) throws {
        guard config.credentialType != .none else { return }

        switch config.credentialType {
        case .oauth:
            let credential = try credentialManager.retrieve(for: config.id)
            if let accessToken = credential.accessToken {
                request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            }

        case .apiKey:
            let apiKey = try credentialManager.retrieveAPIKey(for: config.id)
            request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")

        case .basic:
            let credential = try credentialManager.retrieve(for: config.id)
            if let username = credential.accessToken, let password = credential.apiKey {
                let credentials = "\(username):\(password)".data(using: .utf8)?.base64EncodedString() ?? ""
                request.addValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
            }

        case .none:
            break
        }
    }
}

// MARK: - Data Redactor

/// Redacts sensitive data from MCP requests for privacy
final class MCPDataRedactor {
    private let sensitiveKeys = Set([
        "password",
        "token",
        "secret",
        "key",
        "credential",
        "auth",
        "api_key",
        "access_token",
        "refresh_token",
        "private_key",
        "content", // Don't leak email/document content
        "body",
        "text",
        "message"
    ])

    /// Redact sensitive parameters, keeping only parameter names
    func redactParameters(_ parameters: [String: Any]) -> String {
        let keys = parameters.keys.sorted()
        return "{\(keys.joined(separator: ", "))}"
    }

    /// Check if key is sensitive
    func isSensitive(_ key: String) -> Bool {
        let lowercased = key.lowercased()
        return sensitiveKeys.contains { lowercased.contains($0) }
    }

    /// Redact dictionary recursively
    func redactDictionary(_ dict: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in dict {
            if isSensitive(key) {
                result[key] = "[REDACTED]"
            } else if let nestedDict = value as? [String: Any] {
                result[key] = redactDictionary(nestedDict)
            } else if let array = value as? [[String: Any]] {
                result[key] = array.map { redactDictionary($0) }
            } else {
                result[key] = value
            }
        }
        return result
    }
}

// MARK: - Audit Logger

/// Logs MCP requests for audit and debugging
final class MCPAuditLogger {
    static let shared = MCPAuditLogger()

    private let queue = DispatchQueue(label: "io.atlas.mcp.audit")
    private var logs: [MCPAuditLog] = []
    private let maxLogs = 1000

    private init() {}

    func log(
        serverId: String,
        method: String,
        redactedParams: String,
        success: Bool,
        errorCode: Int?,
        durationMs: Int
    ) {
        let log = MCPAuditLog(
            serverId: serverId,
            method: method,
            redactedParams: redactedParams,
            success: success,
            errorCode: errorCode,
            durationMs: durationMs
        )

        queue.async {
            self.logs.append(log)

            // Keep only last N logs
            if self.logs.count > self.maxLogs {
                self.logs.removeFirst(self.logs.count - self.maxLogs)
            }

            // In production, send to analytics/monitoring service
            #if DEBUG
            print("📊 MCP Audit: \(log.method) [\(log.success ? "✓" : "✗")] \(log.durationMs)ms")
            #endif
        }
    }

    func getLogs(limit: Int = 100) -> [MCPAuditLog] {
        queue.sync {
            Array(logs.suffix(limit))
        }
    }

    func clearLogs() {
        queue.async {
            self.logs.removeAll()
        }
    }
}

// MARK: - Connection Pool Manager

/// Manages multiple MCP client connections
final class MCPConnectionPool {
    static let shared = MCPConnectionPool()

    private var clients: [String: MCPClient] = [:]
    private let lock = NSLock()

    private init() {}

    /// Get or create client for server config
    func getClient(for config: MCPServerConfig) throws -> MCPClient {
        lock.lock()
        defer { lock.unlock() }

        if let existing = clients[config.id] {
            return existing
        }

        let client = try MCPClient(config: config)
        clients[config.id] = client
        return client
    }

    /// Remove client from pool
    func removeClient(for serverId: String) async {
        lock.lock()
        let client = clients.removeValue(forKey: serverId)
        lock.unlock()

        await client?.disconnect()
    }

    /// Disconnect all clients
    func disconnectAll() async {
        lock.lock()
        let allClients = Array(clients.values)
        clients.removeAll()
        lock.unlock()

        await withTaskGroup(of: Void.self) { group in
            for client in allClients {
                group.addTask {
                    await client.disconnect()
                }
            }
        }
    }
}

// MARK: - Retry Logic

extension MCPClient {
    /// Call tool with automatic retry on transient errors
    func callToolWithRetry(
        name: String,
        parameters: [String: Any],
        maxRetries: Int = 3,
        backoff: TimeInterval = 1.0
    ) async throws -> MCPToolResult {
        var lastError: Error?

        for attempt in 0..<maxRetries {
            do {
                return try await callTool(name: name, parameters: parameters)
            } catch let error as MCPClientError {
                lastError = error

                // Don't retry on client errors
                switch error {
                case .toolNotFound, .invalidToolParameters, .authenticationRequired:
                    throw error
                default:
                    break
                }

                // Exponential backoff
                if attempt < maxRetries - 1 {
                    let delay = backoff * pow(2.0, Double(attempt))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            } catch {
                lastError = error
            }
        }

        throw lastError ?? MCPClientError.requestTimeout
    }
}

// MARK: - Helper Extensions

extension MCPClientError {
    var code: Int? {
        switch self {
        case .serverError(let mcpError):
            return mcpError.code
        default:
            return nil
        }
    }
}
