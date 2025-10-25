//
//  IntegrationCoordinator.swift
//  Atlas
//
//  Coordinates between AI engine and cloud integrations
//  Orchestrates data fetching, local processing, and response generation
//

import Foundation

/// Coordinates AI processing with cloud data integrations
@available(iOS 17.0, *)
public actor IntegrationCoordinator {
    
    // MARK: - Services
    
    private let trmEngine: InferenceEngineProtocol
    private let memoryService: MemoryService
    private var gmailClient: GmailMCPClient?
    private var driveClient: GoogleDriveMCPClient?
    
    // MARK: - State
    
    private var isInitialized = false
    
    // MARK: - Initialization
    
    public init() async throws {
        print("🔄 Initializing Integration Coordinator...")
        
        // Initialize core services
        self.trmEngine = TRMEngineFactory.createEngine()
        self.memoryService = MemoryService()
        
        // Try to initialize cloud clients (may fail if not authenticated)
        do {
            self.gmailClient = try GmailMCPClient()
            print("✅ Gmail client initialized")
        } catch {
            print("⚠️ Gmail client not available: \(error.localizedDescription)")
        }
        
        do {
            self.driveClient = try GoogleDriveMCPClient()
            print("✅ Drive client initialized")
        } catch {
            print("⚠️ Drive client not available: \(error.localizedDescription)")
        }
        
        isInitialized = true
        print("✅ Integration Coordinator ready")
    }
    
    // MARK: - Smart Query Processing
    
    /// Process query with automatic integration detection
    public func processQuery(_ query: String, context: MemoryContext?) async throws -> String {
        print("📝 Processing query: \(query)")
        
        // Analyze query to determine if cloud data needed
        let analysis = analyzeQuery(query)
        
        var enhancedContext = ""
        
        // Fetch Gmail data if needed
        if analysis.needsEmail {
            if let emailData = try? await fetchEmailData(query: analysis.emailQuery) {
                enhancedContext += emailData
                print("✅ Added email context")
            }
        }
        
        // Fetch Drive data if needed
        if analysis.needsDrive {
            if let driveData = try? await fetchDriveData(query: analysis.driveQuery) {
                enhancedContext += "\n" + driveData
                print("✅ Added Drive context")
            }
        }
        
        // Generate AI response with enhanced context
        let fullPrompt = enhancedContext.isEmpty ? query : """
        Context from your data:
        \(enhancedContext)
        
        User question: \(query)
        """
        
        let response = try await trmEngine.generate(prompt: fullPrompt, context: context)
        
        print("✅ Generated response")
        return response
    }
    
    // MARK: - Email Integration
    
    /// Fetch and summarize emails
    public func fetchAndSummarizeEmails(query: String) async throws -> String {
        guard let gmail = gmailClient else {
            return "Gmail is not connected. Please connect your Gmail account in Settings to access your emails."
        }
        
        print("📧 Fetching emails with query: \(query)")
        
        do {
            // Try to connect first
            try await gmail.connect()
            
            // Search for emails
            let emails = try await gmail.searchMessages(query: query, maxResults: 10)
            
            if emails.isEmpty {
                return "No emails found matching '\(query)'"
            }
            
            // Extract email content
            var emailTexts = ""
            for (index, email) in emails.prefix(10).enumerated() {
                if let subject = email["subject"] as? String,
                   let snippet = email["snippet"] as? String {
                    emailTexts += "\nEmail \(index + 1): \(subject)\n\(snippet)\n"
                }
            }
            
            // Generate summary with TRM
            let summaryPrompt = """
            Summarize these \(emails.count) emails concisely:
            \(emailTexts)
            
            Provide a brief overview highlighting key points.
            """
            
            let summary = try await trmEngine.generate(prompt: summaryPrompt, context: nil)
            
            return summary
            
        } catch {
            throw IntegrationError.emailFetchFailed(error.localizedDescription)
        }
    }
    
    /// Get specific email details
    public func getEmailDetails(emailId: String) async throws -> String {
        guard let gmail = gmailClient else {
            throw IntegrationError.serviceNotConnected("Gmail")
        }
        
        try await gmail.connect()
        let email = try await gmail.getMessage(id: emailId)
        
        // Extract relevant fields
        let subject = email["subject"] as? String ?? "No subject"
        let body = email["body"] as? String ?? email["snippet"] as? String ?? "No content"
        let from = email["from"] as? String ?? "Unknown sender"
        
        return """
        From: \(from)
        Subject: \(subject)
        
        \(body)
        """
    }
    
    // MARK: - Drive Integration
    
    /// Search and summarize Drive files
    public func searchAndSummarizeDriveFiles(query: String) async throws -> String {
        guard let drive = driveClient else {
            return "Google Drive is not connected. Please connect your Google Drive account in Settings to access your files."
        }
        
        print("📁 Searching Drive files with query: \(query)")
        
        do {
            try await drive.connect()
            
            // Search for files
            let files = try await drive.searchFiles(query: query, maxResults: 10)
            
            if files.isEmpty {
                return "No files found matching '\(query)'"
            }
            
            // Create file list
            var fileList = "Found \(files.count) files:\n"
            for (index, file) in files.enumerated() {
                if let name = file["name"] as? String,
                   let type = file["mimeType"] as? String {
                    fileList += "\n\(index + 1). \(name) (\(type))"
                }
            }
            
            // Generate summary with TRM
            let summaryPrompt = """
            Summarize these Drive files:
            \(fileList)
            
            Provide a brief overview of what files were found.
            """
            
            let summary = try await trmEngine.generate(prompt: summaryPrompt, context: nil)
            
            return summary
            
        } catch {
            throw IntegrationError.driveFetchFailed(error.localizedDescription)
        }
    }
    
    /// Download and analyze specific file
    public func analyzeFile(fileId: String) async throws -> String {
        guard let drive = driveClient else {
            throw IntegrationError.serviceNotConnected("Google Drive")
        }
        
        try await drive.connect()
        
        // Get file metadata
        let file = try await drive.getFile(id: fileId)
        
        guard let fileName = file["name"] as? String else {
            throw IntegrationError.invalidFileData
        }
        
        // For now, return file info
        // In production, this would download and analyze content
        return "File: \(fileName)\nAnalysis of file contents would go here."
    }
    
    // MARK: - Private Helpers
    
    private struct QueryAnalysis {
        let needsEmail: Bool
        let needsDrive: Bool
        let emailQuery: String
        let driveQuery: String
    }
    
    private func analyzeQuery(_ query: String) -> QueryAnalysis {
        let lowercased = query.lowercased()
        
        // Detect email-related queries
        let needsEmail = lowercased.contains("email") ||
                        lowercased.contains("mail") ||
                        lowercased.contains("inbox") ||
                        lowercased.contains("message")
        
        // Detect drive-related queries
        let needsDrive = lowercased.contains("file") ||
                        lowercased.contains("drive") ||
                        lowercased.contains("document") ||
                        lowercased.contains("folder")
        
        // Extract search queries
        var emailQuery = ""
        var driveQuery = ""
        
        if needsEmail {
            // Extract time-based queries
            if lowercased.contains("today") {
                emailQuery = "newer_than:1d"
            } else if lowercased.contains("week") {
                emailQuery = "newer_than:7d"
            } else {
                emailQuery = ""
            }
        }
        
        if needsDrive {
            // Extract file type queries
            if lowercased.contains("document") {
                driveQuery = "mimeType='application/vnd.google-apps.document'"
            } else if lowercased.contains("spreadsheet") {
                driveQuery = "mimeType='application/vnd.google-apps.spreadsheet'"
            } else {
                driveQuery = ""
            }
        }
        
        return QueryAnalysis(
            needsEmail: needsEmail,
            needsDrive: needsDrive,
            emailQuery: emailQuery,
            driveQuery: driveQuery
        )
    }
    
    private func fetchEmailData(query: String) async throws -> String {
        guard let gmail = gmailClient else { return "" }
        
        try await gmail.connect()
        let emails = try await gmail.listMessages(query: query.isEmpty ? nil : query, maxResults: 5)
        
        var context = "Recent emails:\n"
        for (index, email) in emails.prefix(5).enumerated() {
            if let snippet = email["snippet"] as? String {
                context += "\(index + 1). \(snippet)\n"
            }
        }
        
        return context
    }
    
    private func fetchDriveData(query: String) async throws -> String {
        guard let drive = driveClient else { return "" }
        
        try await drive.connect()
        let files = try await drive.searchFiles(query: query.isEmpty ? "" : query, maxResults: 5)
        
        var context = "Recent Drive files:\n"
        for (index, file) in files.prefix(5).enumerated() {
            if let name = file["name"] as? String {
                context += "\(index + 1). \(name)\n"
            }
        }
        
        return context
    }
    
    // MARK: - Connection Management
    
    public func connectGmail() async throws {
        guard gmailClient != nil else {
            throw IntegrationError.serviceNotAvailable("Gmail")
        }
        
        try await gmailClient?.connect()
        print("✅ Gmail connected")
    }
    
    public func connectDrive() async throws {
        guard driveClient != nil else {
            throw IntegrationError.serviceNotAvailable("Google Drive")
        }
        
        try await driveClient?.connect()
        print("✅ Drive connected")
    }
    
    public func disconnectAll() async {
        await gmailClient?.disconnect()
        await driveClient?.disconnect()
        print("✅ All integrations disconnected")
    }
}

// MARK: - Error Types

public enum IntegrationError: LocalizedError {
    case serviceNotConnected(String)
    case serviceNotAvailable(String)
    case emailFetchFailed(String)
    case driveFetchFailed(String)
    case invalidFileData
    case authenticationRequired
    
    public var errorDescription: String? {
        switch self {
        case .serviceNotConnected(let service):
            return "\(service) is not connected"
        case .serviceNotAvailable(let service):
            return "\(service) is not available"
        case .emailFetchFailed(let error):
            return "Failed to fetch emails: \(error)"
        case .driveFetchFailed(let error):
            return "Failed to fetch Drive files: \(error)"
        case .invalidFileData:
            return "Invalid file data received"
        case .authenticationRequired:
            return "Authentication required"
        }
    }
}

