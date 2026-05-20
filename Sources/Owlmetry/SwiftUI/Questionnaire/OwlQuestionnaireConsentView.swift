#if canImport(SwiftUI) && !os(watchOS)
import SwiftUI

/// Small-detent content rendered for `OwlQuestionnairePhase.consent`. An
/// optional hero icon sits above the large title + body. The primary CTA
/// is the only filled button; "Maybe later" and "Don't ask again" sit
/// below as plain links with generous tap targets so the visual weight
/// tracks user preference without making the secondary actions too small
/// to hit.
struct OwlQuestionnaireConsentView: View {
    let icon: Image?
    let title: LocalizedStringResource
    let message: String
    let acceptLabel: LocalizedStringResource
    let laterLabel: LocalizedStringResource
    let neverLabel: LocalizedStringResource
    let onAccept: () -> Void
    let onLater: () -> Void
    let onNever: () -> Void

    var body: some View {
        // No greedy Spacer between the message and the accept button — a Spacer
        // here forces the VStack to fill its parent vertically, which under a
        // fixed sheet detent compresses the message Text to a single line and
        // truncates it. Hugging the content lets the container measure the
        // intrinsic height and size the detent to match.
        VStack(alignment: .leading, spacing: 12) {
            if let icon {
                icon
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.tint)
                    .padding(.top, 24)
                    .accessibilityHidden(true)
            }

            Text(title)
                .font(.largeTitle)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, icon == nil ? 24 : 0)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                OwlHaptics.tap()
                onAccept()
            } label: {
                Text(acceptLabel)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 16)

            VStack(spacing: 4) {
                Button {
                    OwlHaptics.tap()
                    onLater()
                } label: {
                    Text(laterLabel)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(role: .destructive) {
                    OwlHaptics.tap()
                    onNever()
                } label: {
                    Text(neverLabel)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }
}
#endif
