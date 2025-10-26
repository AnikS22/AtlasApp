import Foundation
#if canImport(Darwin)
import Darwin
#endif

// MARK: - Transport Protocol

/// Protocol for MCP transport implementations
protocol MCPTransport: AnyObject {
    /// Connect to the MCP server
    func connect() async throws

    /// Disconnect from the MCP server
    func disconnect() async

    /// Send a request and wait for response
    func send(_ request: MCPRequest) async throws -> MCPResponse

    /// Send a notification (no response expected)
    func notify(_ notification: MCPNotification) async throws

    /// Stream for receiving unsolicited notifications
    var notificationStream: AsyncStream<MCPNotification> { get }

    /// Check if transport is currently connected
    var isConnected: Bool { get }
}

// MARK: - WebSocket Transport

final class WebSocketMCPTransport: NSObject, MCPTransport, URLSessionWebSocketDelegate {
    private let url: URL
    private var webSocket: URLSessionWebSocketTask?
    private let session: URLSession
    private var pendingRequests: [String: CheckedContinuation<MCPResponse, Error>] = [:]
    private let requestQueue = DispatchQueue(label: "io.atlas.mcp.websocket")

    private var notificationContinuation: AsyncStream<MCPNotification>.Continuation?
    let notificationStream: AsyncStream<MCPNotification>

    private(set) var isConnected: Bool = false

    init(url: URL) {
        self.url = url
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: configuration)

        var continuation: AsyncStream<MCPNotification>.Continuation!
        self.notificationStream = AsyncStream { continuation = $0 }
        self.notificationContinuation = continuation

        super.init()
    }

    func connect() async throws {
        guard !isConnected else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.addValue("mcp-client/1.0", forHTTPHeaderField: "User-Agent")

        webSocket = session.webSocketTask(with: request)
        webSocket?.resume()

        // Start receiving messages
        receiveMessage()

        isConnected = true
    }

    func disconnect() async {
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        isConnected = false

        // Fail all pending requests
        requestQueue.sync {
            for (_, continuation) in pendingRequests {
                continuation.resume(throwing: MCPClientError.notConnected)
            }
            pendingRequests.removeAll()
        }
    }

    func send(_ request: MCPRequest) async throws -> MCPResponse {
        guard let webSocket = webSocket, isConnected else {
            throw MCPClientError.notConnected
        }

        // Encode request
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(request)
        let message = URLSessionWebSocketTask.Message.data(data)

        // Send message
        try await webSocket.send(message)

        // Wait for response with timeout
        return try await withTimeout(seconds: 30) {
            try await withCheckedThrowingContinuation { continuation in
                self.requestQueue.sync {
                    self.pendingRequests[request.id] = continuation
                }
            }
        }
    }

    func notify(_ notification: MCPNotification) async throws {
        guard let webSocket = webSocket, isConnected else {
            throw MCPClientError.notConnected
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(notification)
        let message = URLSessionWebSocketTask.Message.data(data)

        try await webSocket.send(message)
    }

    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                self.handleMessage(message)
                // Continue receiving
                self.receiveMessage()

            case .failure(let error):
                print("WebSocket receive error: \(error)")
                self.isConnected = false
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        guard case .data(let data) = message else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            // Try to decode as response
            if let response = try? decoder.decode(MCPResponse.self, from: data) {
                requestQueue.sync {
                    if let continuation = pendingRequests.removeValue(forKey: response.id) {
                        continuation.resume(returning: response)
                    }
                }
                return
            }

            // Try to decode as notification
            if let notification = try? decoder.decode(MCPNotification.self, from: data) {
                notificationContinuation?.yield(notification)
                return
            }

            print("Failed to decode MCP message")
        }
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        isConnected = true
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        isConnected = false
        Task {
            await disconnect()
        }
    }

    deinit {
        Task { [weak self] in
            await self?.disconnect()
        }
    }
}

// MARK: - Stdio Transport

/// Transport for stdio-based MCP servers (Node.js processes)
final class StdioMCPTransport: MCPTransport {
    private let executable: String
    private let arguments: [String]
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var pendingRequests: [String: CheckedContinuation<MCPResponse, Error>] = [:]
    private let requestQueue = DispatchQueue(label: "io.atlas.mcp.stdio")

    private var notificationContinuation: AsyncStream<MCPNotification>.Continuation?
    let notificationStream: AsyncStream<MCPNotification>

    private(set) var isConnected: Bool = false

    init(executable: String, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments

        var continuation: AsyncStream<MCPNotification>.Continuation!
        self.notificationStream = AsyncStream { continuation = $0 }
        self.notificationContinuation = continuation
    }

    func connect() async throws {
        guard !isConnected else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let inputPipe = Pipe()
        let outputPipe = Pipe()

        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        self.process = process
        self.inputPipe = inputPipe
        self.outputPipe = outputPipe

        // Start reading output
        startReadingOutput()

        try process.run()
        isConnected = true
    }

