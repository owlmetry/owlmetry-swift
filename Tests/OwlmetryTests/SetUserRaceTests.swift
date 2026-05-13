// Process is macOS-only; gate so the test target builds on iOS/watchOS sims
// (matches SDKIntegrationTests.swift).
#if os(macOS)
import XCTest
@testable import Owlmetry

/// Reproduction of the orphan-anon-user bug described in CLAUDE.md "Identity":
/// `Owl.log()` spawns a Task that hops `DuplicateFilter` actor → `EventTransport`
/// actor (two awaits). `Owl.setUser()` spawns a Task that goes straight to
/// `EventTransport.claimIdentity` (one await → flushAll → POST /v1/identity/claim).
///
/// The setUser Task can win the race to `EventTransport` while the log Tasks
/// are still queued at `DuplicateFilter`. `flushAll()` then sees an empty
/// buffer, exits immediately, the claim POSTs before any anon event has been
/// ingested, the server returns "no events found", and the SDK gives up.
/// Late-arriving anon events end up orphaned on a separate `app_users` row.
///
/// These tests use a global `URLProtocol` registration to intercept
/// `URLSession.shared` (the default the SDK uses) so we can assert request
/// ordering deterministically without a real server.
final class SetUserRaceTests: XCTestCase {
    /// Hostname our mock intercepts. Filtering by host keeps the global
    /// `URLProtocol` registration from leaking into other unit tests that
    /// happen to run in parallel and use `URLSession.shared`.
    static let mockHost = "race-test.owlmetry.invalid"

    override class func setUp() {
        super.setUp()
        URLProtocol.registerClass(SetUserRaceMockProtocol.self)
    }

    override class func tearDown() {
        URLProtocol.unregisterClass(SetUserRaceMockProtocol.self)
        super.tearDown()
    }

    override func setUp() async throws {
        try await super.setUp()
        await Owl.reset()
        Owl.clearUser(newAnonymousId: true)
        IdentityManager.clearUserId()
        let tempQueue = OfflineQueue()
        await tempQueue.clear()
        SetUserRaceMockProtocol.reset()
    }

    override func tearDown() async throws {
        await Owl.shutdown()
        try await super.tearDown()
    }

