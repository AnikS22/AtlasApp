import Foundation

// MARK: - MCP Client Usage Examples

/**
 This file demonstrates how to use the MCP client infrastructure in Atlas.

 Key Features Demonstrated:
 1. Multi-transport support (WebSocket, stdio, HTTP)
 2. Secure credential management with Keychain
 3. OAuth token handling and refresh
 4. Privacy-first data redaction
 5. Audit logging
 6. Retry logic with exponential backoff
 7. Connection pooling
 */

// MARK: - Example 1: Basic Gmail Integration

func exampleGmailUsage() async throws {
    // Setup Gmail client
    let manager = MCPManager.shared
    try await manager.setupGmail()

    guard let gmail = manager.gmail else {
        print("Gmail client not initialized")
        return
    }

    // List recent messages
    let messages = try await gmail.listMessages(maxResults: 5)
    print("Recent messages: \(messages.count)")

    // Search for specific emails
    let searchResults = try await gmail.searchMessages(
        query: "from:someone@example.com subject:important",
        maxResults: 10
    )
    print("Search results: \(searchResults.count)")

    // Get full message
    if let firstMessage = messages.first,
       let messageId = firstMessage["id"] as? String {
        let fullMessage = try await gmail.getMessage(id: messageId)
        print("Message subject: \(fullMessage["subject"] ?? "No subject")")
    }

    // Send email
    let sentMessageId = try await gmail.sendMessage(
        to: "recipient@example.com",
        subject: "Hello from Atlas",
        body: "This email was sent via Atlas MCP integration."
    )
    print("Sent message ID: \(sentMessageId)")
}

// MARK: - Example 2: Notion Workspace Integration

func exampleNotionUsage() async throws {
    // Setup Notion client with API key
    let apiKey = "secret_xxxxxxxxxxxxx" // From Keychain in production
    let manager = MCPManager.shared
    try await manager.setupNotion(apiKey: apiKey)

    guard let notion = manager.notion else {
        print("Notion client not initialized")
        return
    }

    // Search workspace
    let searchResults = try await notion.search(query: "project")
    print("Found \(searchResults.count) pages/databases")

    // Get specific page
    if let firstResult = searchResults.first,
       let pageId = firstResult["id"] as? String {
        let page = try await notion.getPage(pageId: pageId)
        print("Page title: \(page["title"] ?? "Untitled")")
    }

    // Query database
    let databaseId = "xxxxx-database-id-xxxxx"
    let entries = try await notion.queryDatabase(
        databaseId: databaseId,
        filter: [
            "property": "Status",
            "select": ["equals": "Active"]
        ]
    )
    print("Active entries: \(entries.count)")

    // Create new page
    let parentId = "xxxxx-parent-id-xxxxx"
    let newPageId = try await notion.createPage(
        parentId: parentId,
        title: "Atlas Meeting Notes",
        content: [
            ["type": "paragraph", "text": "Notes from today's meeting..."]
        ]
    )
    print("Created page: \(newPageId)")
}

// MARK: - Example 3: Google Drive Integration

func exampleDriveUsage() async throws {
    // Setup Drive client
    let manager = MCPManager.shared
    try await manager.setupDrive()

    guard let drive = manager.drive else {
        print("Drive client not initialized")
        return
    }

    // List recent files
    let files = try await drive.listFiles(pageSize: 10)
    print("Recent files: \(files.count)")

    // Search for documents
    let documents = try await drive.searchFiles(
        query: "mimeType='application/vnd.google-apps.document'",
        pageSize: 20
    )
    print("Found \(documents.count) Google Docs")

    // Read file content
    if let firstFile = files.first,
       let fileId = firstFile["id"] as? String {
        let content = try await drive.readFile(fileId: fileId)
        print("File content length: \(content.count) characters")
    }

    // Create new file
    let newFileId = try await drive.createFile(
        name: "Atlas Notes.txt",
        content: "These are my notes from Atlas AI assistant.",
        mimeType: "text/plain"
    )
    print("Created file: \(newFileId)")
}

// MARK: - Example 4: Custom MCP Server (WebSocket)

func exampleCustomWebSocketServer() async throws {
    // Configure custom MCP server
    let config = MCPServerConfig(
        name: "Custom MCP Server",
        transport: .websocket,
        endpoint: "ws://localhost:8080/mcp",
        credentialType: .apiKey
    )

    // Store API key
    try MCPCredentialManager.shared.storeAPIKey(
        "custom-api-key-here",
        for: config.id
    )

    // Create client
    let client = try MCPClient(config: config)

    // Connect
    try await client.connect()

    // List available tools
    let tools = try await client.listTools()
    print("Available tools: \(tools.map { $0.name })")

    // Call a tool
    let result = try await client.callTool(
        name: "example_tool",
        parameters: [
            "input": "Hello, world!",
            "option": "verbose"
        ]
    )

    print("Tool result: \(result.content)")

    // Disconnect
    await client.disconnect()
}

// MARK: - Example 5: Retry Logic with Exponential Backoff

func exampleRetryLogic() async throws {
    let manager = MCPManager.shared
    try await manager.setupGmail()

    guard let gmail = manager.gmail else { return }

    // This will automatically retry up to 3 times with exponential backoff
    // if the request fails due to transient errors
    let messages = try await gmail.client.callToolWithRetry(
        name: "gmail_list_messages",
        parameters: ["maxResults": 10],
        maxRetries: 3,
        backoff: 1.0 // Initial backoff of 1 second
    )

    print("Messages retrieved with retry: \(messages.content.count)")
}

// MARK: - Example 6: Audit Log Review

