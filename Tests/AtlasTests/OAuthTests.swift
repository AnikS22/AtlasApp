//
//  OAuthTests.swift
//  AtlasTests
//
//  Unit tests for OAuth and integration services
//

import XCTest
@testable import Atlas

@MainActor
final class OAuthTests: XCTestCase {

    var oauthManager: OAuthManager?

    override func setUpWithError() throws {
        oauthManager = OAuthManager()
    }

    override func tearDownWithError() throws {
        oauthManager = nil
    }

    func testOAuthManagerInitialization() throws {
        XCTAssertNotNil(oauthManager, "OAuth manager should initialize")
        XCTAssertFalse(oauthManager!.isAuthenticating, "Should not be authenticating initially")
        XCTAssertTrue(oauthManager!.connectedServices.isEmpty, "Should have no connected services initially")
    }

    func testServiceTypeEnumeration() throws {
        let services = OAuthManager.ServiceType.allCases
        XCTAssertEqual(services.count, 3, "Should have 3 service types")
        XCTAssertTrue(services.contains(.gmail), "Should include Gmail")
        XCTAssertTrue(services.contains(.googleDrive), "Should include Google Drive")
        XCTAssertTrue(services.contains(.notion), "Should include Notion")
    }

    func testServiceIcons() throws {
        XCTAssertEqual(OAuthManager.ServiceType.gmail.icon, "envelope.fill")
        XCTAssertEqual(OAuthManager.ServiceType.googleDrive.icon, "folder.fill")
        XCTAssertEqual(OAuthManager.ServiceType.notion.icon, "doc.text.fill")
    }

    func testServiceIds() throws {
        XCTAssertEqual(OAuthManager.ServiceType.gmail.serverId, "gmail")
        XCTAssertEqual(OAuthManager.ServiceType.googleDrive.serverId, "google_drive")
        XCTAssertEqual(OAuthManager.ServiceType.notion.serverId, "notion")
    }

    func testConnectionStatus() throws {
        let isConnected = oauthManager?.isConnected(.gmail)
        XCTAssertNotNil(isConnected, "Should return connection status")
    }
}
