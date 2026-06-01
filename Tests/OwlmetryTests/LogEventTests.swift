import XCTest
@testable import Owlmetry

final class LogEventTests: XCTestCase {
    func testCodableRoundTrip() throws {
        let event = LogEvent(
            clientEventId: "abc-123",
            sessionId: "session-123",
            userId: "user1",
            level: .error,
            sourceModule: "File.swift:test:1",
            message: "something broke",
            screenName: "checkout",
            customAttributes: ["key": "val"],
            environment: .ios,
            osVersion: "17.0",
            appVersion: "2.0",
            sdkName: "owlmetry-swift",
            sdkVersion: "0.1.0",
            buildNumber: "100",
            deviceModel: "iPhone16,1",
            locale: "en_US",
            preferredLanguage: "fr-FR",
            supportedLanguages: ["en", "de"],
            isDev: true,
            timestamp: "2026-01-01T00:00:00.000Z"
        )

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(LogEvent.self, from: data)

        XCTAssertEqual(decoded.clientEventId, event.clientEventId)
        XCTAssertEqual(decoded.userId, event.userId)
        XCTAssertEqual(decoded.level, event.level)
        XCTAssertEqual(decoded.message, event.message)
        XCTAssertEqual(decoded.screenName, event.screenName)
        XCTAssertEqual(decoded.environment, event.environment)
        XCTAssertEqual(decoded.preferredLanguage, event.preferredLanguage)
        XCTAssertEqual(decoded.supportedLanguages, event.supportedLanguages)
    }

    func testJSONKeysAreSnakeCase() throws {
        let event = LogEvent(
            clientEventId: "id",
            sessionId: "session-id",
            userId: nil,
            level: .info,
            sourceModule: nil,
            message: "test",
            screenName: nil,
            customAttributes: nil,
            environment: .macos,
            osVersion: nil,
            appVersion: nil,
            sdkName: nil,
            sdkVersion: nil,
            buildNumber: nil,
            deviceModel: nil,
            locale: nil,
            preferredLanguage: "fr-CA",
            supportedLanguages: ["en", "de"],
            isDev: false,
            timestamp: "2026-01-01T00:00:00.000Z"
        )

        let data = try JSONEncoder().encode(event)
        let json = String(data: data, encoding: .utf8)!

        XCTAssertTrue(json.contains("client_event_id"))
        XCTAssertTrue(json.contains("session_id"))
        XCTAssertFalse(json.contains("clientEventId"))
        XCTAssertTrue(json.contains("preferred_language"))
        XCTAssertTrue(json.contains("supported_languages"))
        XCTAssertFalse(json.contains("preferredLanguage"))
    }

    func testNilFieldsOmittedInJSON() throws {
        let event = LogEvent(
            clientEventId: "id",
            sessionId: "session-id",
            userId: nil,
            level: .info,
            sourceModule: nil,
            message: "test",
            screenName: nil,
            customAttributes: nil,
            environment: .ios,
            osVersion: nil,
            appVersion: nil,
            sdkName: nil,
            sdkVersion: nil,
            buildNumber: nil,
            deviceModel: nil,
            locale: nil,
            preferredLanguage: nil,
            supportedLanguages: nil,
            isDev: false,
            timestamp: "2026-01-01T00:00:00.000Z"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(event)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertNil(json["user_id"])
        XCTAssertNil(json["source_module"])
        XCTAssertNil(json["screen_name"])
        XCTAssertNil(json["custom_attributes"])
        XCTAssertNil(json["os_version"])
        XCTAssertNil(json["sdk_name"])
        XCTAssertNil(json["sdk_version"])
        XCTAssertNil(json["preferred_language"])
        XCTAssertNil(json["supported_languages"])
    }

    func testSDKNameAndVersionEncodedAsSnakeCase() throws {
        let event = LogEvent(
            clientEventId: "id",
            sessionId: "session-id",
            userId: nil,
            level: .info,
            sourceModule: nil,
            message: "test",
            screenName: nil,
            customAttributes: nil,
            environment: .ios,
            osVersion: nil,
            appVersion: nil,
            sdkName: "owlmetry-swift",
            sdkVersion: "1.2.3",
            buildNumber: nil,
            deviceModel: nil,
            locale: nil,
            preferredLanguage: nil,
            supportedLanguages: nil,
            isDev: false,
            timestamp: "2026-01-01T00:00:00.000Z"
        )
        let data = try JSONEncoder().encode(event)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["sdk_name"] as? String, "owlmetry-swift")
        XCTAssertEqual(json["sdk_version"] as? String, "1.2.3")
    }
}