func exampleAuditLogReview() {
    let logger = MCPAuditLogger.shared

    // Get recent audit logs
    let logs = logger.getLogs(limit: 50)

    print("=== MCP Audit Logs ===")
    for log in logs {
        let status = log.success ? "✓" : "✗"
        print("\(status) [\(log.timestamp)] \(log.method)")
        print("   Server: \(log.serverId)")
        print("   Params: \(log.redactedParams)")
        print("   Duration: \(log.durationMs)ms")
        if let errorCode = log.errorCode {
            print("   Error Code: \(errorCode)")
        }
        print("")
    }
}

// MARK: - Example 7: OAuth Flow (Gmail/Drive)

func exampleOAuthFlow() async throws {
    let config = MCPOAuthHelper.getGmailConfig()
    let state = UUID().uuidString

    // Step 1: Generate authorization URL
    let authURL = MCPOAuthHelper.generateAuthURL(config: config, state: state)
    print("Open this URL to authorize: \(authURL)")

    // Step 2: After user authorizes, you'll receive an authorization code
    // In a real app, this would come from the OAuth redirect
    let authorizationCode = "received_from_oauth_redirect"

    // Step 3: Exchange code for tokens
    let (accessToken, refreshToken, expiresIn) = try await MCPOAuthHelper.exchangeCodeForTokens(
        config: config,
        code: authorizationCode
    )

    // Step 4: Store credential
    let credential = MCPCredential(
        serverId: "gmail-server-id",
        type: .oauth,
        accessToken: accessToken,
        refreshToken: refreshToken,
        apiKey: nil,
        expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn))
    )

    try MCPCredentialManager.shared.store(credential, for: "gmail-server-id")

    print("OAuth tokens stored successfully")

    // Step 5: Token refresh (automatic when needed)
    let refreshedCredential = try await MCPCredentialManager.shared.refreshTokenIfNeeded(
        for: "gmail-server-id"
    ) { refreshToken in
        return try await MCPOAuthHelper.refreshAccessToken(
            config: config,
            refreshToken: refreshToken
        )
    }

    print("Access token refreshed: \(refreshedCredential.accessToken?.prefix(10) ?? "")...")
}

// MARK: - Example 8: Connection Pool Management

func exampleConnectionPooling() async throws {
    let pool = MCPConnectionPool.shared

    // Get clients from pool (reuses existing connections)
    let gmailConfig = MCPServerConfig(
        name: "Gmail",
        transport: .stdio,
        endpoint: "node /path/to/gmail-server/dist/index.js",
        credentialType: .oauth
    )

    let client1 = try pool.getClient(for: gmailConfig)
    let client2 = try pool.getClient(for: gmailConfig) // Same instance

    print("Clients are same instance: \(client1 === client2)")

    // Use client
    try await client1.connect()
    let tools = try await client1.listTools()
    print("Available tools: \(tools.count)")

    // Disconnect specific client
    await pool.removeClient(for: gmailConfig.id)

    // Or disconnect all
    await pool.disconnectAll()
}

// MARK: - Example 9: Error Handling

func exampleErrorHandling() async {
    do {
        let manager = MCPManager.shared
        try await manager.setupGmail()

        guard let gmail = manager.gmail else { return }

        // This might fail
        let messages = try await gmail.listMessages(maxResults: 10)
        print("Success: \(messages.count) messages")

    } catch MCPClientError.notConnected {
        print("Error: MCP client is not connected")

    } catch MCPClientError.authenticationRequired {
        print("Error: Authentication is required. Please log in.")

    } catch MCPClientError.credentialExpired {
        print("Error: Credentials have expired. Refreshing...")
        // Trigger OAuth refresh flow

    } catch MCPClientError.toolNotFound(let toolName) {
        print("Error: Tool '\(toolName)' not found on server")

    } catch MCPClientError.rateLimitExceeded {
        print("Error: Rate limit exceeded. Please try again later.")

    } catch MCPClientError.serverError(let mcpError) {
        print("Server error [\(mcpError.code)]: \(mcpError.message)")

    } catch {
        print("Unexpected error: \(error)")
    }
}

// MARK: - Example 10: Integration with Atlas Chat

func exampleAtlasIntegration() async throws {
    // This shows how to use MCP tools in the Atlas conversation flow

    let manager = MCPManager.shared
    try await manager.setupGmail()
    try await manager.setupNotion(apiKey: "stored-api-key")

    // User asks: "What are my recent emails?"
    if let gmail = manager.gmail {
        let messages = try await gmail.listMessages(maxResults: 5)

        let summary = messages.compactMap { message -> String? in
            guard let subject = message["snippet"] as? String else { return nil }
            return "• \(subject)"
        }.joined(separator: "\n")

        let response = """
        Here are your 5 most recent emails:
        \(summary)
        """

        print(response)
    }

    // User asks: "Save this to my Notion workspace"
    if let notion = manager.notion {
        let pageId = try await notion.createPage(
            parentId: "workspace-id",
            title: "Conversation Summary",
            content: [
                ["type": "paragraph", "text": "Summary of conversation..."]
            ]
        )

        print("Saved to Notion: \(pageId)")
    }
}

// MARK: - Main Demo Function

func runMCPClientDemo() async {
    print("=== Atlas MCP Client Demo ===\n")

    do {
        print("1. Gmail Integration")
        try await exampleGmailUsage()
        print("\n---\n")

        print("2. Notion Integration")
        try await exampleNotionUsage()
        print("\n---\n")

        print("3. Google Drive Integration")
        try await exampleDriveUsage()
        print("\n---\n")

        print("4. Audit Log Review")
        exampleAuditLogReview()
        print("\n---\n")

        print("5. Connection Pooling")
        try await exampleConnectionPooling()
        print("\n---\n")

        print("Demo completed successfully!")

    } catch {
        print("Demo error: \(error)")
    }
}
