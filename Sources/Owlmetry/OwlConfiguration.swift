import Foundation

public struct OwlConfiguration: Sendable {
    let endpoint: URL
    let apiKey: String
    let bundleId: String
    let flushOnBackground: Bool
    let compressionEnabled: Bool
    let networkTrackingEnabled: Bool
    let consoleLogging: Bool
    let attributionEnabled: Bool

    private static let clientKeyPrefix = "owl_client_"

    public init(
        endpoint: String,
        apiKey: String,
        flushOnBackground: Bool = true,
        compressionEnabled: Bool = true,
        networkTrackingEnabled: Bool = true,
        consoleLogging: Bool = true,
        attributionEnabled: Bool = true
    ) throws {
        guard let bundleId = Self.resolveBundleId(), !bundleId.isEmpty else {
            throw OwlConfigurationError.missingBundleId
        }
        try self.init(
            endpoint: endpoint,
            apiKey: apiKey,
            bundleId: bundleId,
            flushOnBackground: flushOnBackground,
            compressionEnabled: compressionEnabled,
            networkTrackingEnabled: networkTrackingEnabled,
            consoleLogging: consoleLogging,
            attributionEnabled: attributionEnabled
        )
    }

    /// On watchOS, prefer the iOS counterpart's bundle ID (via
    /// `WKCompanionAppBundleIdentifier` in Info.plist) so events from the
    /// watch ingest under the same registered app as the iPhone, and direct
    /// HTTP from cellular watches doesn't 403 on bundle_id mismatch. Falls
    /// back to the watch's own bundle ID for standalone watch apps with no
    /// iOS counterpart.
    private static func resolveBundleId() -> String? {
        #if os(watchOS)
        if let companion = Bundle.main.object(forInfoDictionaryKey: "WKCompanionAppBundleIdentifier") as? String,
           !companion.isEmpty {
            return companion
        }
        #endif
        return Bundle.main.bundleIdentifier
    }

    /// Internal initializer for testing with an explicit bundle ID.
    init(
        endpoint: String,
        apiKey: String,
        bundleId: String,
        flushOnBackground: Bool = true,
        compressionEnabled: Bool = true,
        networkTrackingEnabled: Bool = true,
        consoleLogging: Bool = true,
        attributionEnabled: Bool = true
    ) throws {
        guard let url = URL(string: endpoint) else {
            throw OwlConfigurationError.invalidEndpoint(endpoint)
        }
        guard apiKey.hasPrefix(Self.clientKeyPrefix) else {
            throw OwlConfigurationError.invalidApiKey("API key must start with \"\(Self.clientKeyPrefix)\"")
        }
        guard !bundleId.isEmpty else {
            throw OwlConfigurationError.missingBundleId
        }
        self.endpoint = url
        self.apiKey = apiKey
        self.bundleId = bundleId
        self.flushOnBackground = flushOnBackground
        self.compressionEnabled = compressionEnabled
        self.networkTrackingEnabled = networkTrackingEnabled
        self.consoleLogging = consoleLogging
        self.attributionEnabled = attributionEnabled
    }
}

public enum OwlConfigurationError: LocalizedError {
    case invalidEndpoint(String)
    case invalidApiKey(String)
    case missingBundleId

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint(let value):
            return "Invalid endpoint URL: \(value)"
        case .invalidApiKey(let message):
            return message
        case .missingBundleId:
            return "Bundle ID could not be determined. Ensure the app has a valid bundle identifier."
        }
    }
}
