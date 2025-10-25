import Foundation

// MARK: - Gmail MCP Client

/// Specialized client for Gmail MCP server
final class GmailMCPClient {
    private let client: MCPClient

    init() throws {
        let config = MCPServerConfig(
            name: "Gmail",
            transport: .stdio,
            endpoint: "node /path/to/MCPServers/gmail-server/dist/index.js",
            credentialType: .oauth,
            metadata: [
                "scopes": "gmail.modify"
            ]
        )
        self.client = try MCPClient(config: config)
    }

    func connect() async throws {
        try await client.connect()
    }

    func disconnect() async {
        await client.disconnect()
    }

    // MARK: - Gmail Operations

    /// List Gmail messages with optional query
    func listMessages(query: String? = nil, maxResults: Int = 10) async throws -> [[String: Any]] {
        var params: [String: Any] = ["maxResults": maxResults]
        if let query = query {
            params["query"] = query
        }

        let result = try await client.callTool(name: "gmail_list_messages", parameters: params)

        guard let textContent = result.content.first?.text,
              let data = textContent.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = json["messages"] as? [[String: Any]] else {
            throw MCPClientError.invalidResponse
        }

        return messages
    }

    /// Get full message by ID
    func getMessage(id: String) async throws -> [String: Any] {
        let params = ["messageId": id]
        let result = try await client.callTool(name: "gmail_get_message", parameters: params)

        guard let textContent = result.content.first?.text,
              let data = textContent.data(using: .utf8),
              let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MCPClientError.invalidResponse
        }

        return message
    }

    /// Send email
    func sendMessage(to: String, subject: String, body: String) async throws -> String {
        let params: [String: Any] = [
            "to": to,
            "subject": subject,
            "body": body
        ]

        let result = try await client.callTool(name: "gmail_send_message", parameters: params)

        guard let textContent = result.content.first?.text,
              let data = textContent.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messageId = json["id"] as? String else {
            throw MCPClientError.invalidResponse
        }

        return messageId
    }

    /// Search messages
    func searchMessages(query: String, maxResults: Int = 20) async throws -> [[String: Any]] {
        let params: [String: Any] = [
            "query": query,
            "maxResults": maxResults
        ]

        let result = try await client.callTool(name: "gmail_search_messages", parameters: params)

        guard let textContent = result.content.first?.text,
              let data = textContent.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = json["messages"] as? [[String: Any]] else {
            throw MCPClientError.invalidResponse
        }

        return messages
    }
}

// MARK: - Notion MCP Client

/// Specialized client for Notion MCP server
final class NotionMCPClient {
    private let client: MCPClient

    init(apiKey: String) throws {
        let config = MCPServerConfig(
            name: "Notion",
            transport: .stdio,
            endpoint: "node /path/to/MCPServers/notion-server/dist/index.js",
            credentialType: .apiKey
        )
        self.client = try MCPClient(config: config)

        // Store API key
        try MCPCredentialManager.shared.storeAPIKey(apiKey, for: config.id)
    }

    func connect() async throws {
        try await client.connect()
    }

    func disconnect() async {
        await client.disconnect()
    }

    // MARK: - Notion Operations

    /// Search Notion workspace
    func search(query: String, filter: String? = nil) async throws -> [[String: Any]] {
        var params: [String: Any] = ["query": query]
        if let filter = filter {
            params["filter"] = filter
        }

        let result = try await client.callTool(name: "notion_search", parameters: params)

        guard let textContent = result.content.first?.text,
              let data = textContent.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            throw MCPClientError.invalidResponse
        }

        return results
    }

    /// Get page by ID
    func getPage(pageId: String) async throws -> [String: Any] {
        let params = ["pageId": pageId]
        let result = try await client.callTool(name: "notion_get_page", parameters: params)

        guard let textContent = result.content.first?.text,
              let data = textContent.data(using: .utf8),
              let page = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MCPClientError.invalidResponse
        }

        return page
    }

    /// Create new page
    func createPage(parentId: String, title: String, content: [[String: Any]]) async throws -> String {
        let params: [String: Any] = [
            "parentId": parentId,
            "title": title,
            "content": content
        ]

        let result = try await client.callTool(name: "notion_create_page", parameters: params)

        guard let textContent = result.content.first?.text,
              let data = textContent.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pageId = json["id"] as? String else {
            throw MCPClientError.invalidResponse
        }

        return pageId
    }

    /// Query database
    func queryDatabase(databaseId: String, filter: [String: Any]? = nil) async throws -> [[String: Any]] {
        var params: [String: Any] = ["databaseId": databaseId]
        if let filter = filter {
            params["filter"] = filter
        }

        let result = try await client.callTool(name: "notion_query_database", parameters: params)

        guard let textContent = result.content.first?.text,
              let data = textContent.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            throw MCPClientError.invalidResponse
        }

        return results
    }
}

