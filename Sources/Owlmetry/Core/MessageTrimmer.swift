import Foundation

enum MessageTrimmer {
    static let maxEventMessageLength = 2000

    static func trim(_ message: String) -> String {
        if message.count > maxEventMessageLength {
            return String(message.prefix(maxEventMessageLength))
        }
        return message
    }
}
