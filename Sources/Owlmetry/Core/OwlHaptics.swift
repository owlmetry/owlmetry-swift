import Foundation
#if canImport(UIKit) && !os(watchOS) && !os(macOS)
import UIKit
#endif

/// Lightweight haptic feedback helpers used by the SDK's SwiftUI surfaces
/// (`OwlFeedbackView`, `OwlQuestionnaireView` and friends). Falls back to a
/// no-op on platforms without `UIImpactFeedbackGenerator` so callers can
/// invoke unconditionally without `#if` boilerplate at every call site.
enum OwlHaptics {
    /// Fire-and-forget light tap. Cheap to call on every button action — the
    /// system de-dupes rapid invocations and skips when haptics are disabled
    /// in Accessibility settings or unsupported by hardware.
    @MainActor
    static func tap() {
        #if canImport(UIKit) && !os(watchOS) && !os(macOS) && !os(tvOS) && !os(visionOS)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #endif
    }
}
