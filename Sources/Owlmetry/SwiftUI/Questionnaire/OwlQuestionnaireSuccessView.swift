#if canImport(SwiftUI) && !os(watchOS)
import SwiftUI

/// In-sheet success page rendered for `OwlQuestionnairePhase.success`.
/// Replaces the system alert from the old form-based view so dismissal
/// stays a single tap that goes through `Done` (matches the step-flow's
/// non-swipe-dismissible contract).
struct OwlQuestionnaireSuccessView: View {
    let title: LocalizedStringResource
    let message: LocalizedStringResource
    let doneLabel: LocalizedStringResource
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text(title)
                .font(.title)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            Button(action: onDone) {
                Text(doneLabel)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }
}
#endif