    func disconnect() async {
        process?.terminate()
        process = nil
        inputPipe = nil
        outputPipe = nil
        isConnected = false

        requestQueue.sync {
            for (_, continuation) in pendingRequests {
                continuation.resume(throwing: MCPClientError.notConnected)
            }
            pendingRequests.removeAll()
        }
    }

    func send(_ request: MCPRequest) async throws -> MCPResponse {
        guard let inputPipe = inputPipe, isConnected else {
            throw MCPClientError.notConnected
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(request)

        // Add newline delimiter
        data.append(Data([0x0A]))

        // Write to stdin
        try inputPipe.fileHandleForWriting.write(contentsOf: data)

        return try await withTimeout(seconds: 30) {
            try await withCheckedThrowingContinuation { continuation in
                self.requestQueue.sync {
                    self.pendingRequests[request.id] = continuation
                }
            }
        }
    }

    func notify(_ notification: MCPNotification) async throws {
        guard let inputPipe = inputPipe, isConnected else {
            throw MCPClientError.notConnected
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(notification)
        data.append(Data([0x0A]))

        try inputPipe.fileHandleForWriting.write(contentsOf: data)
    }

    private func startReadingOutput() {
        guard let outputPipe = outputPipe else { return }

        Task {
            for try await line in outputPipe.fileHandleForReading.bytes.lines {
                guard let data = line.data(using: .utf8) else { continue }
                handleMessage(data)
            }
        }
    }

    private func handleMessage(_ data: Data) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Try response
        if let response = try? decoder.decode(MCPResponse.self, from: data) {
            requestQueue.sync {
                if let continuation = pendingRequests.removeValue(forKey: response.id) {
                    continuation.resume(returning: response)
                }
            }
            return
        }

        // Try notification
        if let notification = try? decoder.decode(MCPNotification.self, from: data) {
            notificationContinuation?.yield(notification)
        }
    }

    deinit {
        Task { [weak self] in
            await self?.disconnect()
        }
    }
}

// MARK: - HTTP Transport

/// Transport for HTTP-based MCP servers
final class HTTPMCPTransport: MCPTransport {
    private let baseURL: URL
    private let session: URLSession
    private var isActive: Bool = false

    private var notificationContinuation: AsyncStream<MCPNotification>.Continuation?
    let notificationStream: AsyncStream<MCPNotification>

    var isConnected: Bool { isActive }

    init(baseURL: URL) {
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: configuration)

        var continuation: AsyncStream<MCPNotification>.Continuation!
        self.notificationStream = AsyncStream { continuation = $0 }
        self.notificationContinuation = continuation
    }

    func connect() async throws {
        // HTTP is stateless, just verify server is reachable
        var request = URLRequest(url: baseURL.appendingPathComponent("/health"))
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw MCPClientError.connectionFailed(
                NSError(domain: "HTTPTransport", code: -1, userInfo: [NSLocalizedDescriptionKey: "Server unreachable"])
            )
        }

        isActive = true
    }

    func disconnect() async {
        isActive = false
    }

    func send(_ request: MCPRequest) async throws -> MCPResponse {
        guard isActive else {
            throw MCPClientError.notConnected
        }

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("/rpc"))
        urlRequest.httpMethod = "POST"
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.addValue("mcp-client/1.0", forHTTPHeaderField: "User-Agent")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        urlRequest.httpBody = try encoder.encode(request)

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPClientError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw MCPClientError.transportError("HTTP \(httpResponse.statusCode)")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MCPResponse.self, from: data)
    }

    func notify(_ notification: MCPNotification) async throws {
        guard isActive else {
            throw MCPClientError.notConnected
        }

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("/notify"))
        urlRequest.httpMethod = "POST"
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        urlRequest.httpBody = try encoder.encode(notification)

        _ = try await session.data(for: urlRequest)
    }
}

// MARK: - Helper Extensions

extension AsyncSequence where Element == UInt8 {
    /// Read lines from byte stream
    var lines: AsyncLineSequence<Self> {
        AsyncLineSequence(base: self)
    }
}

struct AsyncLineSequence<Base: AsyncSequence>: AsyncSequence where Base.Element == UInt8 {
    typealias Element = String

    let base: Base

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(base: base.makeAsyncIterator())
    }

    struct AsyncIterator: AsyncIteratorProtocol {
        var base: Base.AsyncIterator
        var buffer: [UInt8] = []

        mutating func next() async throws -> String? {
            while let byte = try await base.next() {
                if byte == 0x0A { // Newline
                    defer { buffer.removeAll() }
                    return String(bytes: buffer, encoding: .utf8)
                }
                buffer.append(byte)
            }

            // End of stream
            if !buffer.isEmpty {
                defer { buffer.removeAll() }
                return String(bytes: buffer, encoding: .utf8)
            }

            return nil
        }
    }
}

/// Helper function to add timeout to async operations
func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw MCPClientError.requestTimeout
        }

        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