// MARK: - Google Drive MCP Client

/// Specialized client for Google Drive MCP server
final class GoogleDriveMCPClient {
    private let client: MCPClient

    init() throws {
        let config = MCPServerConfig(
            name: "Google Drive",
            transport: .stdio,
            endpoint: "node /path/to/MCPServers/drive-server/dist/index.js",
            credentialType: .oauth,
            metadata: [
                "scopes": "drive.readonly,drive.file"
            ]
        )
        self.client = try MCPClient(config: config)
    }

    func connect() async throws {
        try await client.connect()
    }

    func disconnect() async {
        await client.disconnect()
    }

    // MARK: - Drive Operations

    /// List files
    func listFiles(query: String? = nil, pageSize: Int = 10) async throws -> [[String: Any]] {
        var params: [String: Any] = ["pageSize": pageSize]
        if let query = query {
            params["query"] = query
        }

        let result = try await client.callTool(name: "drive_list_files", parameters: params)

        guard let textContent = result.content.first?.text,
              let data = textContent.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = json["files"] as? [[String: Any]] else {
            throw MCPClientError.invalidResponse
        }

        return files
    }

    /// Get file metadata
    func getFile(fileId: String) async throws -> [String: Any] {
        let params = ["fileId": fileId]
        let result = try await client.callTool(name: "drive_get_file", parameters: params)

        guard let textContent = result.content.first?.text,
              let data = textContent.data(using: .utf8),
              let file = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MCPClientError.invalidResponse
        }

        return file
    }

    /// Read file content
    func readFile(fileId: String) async throws -> String {
        let params = ["fileId": fileId]
        let result = try await client.callTool(name: "drive_read_file", parameters: params)

        guard let textContent = result.content.first?.text else {
            throw MCPClientError.invalidResponse
        }

        return textContent
    }

    /// Create file
    func createFile(name: String, content: String, mimeType: String, folderId: String? = nil) async throws -> String {
        var params: [String: Any] = [
            "name": name,
            "content": content,
            "mimeType": mimeType
        ]
        if let folderId = folderId {
            params["folderId"] = folderId
        }

        let result = try await client.callTool(name: "drive_create_file", parameters: params)

        guard let textContent = result.content.first?.text,
              let data = textContent.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fileId = json["id"] as? String else {
            throw MCPClientError.invalidResponse
        }

        return fileId
    }

    /// Search files
    func searchFiles(query: String, pageSize: Int = 20) async throws -> [[String: Any]] {
        let params: [String: Any] = [
            "query": query,
            "pageSize": pageSize
        ]

        let result = try await client.callTool(name: "drive_search_files", parameters: params)

        guard let textContent = result.content.first?.text,
              let data = textContent.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = json["files"] as? [[String: Any]] else {
            throw MCPClientError.invalidResponse
        }

        return files
    }
}

// MARK: - MCP Manager

/// Central manager for all MCP server connections
final class MCPManager {
    static let shared = MCPManager()

    private var gmailClient: GmailMCPClient?
    private var notionClient: NotionMCPClient?
    private var driveClient: GoogleDriveMCPClient?

    private init() {}

    // MARK: - Setup

    func setupGmail() async throws {
        gmailClient = try GmailMCPClient()
        try await gmailClient?.connect()
    }

    func setupNotion(apiKey: String) async throws {
        notionClient = try NotionMCPClient(apiKey: apiKey)
        try await notionClient?.connect()
    }

    func setupDrive() async throws {
        driveClient = try GoogleDriveMCPClient()
        try await driveClient?.connect()
    }

    // MARK: - Access

    var gmail: GmailMCPClient? { gmailClient }
    var notion: NotionMCPClient? { notionClient }
    var drive: GoogleDriveMCPClient? { driveClient }

    // MARK: - Cleanup

    func disconnectAll() async {
        await gmailClient?.disconnect()
        await notionClient?.disconnect()
        await driveClient?.disconnect()

        gmailClient = nil
        notionClient = nil
        driveClient = nil
    }
}