    /// The load-bearing assertion: after a burst of `Owl.log()` calls
    /// followed immediately by `Owl.setUser(...)`, the claim POST must arrive
    /// at the server *after* every ingest POST that carries one of those log
    /// events. If it doesn't, the server-side claim runs against an empty
    /// events table and the anon→real merge is lost.
    func testClaimPostIsIssuedAfterAllPriorIngestPosts() async throws {
        try Owl.configure(
            endpoint: "https://\(Self.mockHost)",
            apiKey: "owl_client_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            bundleId: "com.owlmetry.test",
            flushOnBackground: false,
            // Disable gzip — bodies > 512 bytes would arrive compressed,
            // breaking the JSONSerialization parse below.
            compressionEnabled: false,
            networkTrackingEnabled: false,
            consoleLogging: false,
            // Disable the auto-attribution capture Task — it would race the
            // mock's request capture and add a separate POST that confuses the
            // ordering assertion.
            attributionEnabled: false
        )

        // 30 events under the device's anon id. EventTransport batches at 20,
        // so we expect at least two ingest batches before flushAll drains.
        for i in 0..<30 {
            Owl.info("burst_\(i)", screenName: "race")
        }

        // No sleep — the bug is exactly that this fires before the log Tasks
        // have reached the EventTransport buffer.
        let realId = "race-real-user-\(UUID().uuidString.prefix(8))"
        Owl.setUser(realId)

        // Drive the in-flight Tasks to completion. shutdown() drains the
        // transport buffer, but we also need to wait for the claim Task that
        // setUser spawned independently. Poll until we see a claim POST.
        let claimSeen = await pollUntil(timeout: 8) {
            SetUserRaceMockProtocol.snapshot().contains { $0.path.hasSuffix("/v1/identity/claim") }
        }
        XCTAssertTrue(claimSeen, "claim POST never arrived within 8s — SDK never POSTed claim or mock not wired")

        // Drain anything still in flight.
        await Owl.shutdown()

        // Give residual Tasks a moment to finalize so the snapshot is stable.
        try? await Task.sleep(nanoseconds: 200_000_000)

        let captured = SetUserRaceMockProtocol.snapshot()
        let ingestArrivals = captured.filter { $0.path.hasSuffix("/v1/ingest") }
        let claimArrivals = captured.filter { $0.path.hasSuffix("/v1/identity/claim") }

        XCTAssertFalse(ingestArrivals.isEmpty, "no ingest POSTs were captured — every event was lost or the mock isn't wired")
        XCTAssertFalse(claimArrivals.isEmpty, "no claim POSTs captured")

        let firstClaimAt = claimArrivals.map { $0.date }.min()!

        // Every "burst_*" event must have been delivered to /v1/ingest. The
        // SDK also emits sdk:session_started on configure — that's expected
        // and unrelated, so filter to our message prefix.
        var burstEventsIngested = 0
        var lastBurstIngestAt: Date = .distantPast
        for arrival in ingestArrivals {
            guard let body = arrival.body,
                  let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let events = json["events"] as? [[String: Any]] else { continue }
            let burstsInBatch = events.filter { (($0["message"] as? String) ?? "").hasPrefix("burst_") }.count
            if burstsInBatch > 0 {
                burstEventsIngested += burstsInBatch
                if arrival.date > lastBurstIngestAt { lastBurstIngestAt = arrival.date }
            }
        }
        XCTAssertEqual(burstEventsIngested, 30,
                       "expected all 30 burst events at /v1/ingest, got \(burstEventsIngested)")

        // The load-bearing ordering assertion: the claim's first POST must
        // arrive at or after the last burst ingest. Without the fix, the
        // claim Task can win the race to EventTransport while the log Tasks
        // are still queued at DuplicateFilter — flushAll sees an empty
        // buffer and claim POSTs before any burst event has been ingested.
        XCTAssertGreaterThanOrEqual(
            firstClaimAt, lastBurstIngestAt,
            "claim POST arrived BEFORE the last burst ingest — the SDK race is not fixed. " +
            "first claim: \(firstClaimAt.timeIntervalSince1970), " +
            "last burst ingest: \(lastBurstIngestAt.timeIntervalSince1970)"
        )

        // Claim payload must use the original anon id (the one that was
        // current at log time) and the new real id.
        let claimBody = claimArrivals.first.flatMap { $0.body }
        let claimJson = claimBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        XCTAssertEqual(claimJson?["user_id"] as? String, realId)
        let anonInClaim = claimJson?["anonymous_id"] as? String
        XCTAssertNotNil(anonInClaim)
        XCTAssertTrue(anonInClaim?.hasPrefix(IdentityManager.anonymousIdPrefix) == true,
                      "claim's anonymous_id should be the device anon id; got \(anonInClaim ?? "nil")")
    }

    // MARK: - Helpers

    private func pollUntil(timeout: TimeInterval, _ predicate: @Sendable () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return predicate()
    }
}

// MARK: - Global mock URLProtocol

/// Intercepts every request to `SetUserRaceTests.mockHost` regardless of the
/// `URLSession` instance. `URLSession.shared` (the SDK's default) consults
/// the global protocol registry, so registering this class once in `setUp`
/// covers everything the SDK posts.
final class SetUserRaceMockProtocol: URLProtocol {
    struct Arrival {
        let date: Date
        let path: String
        let body: Data?
    }

    private static let lock = NSLock()
    private static var captured: [Arrival] = []

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        captured.removeAll()
    }

    static func snapshot() -> [Arrival] {
        lock.lock(); defer { lock.unlock() }
        return captured
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == SetUserRaceTests.mockHost
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = Self.readBody(from: request)
        let arrival = Arrival(date: Date(), path: request.url?.path ?? "", body: body)
        Self.lock.lock()
        Self.captured.append(arrival)
        Self.lock.unlock()

        // Cover all the SDK endpoints the test could hit. Response bodies
        // shape-match what the real server returns for each.
        let path = request.url?.path ?? ""
        let responseBody: Data
        if path.hasSuffix("/v1/identity/claim") {
            responseBody = #"{"claimed":true,"events_reassigned_count":0}"#.data(using: .utf8)!
        } else if path.hasSuffix("/v1/ingest") {
            responseBody = #"{"accepted":1,"rejected":0}"#.data(using: .utf8)!
        } else {
            responseBody = #"{}"#.data(using: .utf8)!
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readBody(from request: URLRequest) -> Data? {
        if let direct = request.httpBody { return direct }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let n = stream.read(buffer, maxLength: 4096)
            if n > 0 { data.append(buffer, count: n) } else { break }
        }
        return data
    }
}
#endif
