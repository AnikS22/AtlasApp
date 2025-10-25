# MCP Client

Model Context Protocol client for iOS with multi-transport support.

## Features
- WebSocket, HTTP, and stdio transports
- Gmail, Notion, and Google Drive integration
- Secure credential management
- Data redaction for privacy
- Audit logging

## Usage
```swift
let mcpClient = MCPClient()

// Connect to Gmail server
let gmailConfig = ServerConfig(
    name: "gmail",
    transport: .webSocket(URL(string: "ws://localhost:3000")!),
    credentials: Credentials(type: .oauth, token: "...")
)
try await mcpClient.connect(to: gmailConfig)

// Execute tool
let result = try await mcpClient.execute(
    tool: "gmail_send_message",
    server: "gmail",
    parameters: [
        "to": "user@example.com",
        "subject": "Hello",
        "body": "Test message"
    ]
)
```
