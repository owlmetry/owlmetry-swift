import Foundation

/// Persistent state every questionnaire trigger condition reads from. Lives
/// in the same UserDefaults suite as `IdentityManager`'s real-user-id so
/// install scope matches. Single source of truth for launch / foreground
/// counters and the install timestamp.
///
/// All counters increment idempotently per process via in-memory flags so a
/// hot reload of `Owl.configure(...)` doesn't double-count.
public final class OwlQuestionnaireState: @unchecked Sendable {
    public static let shared = OwlQuestionnaireState()

    static let launchCountKey = "owlmetry.questionnaire.launch_count"
    static let foregroundCountKey = "owlmetry.questionnaire.foreground_count"
    static let firstLaunchAtKey = "owlmetry.questionnaire.first_launch_at"

    private let lock = NSLock()
    private var didMarkConfigured = false
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Called once per process from the tail of `Owl.configureWith(_:)`.
    /// Increments `launch_count` and sets `first_launch_at` the first time.
    public func markConfiguredOnce(now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        guard !didMarkConfigured else { return }
        didMarkConfigured = true

        let next = defaults.integer(forKey: Self.launchCountKey) + 1
        defaults.set(next, forKey: Self.launchCountKey)

        if defaults.object(forKey: Self.firstLaunchAtKey) == nil {
            defaults.set(now.timeIntervalSinceReferenceDate, forKey: Self.firstLaunchAtKey)
        }
    }

    /// Called from `LifecycleObserver` on every foreground transition. The
    /// process-cold-launch path doesn't double-fire because iOS only delivers
    /// `willEnterForeground` after the first background-to-foreground.
    public func incrementForeground() {
        lock.lock()
        defer { lock.unlock() }
        let next = defaults.integer(forKey: Self.foregroundCountKey) + 1
        defaults.set(next, forKey: Self.foregroundCountKey)
    }

    public var launchCount: Int {
        defaults.integer(forKey: Self.launchCountKey)
    }

    public var foregroundCount: Int {
        defaults.integer(forKey: Self.foregroundCountKey)
    }

    public var firstLaunchAt: Date? {
        let raw = defaults.double(forKey: Self.firstLaunchAtKey)
        guard raw > 0 else { return nil }
        return Date(timeIntervalSinceReferenceDate: raw)
    }

    /// Immutable snapshot for pure condition evaluation. Used by the view
    /// modifier so triggers don't re-read UserDefaults mid-evaluation.
    public func snapshot(now: Date = Date()) -> Snapshot {
        Snapshot(
            launchCount: launchCount,
            foregroundCount: foregroundCount,
            firstLaunchAt: firstLaunchAt,
            now: now
        )
    }

    public struct Snapshot: Sendable {
        public let launchCount: Int
        public let foregroundCount: Int
        public let firstLaunchAt: Date?
        public let now: Date

        public func daysSinceFirstLaunch() -> Double {
            guard let first = firstLaunchAt else { return 0 }
            return now.timeIntervalSince(first) / 86_400
        }

        public func hoursSinceFirstLaunch() -> Double {
            guard let first = firstLaunchAt else { return 0 }
            return now.timeIntervalSince(first) / 3_600
        }
    }

    // Debug-only escape hatch for the demo app's "Reset persistent state" button.
    public func _debugReset() {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: Self.launchCountKey)
        defaults.removeObject(forKey: Self.foregroundCountKey)
        defaults.removeObject(forKey: Self.firstLaunchAtKey)
        didMarkConfigured = false
    }
}
