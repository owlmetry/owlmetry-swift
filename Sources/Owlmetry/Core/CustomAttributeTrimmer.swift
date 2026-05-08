import Foundation

enum CustomAttributeTrimmer {
    static let maxCustomAttributeValueLength = 200

    // Per-key length overrides for trusted SDK-reserved attribute keys
    // (always underscore-prefixed). Mirrors the server's
    // RESERVED_ATTRIBUTE_VALUE_LENGTH_OVERRIDES so values that legitimately
    // exceed 200 chars (stack traces) survive the SDK trim before transport.
    static let reservedKeyLengthOverrides: [String: Int] = [
        "_error_stack": 16000,
    ]

    static func trim(_ customAttributes: [String: String]?) -> [String: String]? {
        guard let customAttributes else { return nil }
        guard !customAttributes.isEmpty else { return customAttributes }

        var result: [String: String] = [:]
        result.reserveCapacity(customAttributes.count)
        for (key, value) in customAttributes {
            let cap = reservedKeyLengthOverrides[key] ?? maxCustomAttributeValueLength
            result[key] = value.count > cap ? String(value.prefix(cap)) : value
        }
        return result
    }
}
