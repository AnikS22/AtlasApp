//
//  MCPClientTests.swift
//  AtlasTests
//
//  Unit tests for MCP client
//

import XCTest
@testable import Atlas

final class MCPClientTests: XCTestCase {

    func testMCPClientInitialization() throws {
        let config = MCPServerConfig(
            id: "test-server",
            name: "Test Server",
            endpoint: "http://localhost:3000",
            transport: .http,
            credentialType: .none,
            category: .dataManagement,
            enabled: true
        )

        let client = try MCPClient(config: config)
        XCTAssertNotNil(client, "MCP client should initialize")
        XCTAssertFalse(client.isConnected, "Client should not be connected initially")
    }

    func testMCPClientConfiguration() throws {
        let config = MCPServerConfig(
            id: "test-server",
            name: "Test Server",
            endpoint: "ws://localhost:8080",
            transport: .websocket,
            credentialType: .apiKey,
            category: .aiTools,
            enabled: true
        )

        let client = try MCPClient(config: config)
        XCTAssertEqual(client.config.id, "test-server")
        XCTAssertEqual(client.config.transport, .websocket)
        XCTAssertEqual(client.config.credentialType, .apiKey)
    }

    func testDataRedaction() throws {
        let redactor = MCPDataRedactor()

        let sensitiveData: [String: Any] = [
            "username": "testuser",
            "password": "secret123",
            "api_key": "sk-1234567890",
            "message": "Hello world"
        ]

        let redacted = redactor.redactDictionary(sensitiveData)

        XCTAssertEqual(redacted["username"] as? String, "testuser", "Non-sensitive data should not be redacted")
        XCTAssertEqual(redacted["password"] as? String, "[REDACTED]", "Password should be redacted")
        XCTAssertEqual(redacted["api_key"] as? String, "[REDACTED]", "API key should be redacted")
        XCTAssertEqual(redacted["message"] as? String, "[REDACTED]", "Message content should be redacted")
    }

    func testMCPAuditLogger() throws {
        let logger = MCPAuditLogger.shared
        logger.clearLogs()

        logger.log(
            serverId: "test-server",
            method: "tools/call:test_tool",
            redactedParams: "{param1, param2}",
            success: true,
            errorCode: nil,
            durationMs: 150
        )

        let logs = logger.getLogs(limit: 10)
        XCTAssertEqual(logs.count, 1, "Should have one log entry")
        XCTAssertEqual(logs[0].method, "tools/call:test_tool")
        XCTAssertTrue(logs[0].success)
        XCTAssertEqual(logs[0].durationMs, 150)
    }

    func testStdioTransportInitialization() throws {
        let config = MCPServerConfig(
            id: "stdio-server",
            name: "Stdio Server",
            endpoint: "node server.js",
            transport: .stdio,
            credentialType: .none,
            category: .development,
            enabled: true
        )

        let client = try MCPClient(config: config)
        XCTAssertNotNil(client)
    }

    func testHTTPTransportInitialization() throws {
        let config = MCPServerConfig(
            id: "http-server",
            name: "HTTP Server",
            endpoint: "https://api.example.com",
            transport: .http,
            credentialType: .oauth,
            category: .productivity,
            enabled: true
        )

        let client = try MCPClient(config: config)
        XCTAssertNotNil(client)
    }
}
