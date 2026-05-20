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
        // Done button pinned outside the ScrollView so it's always reachable
        // regardless of how long the success message is. The ScrollView wraps
        // the icon + title + message so any custom override from
        // `OwlQuestionnaireStrings` that exceeds the sheet height scrolls
        // instead of pushing the button off-screen.
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ScrollView {
                    // VStack-of-Spacers + minHeight pattern centers the
                    // content vertically when it fits, and lets the inner
                    // VStack grow beyond the scroll height (scrolling) when
                    // it doesn't.
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)

                        VStack(spacing: 20) {
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
                                .fixedSize(horizontal: false, vertical: true)

                            Text(message)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 32)
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
            }

            Button {
                OwlHaptics.tap()
                onDone()
            } label: {
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
