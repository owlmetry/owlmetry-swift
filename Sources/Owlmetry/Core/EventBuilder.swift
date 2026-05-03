import Foundation

/// Assembles every outgoing `LogEvent` from the SDK. SDK identity
/// (`sdk_name`, `sdk_version`) is stamped here from `OwlmetryVersion`
/// so consumers never need to set it on the call site.
enum EventBuilder {
    static let systemMetaKeys: Set<String> = ["_file", "_function", "_line", "_connection"]

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func build(
        message: String,
        level: OwlLogLevel,
        screenName: String?,
        customAttributes: [String: String]?,
        userId: String?,
        sessionId: String,
        deviceInfo: DeviceInfo,
        isDev: Bool,
        networkStatus: String,
        file: String,
        function: String,
        line: Int
    ) -> LogEvent {
        let fileName: String
        if let lastSlash = file.lastIndex(of: "/") {
            fileName = String(file[file.index(after: lastSlash)...])
        } else {
            fileName = file
        }

        var mergedAttributes = CustomAttributeTrimmer.trim(customAttributes) ?? [:]
        mergedAttributes["_file"] = fileName
        mergedAttributes["_function"] = function
        mergedAttributes["_line"] = String(line)
        mergedAttributes["_connection"] = networkStatus

        let allExperiments = ExperimentManager.shared.allExperiments()

        return LogEvent(
            clientEventId: UUID().uuidString,
            sessionId: sessionId,
            userId: userId,
            level: level,
            sourceModule: "\(fileName):\(function):\(line)",
            message: MessageTrimmer.trim(message),
            screenName: screenName,
            customAttributes: mergedAttributes.isEmpty ? nil : mergedAttributes,
            environment: deviceInfo.platform,
            osVersion: deviceInfo.osVersion,
            appVersion: deviceInfo.appVersion,
            sdkName: OwlmetryVersion.name,
            sdkVersion: OwlmetryVersion.current,
            buildNumber: deviceInfo.buildNumber,
            deviceModel: deviceInfo.deviceModel,
            locale: deviceInfo.locale,
            isDev: isDev,
            experiments: allExperiments.isEmpty ? nil : allExperiments,
            timestamp: isoFormatter.string(from: Date())
        )
    }
}
