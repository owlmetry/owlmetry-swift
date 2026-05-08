import Foundation

/// Extracts structured fields from a Swift `Error` for `Owl.error(_:Error)`.
/// Output is delivered as `_error_*` reserved custom attributes, which the
/// server reads for issue fingerprinting (`_error_type` becomes the
/// fingerprint discriminator) and dashboard display.
enum ErrorExtraction {
    static let maxCauseDepth = 5
    static let maxStackLength = 16000

    struct Result {
        let message: String
        let attributes: [String: String]
    }

    /// - Parameters:
    ///   - error: the value passed to `Owl.error(_:Error)`.
    ///   - userMessage: optional caller-provided context. When non-empty it is
    ///     used as the event message; otherwise we derive one from the error.
    ///   - callStack: result of `Thread.callStackSymbols` captured at the
    ///     public `Owl.error` body (so SDK helper frames don't leak in).
    static func extract(
        error: Error,
        userMessage: String?,
        callStack: [String]
    ) -> Result {
        var attrs: [String: String] = [:]

        attrs["_error_type"] = String(reflecting: type(of: error))

        if !callStack.isEmpty {
            let joined = callStack.joined(separator: "\n")
            attrs["_error_stack"] = joined.count > maxStackLength
                ? String(joined.prefix(maxStackLength))
                : joined
        }

        // Every Swift Error bridges to NSError automatically; the bridge
        // synthesizes domain (= type name) + code (= enum case ordinal) for
        // pure-Swift errors and forwards real values for Foundation/Cocoa.
        let ns = error as NSError
        attrs["_error_domain"] = ns.domain
        attrs["_error_code"] = String(ns.code)

        var current = ns.userInfo[NSUnderlyingErrorKey] as? NSError
        var depth = 1
        while let cause = current, depth <= maxCauseDepth {
            attrs["_error_cause_\(depth)_type"] = cause.domain
            attrs["_error_cause_\(depth)_message"] = cause.localizedDescription
            current = cause.userInfo[NSUnderlyingErrorKey] as? NSError
            depth += 1
        }

        let resolvedMessage = resolveMessage(error: error, userMessage: userMessage)

        return Result(message: resolvedMessage, attributes: attrs)
    }

    /// Caller-provided message wins. Otherwise prefer `localizedDescription`
    /// when it isn't the Foundation bridge fallback ("The operation couldn't
    /// be completed. (Module.Type error N.)"), since for native Foundation
    /// errors it carries the most useful human-readable text. Fall back to
    /// `String(describing:)` which preserves Swift enum case names with
    /// associated values (e.g. `paymentFailed("declined")`).
    private static func resolveMessage(error: Error, userMessage: String?) -> String {
        if let user = userMessage?.trimmingCharacters(in: .whitespacesAndNewlines), !user.isEmpty {
            return user
        }
        let localized = error.localizedDescription
        let described = String(describing: error)
        if !localized.isEmpty && !looksLikeBridgeFallback(localized) {
            return localized
        }
        return described.isEmpty ? localized : described
    }

    private static func looksLikeBridgeFallback(_ s: String) -> Bool {
        s.contains("(") && s.contains("error ") && s.hasSuffix(".)")
    }
}
