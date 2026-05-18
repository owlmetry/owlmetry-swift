import Darwin
import Foundation
import os

public enum Owl {
    static let logSubsystem = "com.owlmetry.sdk"
    private static let logger = Logger(subsystem: logSubsystem, category: "owl")

    private struct State {
        var configuration: OwlConfiguration?
        var deviceInfo: DeviceInfo?
        var transport: EventTransport?
        var attachmentUploader: AttachmentUploader?
        var duplicateFilter: DuplicateFilter?
        var networkMonitor: NetworkMonitor?
        var offlineQueue: OfflineQueue?
        var lifecycleObserver: LifecycleObserver?
        var defaultUserId: String?
        var anonymousId: String?
        var sessionId: String?
        var hasWarnedNotConfigured = false
        // Cold-launch race: iOS may deliver a watch payload before
        // configure() finishes. Buffered here, drained at end of configure.
        var pendingWatchEvents: [LogEvent] = []
        // Count of `Owl.log(...)` Tasks that have spawned but not yet
        // reached `EventTransport.enqueue`. `setUser`, `setUserProperties`,
        // and the configure-time startup reclaim await this draining to
        // zero before POSTing, so the claim/properties write arrives at
        // the server only after every preceding log event has been
        // enqueued for ingest. Without this gate the claim Task could win
        // the actor race against in-flight log Tasks (which hop
        // DuplicateFilter actor → EventTransport actor) and POST against
        // an empty events table — see CLAUDE.md "Identity" for the
        // Signature Creator orphan-user bug.
        var inFlightLogTasks: Int = 0
        var pendingLogDrains: [CheckedContinuation<Void, Never>] = []
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())

    // MARK: - Setup

    public static func configure(
        endpoint: String,
        apiKey: String,
        flushOnBackground: Bool = true,
        compressionEnabled: Bool = true,
        networkTrackingEnabled: Bool = true,
        consoleLogging: Bool = true,
        attributionEnabled: Bool = true
    ) throws {
        let config = try OwlConfiguration(endpoint: endpoint, apiKey: apiKey, flushOnBackground: flushOnBackground, compressionEnabled: compressionEnabled, networkTrackingEnabled: networkTrackingEnabled, consoleLogging: consoleLogging, attributionEnabled: attributionEnabled)
        try configureWith(config)
    }

    /// Internal entry point for testing with an explicit bundle ID.
    static func configure(
        endpoint: String,
        apiKey: String,
        bundleId: String,
        flushOnBackground: Bool = true,
        compressionEnabled: Bool = true,
        networkTrackingEnabled: Bool = true,
        consoleLogging: Bool = true,
        attributionEnabled: Bool = true
    ) throws {
        let config = try OwlConfiguration(endpoint: endpoint, apiKey: apiKey, bundleId: bundleId, flushOnBackground: flushOnBackground, compressionEnabled: compressionEnabled, networkTrackingEnabled: networkTrackingEnabled, consoleLogging: consoleLogging, attributionEnabled: attributionEnabled)
        try configureWith(config)
    }

