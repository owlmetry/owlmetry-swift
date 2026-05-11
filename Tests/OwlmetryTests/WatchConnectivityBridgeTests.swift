import XCTest
@testable import Owlmetry

#if canImport(WatchConnectivity)
import WatchConnectivity

final class WatchConnectivityBridgeTests: XCTestCase {
    func testEncodeDecodeRoundtripPreservesAllFields() throws {
        let event = LogEvent.stub(
            message: "workout_started",
            level: .info,
            screenName: "workout",
            customAttributes: ["intensity": "high"],
            userId: "rider-42"
        )
        let encoded = try JSONEncoder().encode([event])
        let envelope: [String: Any] = [WatchConnectivityBridge.envelopeKey: encoded]

        let decoded = try XCTUnwrap(WatchConnectivityBridge.decodeEnvelope(envelope))

        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].message, "workout_started")
        XCTAssertEqual(decoded[0].screenName, "workout")
        XCTAssertEqual(decoded[0].userId, "rider-42")
        XCTAssertEqual(decoded[0].customAttributes?["intensity"], "high")
        XCTAssertEqual(decoded[0].environment, .ios)
        XCTAssertEqual(decoded[0].clientEventId, event.clientEventId)
        XCTAssertEqual(decoded[0].timestamp, event.timestamp)
    }

    func testEncodeDecodeRoundtripMultipleEvents() throws {
        let events = (0..<5).map { LogEvent.stub(message: "event-\($0)") }
        let encoded = try JSONEncoder().encode(events)
        let envelope: [String: Any] = [WatchConnectivityBridge.envelopeKey: encoded]

        let decoded = try XCTUnwrap(WatchConnectivityBridge.decodeEnvelope(envelope))

        XCTAssertEqual(decoded.count, 5)
        XCTAssertEqual(decoded.map { $0.message }, ["event-0", "event-1", "event-2", "event-3", "event-4"])
        XCTAssertEqual(decoded.map { $0.clientEventId }, events.map { $0.clientEventId })
    }

    func testEncodeDecodeEmptyArrayRoundtrips() throws {
        let encoded = try JSONEncoder().encode([LogEvent]())
        let envelope: [String: Any] = [WatchConnectivityBridge.envelopeKey: encoded]

        let decoded = try XCTUnwrap(WatchConnectivityBridge.decodeEnvelope(envelope))
        XCTAssertTrue(decoded.isEmpty)
    }

    func testDecodeReturnsNilWhenEnvelopeKeyAbsent() {
        let userInfo: [String: Any] = ["host_feature_payload": "value"]
        XCTAssertNil(WatchConnectivityBridge.decodeEnvelope(userInfo))
    }

    func testDecodeReturnsNilWhenEnvelopeValueIsWrongType() {
        let userInfo: [String: Any] = [WatchConnectivityBridge.envelopeKey: "not data"]
        XCTAssertNil(WatchConnectivityBridge.decodeEnvelope(userInfo))
    }

    func testDecodeReturnsNilWhenJSONIsMalformed() {
        let garbage = Data([0x00, 0x01, 0x02, 0xFF])
        let userInfo: [String: Any] = [WatchConnectivityBridge.envelopeKey: garbage]
        XCTAssertNil(WatchConnectivityBridge.decodeEnvelope(userInfo))
    }

    func testEnvelopeKeyIsStable() {
        // Wire contract — bumping requires cross-version migration.
        XCTAssertEqual(WatchConnectivityBridge.envelopeKey, "__owl_v1")
    }
}

#endif
