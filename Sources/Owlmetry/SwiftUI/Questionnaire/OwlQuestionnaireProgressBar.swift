#if canImport(SwiftUI) && !os(watchOS)
import SwiftUI

/// Segmented horizontal progress bar — one segment per question, filled
/// through and including the current index. Matches the visual pattern in
/// `SewingPatterns/iOS/.../OnboardingView.swift:183-194` and
/// `LegalScan/.../OnboardingView.swift:23-32`.
struct OwlQuestionnaireProgressBar: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<max(total, 1), id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(i <= current ? Color.accentColor : Color.gray.opacity(0.25))
                    .frame(height: 4)
                    .animation(.easeInOut(duration: 0.25), value: current)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Step \(current + 1) of \(total)"))
    }
}
#endif