    private static func configureWith(_ config: OwlConfiguration) throws {

        let monitor = NetworkMonitor()
        let queue = OfflineQueue()
        let transport = EventTransport(
            endpoint: config.endpoint,
            apiKey: config.apiKey,
            bundleId: config.bundleId,
            compressionEnabled: config.compressionEnabled,
            offlineQueue: queue,
            networkMonitor: monitor
        )
        let attachmentUploader = AttachmentUploader(
            endpoint: config.endpoint,
            apiKey: config.apiKey
        )
        let filter = DuplicateFilter()

        // Resolve identity: saved real user ID > anonymous ID
        let anonId = IdentityManager.anonymousId()
        let userId = IdentityManager.savedUserId() ?? anonId

        let lifecycleObserver: LifecycleObserver?
        if config.flushOnBackground {
            lifecycleObserver = LifecycleObserver(transport: transport, offlineQueue: queue)
        } else {
            lifecycleObserver = nil
        }

        let (oldTransport, oldObserver): (EventTransport?, LifecycleObserver?) = state.withLock { s in
            let old = (s.transport, s.lifecycleObserver)
            s.configuration = config
            s.deviceInfo = DeviceInfo.collect()
            s.networkMonitor = monitor
            s.offlineQueue = queue
            s.transport = transport
            s.attachmentUploader = attachmentUploader
            s.duplicateFilter = filter
            s.lifecycleObserver = lifecycleObserver
            s.anonymousId = anonId
            s.sessionId = UUID().uuidString
            s.defaultUserId = userId
            s.hasWarnedNotConfigured = false
            return old
        }

        // Stop old observer and flush old transport before replacing
        oldObserver?.stop()
        if let oldTransport {
            Task { await oldTransport.shutdown() }
        }

        lifecycleObserver?.start()

        #if canImport(WatchConnectivity)
        WatchConnectivityBridge.shared.activate()
        #endif

        // Network request instrumentation
        #if canImport(ObjectiveC)
        if config.networkTrackingEnabled {
            URLSessionInstrumentation.install(endpoint: config.endpoint)
        } else {
            URLSessionInstrumentation.disable()
        }
        #endif

        Task {
            await transport.start()
            await filter.start()
            // Drain any watch payloads delivered before configure() finished
            // wiring up (iOS may cold-launch the host app to deliver).
            let pending: [LogEvent] = state.withLock { s in
                let out = s.pendingWatchEvents
                s.pendingWatchEvents = []
                return out
            }
            await transport.enqueue(pending)
        }

        // Idempotent startup reclaim — covers the case where a previous
        // session saved a user id but the claim POST never succeeded.
        // Same in-flight log Task gate as `setUser`: don't claim until any
        // events emitted between configure() returning and this Task running
        // have reached the transport buffer.
        if let savedUserId = IdentityManager.savedUserId(), savedUserId != anonId {
            Task {
                await Self.awaitInFlightLogTasks()
                await transport.claimIdentity(anonymousId: anonId, userId: savedUserId)
            }
        }

        // Auto-capture Apple Search Ads attribution on configure. Opt-out via
        // `attributionEnabled: false`. Fully self-contained: honors the
        // per-install captured flag, handles simulator/non-iOS gracefully,
        // and retries across launches on transient failures.
        //
        // The userId read is deferred into a closure so a `setUser(...)` call
        // that arrives during token fetch (common with async auth flows) is
        // picked up before we POST — otherwise a stale anon id lands on a row
        // the claim merge has already consumed.
        if config.attributionEnabled {
            Task.detached(priority: .background) {
                await AppleSearchAdsAttribution.captureIfNeeded(
                    anonymousId: anonId,
                    currentUserId: { Owl.currentUserId ?? anonId },
                    transport: transport
                )
            }
        }

        // Emit session start event with launch time if available
        var sessionAttributes: [String: String]? = nil
        if let launchMs = Self.processLaunchDurationMs() {
            sessionAttributes = ["_launch_ms": String(launchMs)]
        }
        log("sdk:session_started", level: .info, screenName: nil, attributes: sessionAttributes,
            file: #file, function: #function, line: #line)

        // Bump the per-install launch counter once per process. Drives the
        // `.owlQuestionnaire(...)` trigger conditions.
        OwlQuestionnaireState.shared.markConfiguredOnce()
    }

    // MARK: - Session

    /// The current session ID, or `nil` if the SDK has not been configured.
    public static var sessionId: String? {
        state.withLock { $0.sessionId }
    }

    /// The current user ID used on outgoing events — the real user ID if
    /// `setUser(_:)` has been called, otherwise the device's persistent
    /// anonymous ID. `nil` before `configure()` has been called.
    public static var currentUserId: String? {
        state.withLock { $0.defaultUserId }
    }

    // MARK: - User Identity

    /// Set the real user identifier (call after your app's login).
    /// This persists the ID and triggers a server-side claim to
    /// retroactively associate all anonymous events with this user.
    public static func setUser(_ identifier: String) {
        IdentityManager.saveUserId(identifier)

        let (anonId, transport) = state.withLock { s -> (String?, EventTransport?) in
            let anonId = s.anonymousId
            s.defaultUserId = identifier
            return (anonId, s.transport)
        }

        // Fire claim request to update previously-sent anonymous events.
        // Wait for any in-flight `Owl.log(...)` Tasks to reach the transport
        // buffer first — otherwise the claim's own `flushAll()` could see an
        // empty buffer, POST against an empty events table on the server,
        // and the late-arriving anon events would orphan onto a separate
        // app_users row. See CLAUDE.md "Identity" for the full bug story.
        if let anonId, let transport {
            Task {
                await Self.awaitInFlightLogTasks()
                await transport.claimIdentity(anonymousId: anonId, userId: identifier)
            }
        }
    }

    /// Clear the user identifier (call on logout).
    /// Reverts to the anonymous device ID for future events.
    /// Pass `newAnonymousId: true` to generate a fresh anonymous ID
    /// (use when the device may be shared between users).
    public static func clearUser(newAnonymousId: Bool = false) {
        IdentityManager.clearUserId()

        // Generate new anonymous ID outside the lock (Keychain I/O)
        let freshId = newAnonymousId ? IdentityManager.resetAnonymousId() : nil

        state.withLock { s in
            if let freshId {
                s.anonymousId = freshId
                s.defaultUserId = freshId
            } else {
                s.defaultUserId = s.anonymousId
            }
        }
    }

    // MARK: - User Properties

    /// Set custom properties on the current user. Properties are merged
    /// server-side — existing keys not in this call are preserved.
    /// Pass an empty string value to remove a property.
    public static func setUserProperties(_ properties: [String: String]) {
        let (userId, transport) = state.withLock { s -> (String?, EventTransport?) in
            return (s.defaultUserId, s.transport)
        }
        guard let userId, let transport else { return }
        Task {
            // Symmetric with setUser — let any in-flight log Tasks reach
            // the transport before we issue the user-properties POST so the
            // server's app_users upsert sequencing stays consistent.
            await Self.awaitInFlightLogTasks()
            await transport.setUserProperties(userId: userId, properties: properties)
        }
    }

    // MARK: - Attribution

    /// Submit an Apple Search Ads attribution token obtained by the app
    /// itself (for example from a custom attribution flow) and let Owlmetry
    /// resolve it with Apple.
    ///
    /// You do **not** need to call this in normal use — `Owl.configure()`
    /// auto-captures attribution in the background. Provided for apps that
    /// opt out via `OwlConfiguration.attributionEnabled = false` and manage
    /// token acquisition themselves, and for testing.
    ///
    /// Returns `true` on successful server submission (attributed or not),
    /// `false` on pending, invalid token, or transport failure.
    @discardableResult
    public static func sendAppleSearchAdsAttributionToken(_ token: String) async -> Bool {
        let (anonId, userId, transport) = state.withLock { s -> (String?, String?, EventTransport?) in
            return (s.anonymousId, s.defaultUserId, s.transport)
        }
        guard let anonId, let userId, let transport else { return false }
        return await AppleSearchAdsAttribution.submit(
            token: token,
            anonymousId: anonId,
            userId: userId,
            transport: transport
        )
    }

    /// Clear the "captured" flag for Apple Search Ads attribution on the
    /// current install so the next `Owl.configure()` re-attempts capture.
    /// Intended for development builds and UI tests; production apps should
    /// not need this.
    public static func resetAppleSearchAdsAttributionCapture() {
        let anonId = state.withLock { $0.anonymousId }
        guard let anonId else { return }
        AppleSearchAdsAttribution.State.reset(anonymousId: anonId)
    }

    // MARK: - Logging

    public static func info(
        _ message: String,
        screenName: String? = nil,
        attributes: [String: String?] = [:],
        attachments: [OwlAttachment]? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .info, screenName: screenName, attributes: cleanAttributes(attributes), attachments: attachments,
            file: file, function: function, line: line)
    }

