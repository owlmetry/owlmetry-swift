#if canImport(SwiftUI) && !os(watchOS)
import SwiftUI

/// Small-detent content rendered for `OwlQuestionnairePhase.consent`.
/// Three vertically-stacked buttons: accept (filled), later (plain),
/// never (plain destructive). Sized to fit `.height(380)` on iPhone SE.
struct OwlQuestionnaireConsentView: View {
    let title: LocalizedStringResource
    let message: String
    let acceptLabel: LocalizedStringResource
    let laterLabel: LocalizedStringResource
    let neverLabel: LocalizedStringResource
    let onAccept: () -> Void
    let onLater: () -> Void
    let onNever: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 8)

            VStack(spacing: 10) {
                Button(action: onAccept) {
                    Text(acceptLabel)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)

                Button(action: onLater) {
                    Text(laterLabel)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)

                Button(role: .destructive, action: onNever) {
                    Text(neverLabel)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }
}
#endif
