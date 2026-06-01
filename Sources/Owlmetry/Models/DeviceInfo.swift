import Foundation

#if canImport(UIKit)
import UIKit
#endif

struct DeviceInfo: Sendable {
    let platform: OwlPlatform
    let osVersion: String
    let appVersion: String?
    let buildNumber: String?
    let deviceModel: String
    /// The *shown* locale. `Locale.current` resolves the user's preferences
    /// against the languages the app actually ships, so its language component
    /// can't reveal demand for a language we don't ship yet.
    let locale: String
    /// The user's top *wanted* language (`Locale.preferredLanguages.first`),
    /// unconstrained by the app — the localization-demand signal. A French user
    /// of an English-only app reports `fr` here while `locale` shows English.
    let preferredLanguage: String?
    /// Every language this app binary ships (`Bundle.main.localizations`, minus
    /// the "Base" pseudo-localization). Lets the server keep the app's shipped
    /// languages current with zero manual upkeep, to compute the gap against
    /// preferred-language demand.
    let supportedLanguages: [String]

    static func collect() -> DeviceInfo {
        DeviceInfo(
            platform: detectPlatform(),
            osVersion: formatOSVersion(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
            deviceModel: getDeviceModel(),
            locale: Locale.current.identifier,
            preferredLanguage: Locale.preferredLanguages.first,
            supportedLanguages: Bundle.main.localizations.filter { $0 != "Base" }
        )
    }

    private static func detectPlatform() -> OwlPlatform {
        #if os(macOS)
        return .macos
        #elseif os(watchOS)
        return .watchos
        #else
        if ProcessInfo.processInfo.isMacCatalystApp {
            return .macos
        } else if UIDevice.current.userInterfaceIdiom == .pad {
            return .ipados
        } else {
            return .ios
        }
        #endif
    }

    private static func formatOSVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private static func getDeviceModel() -> String {
        var size = 0
        guard sysctlbyname("hw.machine", nil, &size, nil, 0) == 0, size > 0 else {
            return "Unknown"
        }
        var machine = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.machine", &machine, &size, nil, 0) == 0 else {
            return "Unknown"
        }
        return String(cString: machine)
    }
}