    public static func debug(
        _ message: String,
        screenName: String? = nil,
        attributes: [String: String?] = [:],
        attachments: [OwlAttachment]? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .debug, screenName: screenName, attributes: cleanAttributes(attributes), attachments: attachments,
            file: file, function: function, line: line)
    }

    public static func warn(
        _ message: String,
        screenName: String? = nil,
        attributes: [String: String?] = [:],
        attachments: [OwlAttachment]? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .warn, screenName: screenName, attributes: cleanAttributes(attributes), attachments: attachments,
            file: file, function: function, line: line)
    }

    public static func error(
        _ message: String,
        screenName: String? = nil,
        attributes: [String: String?] = [:],
        attachments: [OwlAttachment]? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .error, screenName: screenName, attributes: cleanAttributes(attributes), attachments: attachments,
            file: file, function: function, line: line)
    }

    /// Report an error/exception value. Extracts the runtime type, NSError
    /// domain/code, underlying-error cause chain, and the call stack into
    /// `_error_*` reserved attributes. The server's issue tracker uses
    /// `_error_type` as a fingerprint discriminator so different error
    /// classes with the same wording stay on separate issues.
    ///
    /// Pass an optional `message` to override the auto-derived event message
    /// with caller context (e.g. `Owl.error(err, "while loading photos")`).
    public static func error(
        _ error: Error,
        _ message: String? = nil,
        screenName: String? = nil,
        attributes: [String: String?] = [:],
        attachments: [OwlAttachment]? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        // Capture stack at the call site (caller is at index >=1; index 0
        // is this method) so SDK helper frames don't pollute it.
        let callStack = Thread.callStackSymbols

        let extracted = ErrorExtraction.extract(
            error: error,
            userMessage: message,
            callStack: callStack
        )

        var merged = cleanAttributes(attributes) ?? [:]
        // SDK-owned `_error_*` keys take precedence over caller-provided
        // values to keep fingerprinting + dashboard rendering consistent.
        for (k, v) in extracted.attributes {
            merged[k] = v
        }

        log(extracted.message, level: .error, screenName: screenName,
            attributes: merged, attachments: attachments,
            file: file, function: function, line: line)
    }

    // MARK: - Funnel Steps

    /// Record a funnel step. Sends an info-level event with message `"step:<stepName>"`.
    public static func step(
        _ stepName: String,
        attributes: [String: String?] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        info("step:\(stepName)", attributes: attributes, file: file, function: function, line: line)
    }

    /// Record a funnel step.
    /// - Note: Deprecated. Use `step(_:attributes:)` instead.
    @available(*, deprecated, renamed: "step(_:attributes:file:function:line:)")
    public static func track(
        _ stepName: String,
        attributes: [String: String?] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        step(stepName, attributes: attributes, file: file, function: function, line: line)
    }

    // MARK: - User Feedback

    /// Submit user feedback synchronously. Returns an `OwlFeedbackReceipt` on success
    /// so the caller can confirm the server received the submission.
    ///
    /// This is NOT offline-queued — if the network is unavailable the call throws and
    /// the caller should let the user retry. Session, user id, device info, and
    /// environment are attached automatically.
    ///
    /// - Parameters:
    ///   - message: The feedback text. Required. Trimmed server-side; must be 1..4000 characters.
    ///   - name: Optional submitter display name.
    ///   - email: Optional submitter email (validated server-side).
    @discardableResult
    public static func sendFeedback(
        message: String,
        name: String? = nil,
        email: String? = nil
    ) async throws -> OwlFeedbackReceipt {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw OwlFeedbackError.emptyMessage }

        let snapshot = state.withLock { s -> (EventTransport, String, DeviceInfo, String?, String?)? in
            guard let transport = s.transport,
                  let config = s.configuration,
                  let deviceInfo = s.deviceInfo else {
                if !s.hasWarnedNotConfigured {
                    s.hasWarnedNotConfigured = true
                    logger.warning("Owl.configure() has not been called. sendFeedback dropped.")
                }
                return nil
            }
            return (transport, config.bundleId, deviceInfo, s.defaultUserId, s.sessionId)
        }

        guard let (transport, bundleId, deviceInfo, userId, sessionId) = snapshot else {
            throw OwlFeedbackError.notConfigured
        }

        #if DEBUG
        let isDev = true
        #else
        let isDev = false
        #endif

        func trimNil(_ s: String?) -> String? {
            guard let s else { return nil }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }

        let body = FeedbackRequestBody(
            bundle_id: bundleId,
            message: trimmed,
            session_id: sessionId,
            user_id: userId,
            submitter_name: trimNil(name),
            submitter_email: trimNil(email),
            app_version: deviceInfo.appVersion,
            sdk_name: OwlmetryVersion.name,
            sdk_version: OwlmetryVersion.current,
            environment: deviceInfo.platform.rawValue,
            device_model: deviceInfo.deviceModel,
            os_version: deviceInfo.osVersion,
            is_dev: isDev
        )

        let result = await transport.submitFeedback(body)
        switch result {
        case .success(let receipt):
            // Audit trail — feedback submission is observable in the event stream.
            log("sdk:feedback_submitted", level: .info, screenName: nil,
                attributes: ["has_email": trimNil(email) != nil ? "true" : "false",
                             "has_name": trimNil(name) != nil ? "true" : "false"],
                file: #file, function: #function, line: #line)
            return receipt
        case .failure(let error):
            throw error
        }
    }

    // MARK: - Questionnaires

    /// Total number of times `Owl.configure(...)` has completed since install.
    public static var launchCount: Int { OwlQuestionnaireState.shared.launchCount }
    /// Total number of foreground transitions since install.
    public static var foregroundCount: Int { OwlQuestionnaireState.shared.foregroundCount }
    /// Timestamp of the first-ever `Owl.configure(...)` on this install.
    public static var firstLaunchAt: Date? { OwlQuestionnaireState.shared.firstLaunchAt }

    /// Fetch a questionnaire by slug. Returns `nil` when the user is ineligible
    /// (already responded, globally dismissed, or the questionnaire is inactive).
    /// Throws on slug-not-found or transport / server errors.
    public static func fetchQuestionnaire(slug: String) async throws -> OwlQuestionnaire? {
        let snapshot = transportSnapshot()
        guard let snapshot else { throw OwlQuestionnaireError.notConfigured }
        let result = await snapshot.transport.fetchQuestionnaire(slug: slug, userId: snapshot.userId)
        switch result {
        case .success(let q): return q
        case .failure(let err): throw err
        }
    }

    /// Submit a completed response. Answers are validated against the
    /// questionnaire's current schema on the server. Returns a receipt with
    /// the response id and server timestamp.
    public static func submitQuestionnaireResponse(
        slug: String,
        answers: [String: OwlQuestionnaireAnswerValue]
    ) async throws -> OwlQuestionnaireReceipt {
        let snapshot = transportSnapshot()
        guard let snapshot else { throw OwlQuestionnaireError.notConfigured }

        #if DEBUG
        let isDev = true
        #else
        let isDev = false
        #endif

        let result = await snapshot.transport.submitQuestionnaireResponse(
            slug: slug,
            userId: snapshot.userId,
            sessionId: snapshot.sessionId,
            answers: answers,
            deviceInfo: snapshot.deviceInfo,
            environment: snapshot.deviceInfo.platform.rawValue,
            appVersion: snapshot.deviceInfo.appVersion,
            isDev: isDev
        )
        switch result {
        case .success(let receipt):
            log("sdk:questionnaire_submitted", level: .info, screenName: nil,
                attributes: ["slug": slug],
                file: #file, function: #function, line: #line)
            return receipt
        case .failure(let err):
            throw err
        }
    }

    /// Globally opt the current user out of every questionnaire. Idempotent.
    /// Survives reinstall (stored in `app_users.properties` server-side).
    @discardableResult
    public static func dismissQuestionnaires() async throws -> Date {
        let snapshot = transportSnapshot()
        guard let snapshot, let userId = snapshot.userId else {
            throw OwlQuestionnaireError.notConfigured
        }
        let result = await snapshot.transport.submitQuestionnaireDismiss(userId: userId)
        switch result {
        case .success(let date):
            log("sdk:questionnaire_dismissed", level: .info, screenName: nil, attributes: nil,
                file: #file, function: #function, line: #line)
            return date
        case .failure(let err): throw err
        }
    }

    // Process-local dedupe so a single launch doesn't re-present the same slug
    // even if the gate's `.task` is re-entered or two view modifiers with the
    // same slug both fire. Cross-launch dedupe is the server's job.
    private static let shownLock = NSLock()
    nonisolated(unsafe) private static var shownSlugs = Set<String>()

    static func questionnaireWasShownThisProcess(slug: String) -> Bool {
        shownLock.lock(); defer { shownLock.unlock() }
        return shownSlugs.contains(slug)
    }

    static func markQuestionnaireShown(slug: String) {
        shownLock.lock(); defer { shownLock.unlock() }
        shownSlugs.insert(slug)
    }

    private struct TransportSnapshot {
        let transport: EventTransport
        let userId: String?
        let sessionId: String?
        let deviceInfo: DeviceInfo
    }

    private static func transportSnapshot() -> TransportSnapshot? {
        state.withLock { s -> TransportSnapshot? in
            guard let transport = s.transport,
                  let deviceInfo = s.deviceInfo else {
                if !s.hasWarnedNotConfigured {
                    s.hasWarnedNotConfigured = true
                    logger.warning("Owl.configure() has not been called. Questionnaire call dropped.")
                }
                return nil
            }
            return TransportSnapshot(
                transport: transport,
                userId: s.defaultUserId,
                sessionId: s.sessionId,
                deviceInfo: deviceInfo
            )
        }
    }

    // MARK: - Structured Metrics

    /// Regex for valid metric slugs: lowercase letters, numbers, and hyphens only.
    private static let slugRegex = try! NSRegularExpression(pattern: "^[a-z0-9-]+$")

    /// Normalize a metric slug to contain only lowercase letters, numbers, and hyphens.
    /// Logs a warning if the slug was modified.
    private static func normalizeSlug(_ slug: String) -> String {
        let range = NSRange(slug.startIndex..., in: slug)
        if slugRegex.firstMatch(in: slug, range: range) != nil {
            return slug
        }
        var normalized = slug.lowercased()
        normalized = normalized.replacingOccurrences(
            of: "[^a-z0-9-]", with: "-", options: .regularExpression)
        normalized = normalized.replacingOccurrences(
            of: "-{2,}", with: "-", options: .regularExpression)
        normalized = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        logger.warning("Metric slug \"\(slug)\" was auto-corrected to \"\(normalized)\". Slugs should contain only lowercase letters, numbers, and hyphens.")
        return normalized
    }

    /// Start a tracked operation. Returns an `Operation` object whose `complete()`, `fail()`,
    /// or `cancel()` method should be called when the operation finishes.
    ///
    /// The `metric` slug should contain only lowercase letters, numbers, and hyphens
    /// (e.g. `"photo-conversion"`, `"api-request"`). Invalid characters are auto-corrected
    /// with a warning logged.
    public static func startOperation(
        _ metric: String,
        attributes: [String: String?] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) -> OwlOperation {
        let slug = normalizeSlug(metric)
        let op = OwlOperation(metric: slug)
        var attrs: [String: String?] = attributes
        attrs["tracking_id"] = op.trackingId
        info("metric:\(slug):start", attributes: attrs, file: file, function: function, line: line)
        return op
    }

    /// Record a single-shot metric (no lifecycle).
    ///
    /// The `metric` slug should contain only lowercase letters, numbers, and hyphens
    /// (e.g. `"onboarding"`, `"checkout"`). Invalid characters are auto-corrected
    /// with a warning logged.
    public static func recordMetric(
        _ metric: String,
        attributes: [String: String?] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let slug = normalizeSlug(metric)
        info("metric:\(slug):record", attributes: attributes, file: file, function: function, line: line)
    }

    // MARK: - watchOS Companion

    #if canImport(WatchConnectivity) && !os(watchOS)
    /// Forward a `WCSession` user-info payload into the Owlmetry pipeline.
    /// Call this from your iPhone app's existing `WCSessionDelegate`:
    ///
    /// ```swift
    /// func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
    ///     if Owl.handleWatchUserInfo(userInfo) { return }
    ///     // ... your existing handling
    /// }
    /// ```
    ///
    /// Returns `true` when the payload was an Owlmetry envelope (decoded
    /// and queued for ingest), `false` otherwise — let the caller continue
    /// its own handling.
    ///
    /// Safe to call before `Owl.configure()`: events are buffered and
    /// drained automatically once configuration completes.
    @discardableResult
    public static func handleWatchUserInfo(_ userInfo: [String: Any]) -> Bool {
        guard let events = WatchConnectivityBridge.decodeEnvelope(userInfo) else {
            return false
        }

        let transport: EventTransport? = state.withLock { s in
            if let transport = s.transport {
                return transport
            }
            s.pendingWatchEvents.append(contentsOf: events)
            return nil
        }

        if let transport {
            Task { await transport.enqueue(events) }
        }
        return true
    }
    #endif

    // MARK: - Lifecycle

    public static func shutdown() async {
        let (transport, observer) = state.withLock { ($0.transport, $0.lifecycleObserver) }
        observer?.stop()
        await transport?.shutdown()
    }

    // MARK: - Testing Support

    /// Reset all SDK state, simulating an app restart.
    /// After calling this, `configure()` must be called again.
    /// Persistent state (Keychain anonymous ID, UserDefaults) is NOT cleared,
    /// matching real app restart behavior.
    static func reset() async {
        #if canImport(ObjectiveC)
        URLSessionInstrumentation.disable()
        #endif
        let (oldTransport, oldObserver) = state.withLock { s -> (EventTransport?, LifecycleObserver?) in
            let old = (s.transport, s.lifecycleObserver)
            s = State()
            return old
        }
        oldObserver?.stop()
        await oldTransport?.shutdown()
    }

    /// Access the offline queue for testing.
    static var _offlineQueue: OfflineQueue? {
        state.withLock { $0.offlineQueue }
    }

    /// Access the event transport for testing.
    static func _transportForTests() -> EventTransport? {
        state.withLock { $0.transport }
    }

    // MARK: - Internal

    /// Suspend until every in-flight `Owl.log(...)` Task has reached the
    /// EventTransport buffer. Used by setUser, setUserProperties, the
    /// configure-time startup reclaim, and the attribution submit path so
    /// outbound writes that depend on prior events being ingestible never
    /// race ahead of them.
    ///
    /// Returns immediately when the counter is already zero — no need to
    /// suspend on the cooperative pool just to assert "nothing to wait for".
    static func awaitInFlightLogTasks() async {
        let needsWait: Bool = state.withLock { $0.inFlightLogTasks > 0 }
        if !needsWait { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            // Re-check inside the lock to avoid a TOCTOU where the last log
            // Task drained between our check above and appending here.
            let resumeNow: Bool = state.withLock { s in
                if s.inFlightLogTasks == 0 {
                    return true
                }
                s.pendingLogDrains.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    /// Filter out nil values from caller-supplied attributes so optional
    /// strings can flow through `attributes:` without unwrapping at the call
    /// site. Returns `nil` if nothing remains, matching the existing
    /// "no custom attributes" path through the pipeline.
    static func cleanAttributes(_ attributes: [String: String?]) -> [String: String]? {
        let filtered = attributes.compactMapValues { $0 }
        return filtered.isEmpty ? nil : filtered
    }

    private static func printToConsole(
        _ message: String,
        level: OwlLogLevel,
        attributes: [String: String]?
    ) {
        if message.hasPrefix("sdk:") { return }
        if message.hasPrefix("metric:") && message.hasSuffix(":start") { return }

        let tag: String
        switch level {
        case .info:  tag = "INFO "
        case .debug: tag = "DEBUG"
        case .warn:  tag = "WARN "
        case .error: tag = "ERROR"
        }

        let stepPrefix = "step:"
        let legacyTrackPrefix = "track:" // Legacy prefix from older SDK versions

        let displayMessage: String
        if message.hasPrefix(stepPrefix) {
            displayMessage = "step: \(String(message.dropFirst(stepPrefix.count)))"
        } else if message.hasPrefix(legacyTrackPrefix) {
            displayMessage = "step: \(String(message.dropFirst(legacyTrackPrefix.count)))"
        } else if message.hasPrefix("metric:") {
            let body = String(message.dropFirst(7))
            if let colonIndex = body.firstIndex(of: ":") {
                let metricName = body[body.startIndex..<colonIndex]
                let phase = body[body.index(after: colonIndex)...]
                displayMessage = "metric: \(metricName) \(phase)"
            } else {
                displayMessage = "metric: \(body)"
            }
        } else {
            displayMessage = message
        }

        var line = "🦉  \(tag) \(displayMessage)"
        if let attributes, !attributes.isEmpty {
            let pairs = attributes.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            line += " {\(pairs)}"
        }

        print(line)
    }

    private static func log(
        _ message: String,
        level: OwlLogLevel,
        screenName: String?,
        attributes: [String: String]?,
        attachments: [OwlAttachment]? = nil,
        file: String,
        function: String,
        line: Int
    ) {
        let snapshot = state.withLock { s -> (DeviceInfo, EventTransport, AttachmentUploader?, DuplicateFilter, String?, String?, String, Bool)? in
            guard let deviceInfo = s.deviceInfo,
                  let transport = s.transport,
                  let filter = s.duplicateFilter,
                  let config = s.configuration else {
                if !s.hasWarnedNotConfigured {
                    s.hasWarnedNotConfigured = true
                    logger.warning("Owl.configure() has not been called. Events are being dropped.")
                }
                return nil
            }
            let networkStatus = s.networkMonitor?.status.rawValue ?? "unknown"
            return (deviceInfo, transport, s.attachmentUploader, filter, s.defaultUserId, s.sessionId, networkStatus, config.consoleLogging)
        }

        guard let (deviceInfo, transport, attachmentUploader, duplicateFilter, defaultUser, sessionId, networkStatus, consoleLogging) = snapshot else { return }

        if consoleLogging {
            printToConsole(message, level: level, attributes: attributes)
        }

        #if DEBUG
        let isDev = true
        #else
        let isDev = false
        #endif

        let event = EventBuilder.build(
            message: message,
            level: level,
            screenName: screenName,
            customAttributes: attributes,
            userId: defaultUser,
            sessionId: sessionId ?? UUID().uuidString,
            deviceInfo: deviceInfo,
            isDev: isDev,
            networkStatus: networkStatus,
            file: file,
            function: function,
            line: line
        )

        let clientEventId = event.clientEventId

        // Bump the in-flight counter synchronously so a setUser/claim Task
        // spawned right after this `log` call sees inFlightLogTasks > 0 and
        // waits for us. The Task body decrements + signals waiters on exit.
        state.withLock { $0.inFlightLogTasks += 1 }
        Task {
            defer {
                let waitersToResume: [CheckedContinuation<Void, Never>] = state.withLock { s in
                    s.inFlightLogTasks -= 1
                    guard s.inFlightLogTasks == 0 else { return [] }
                    let pending = s.pendingLogDrains
                    s.pendingLogDrains = []
                    return pending
                }
                for waiter in waitersToResume { waiter.resume() }
            }
            guard await duplicateFilter.shouldAllow(event) else { return }
            await transport.enqueue(event)
        }

        if let attachments, !attachments.isEmpty, let uploader = attachmentUploader {
            Task {
                await uploader.enqueue(clientEventId: clientEventId, userId: defaultUser, isDev: isDev, attachments: attachments)
            }
        }
    }

    /// Returns milliseconds from process start to now using sysctl, or nil on failure.
    private static func processLaunchDurationMs() -> Int? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0 else { return nil }
        let startSec = Double(info.kp_proc.p_starttime.tv_sec)
        let startUsec = Double(info.kp_proc.p_starttime.tv_usec)
        let processStart = startSec + startUsec / 1_000_000
        let now = Date().timeIntervalSince1970
        let ms = Int((now - processStart) * 1000)
        return ms > 0 ? ms : nil
    }
}
