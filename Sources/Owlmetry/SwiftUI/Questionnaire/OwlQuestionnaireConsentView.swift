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
                .padding(.top, icon == nil ? 24 : 0)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 16)

            Button(action: onAccept) {
                Text(acceptLabel)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)

            VStack(spacing: 4) {
                Button(action: onLater) {
                    Text(laterLabel)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(role: .destructive, action: onNever) {
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
