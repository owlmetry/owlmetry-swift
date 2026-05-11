import Foundation
import os

#if canImport(WatchConnectivity)
import WatchConnectivity

/// Relays Owlmetry events from a watchOS app to its paired iPhone via
/// `WCSession.transferUserInfo` — itself an OS-managed persistent queue
/// that survives watch suspension and bluetooth disconnection, delivered
/// when the iPhone counterpart is reachable again. Used as the offline
/// fallback in `EventTransport`.
final class WatchConnectivityBridge: @unchecked Sendable {
    static let shared = WatchConnectivityBridge()

    // Wire-contract key; bumping requires cross-version migration.
    static let envelopeKey = "__owl_v1"

    // 60 KB stays defensively under WC's practical payload ceiling.
    private static let maxChunkBytes = 60_000

    private static let logger = Logger(subsystem: Owl.logSubsystem, category: "wc-bridge")

    #if os(watchOS)
    private let delegate = WatchSessionDelegate()
    #endif

    private init() {}

    /// Activate `WCSession.default`. Idempotent. Watch-side claims the
    /// delegate slot; iOS-side host apps forward inbound payloads via
    /// `Owl.handleWatchUserInfo(_:)` from their own `WCSessionDelegate`.
    func activate() {
        guard WCSession.isSupported() else { return }
        #if os(watchOS)
        WCSession.default.delegate = delegate
        WCSession.default.activate()
        #endif
    }

    #if os(watchOS)
    /// True when the watch can hand events off to the paired iPhone right
    /// now. False during the brief activation gap on first launch, and for
    /// watch-only apps with no companion ever installed.
    var canRelay: Bool {
        let session = WCSession.default
        return session.activationState == .activated && session.isCompanionAppInstalled
    }

    /// Hand a batch to WC's persistent `transferUserInfo` queue. The
    /// payload survives watch suspension, watch reboot, and bluetooth
    /// disconnection; the OS wakes the paired iPhone app to receive when
    /// the devices reconnect. Chunks at ~60 KB encoded (WC has no
    /// documented hard cap, but historic failures cluster well above
    /// that — chunking is defensive); chunks deliver FIFO so server-side
    /// timestamps stay monotonic.
    func enqueue(_ events: [LogEvent]) {
        guard canRelay, !events.isEmpty else { return }
        let encoder = JSONEncoder()
        var remaining = ArraySlice(events)
        while let chunk = Self.nextChunk(from: &remaining, encoder: encoder) {
            WCSession.default.transferUserInfo([Self.envelopeKey: chunk])
        }
    }

    private static func nextChunk(
        from events: inout ArraySlice<LogEvent>,
        encoder: JSONEncoder
    ) -> Data? {
        guard !events.isEmpty else { return nil }
        var size = events.count
        while size > 0 {
            let candidate = Array(events.prefix(size))
            guard let data = try? encoder.encode(candidate) else {
                size -= 1
                continue
            }
            if data.count <= maxChunkBytes || size == 1 {
                events = events.dropFirst(size)
                return data
            }
            size -= 1
        }
        logger.error("Failed to encode single-event WC chunk; dropping")
        events = events.dropFirst()
        return nil
    }
    #endif

    /// Decode an inbound `didReceiveUserInfo` payload. Returns nil when the
    /// envelope is absent — caller should fall through to its own handling.
    static func decodeEnvelope(_ userInfo: [String: Any]) -> [LogEvent]? {
        guard let data = userInfo[envelopeKey] as? Data else { return nil }
        return try? JSONDecoder().decode([LogEvent].self, from: data)
    }
}

#if os(watchOS)
private final class WatchSessionDelegate: NSObject, WCSessionDelegate {
    // No-op: canRelay reads activationState live, so we don't mirror it.
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}
}
#endif

#endif
