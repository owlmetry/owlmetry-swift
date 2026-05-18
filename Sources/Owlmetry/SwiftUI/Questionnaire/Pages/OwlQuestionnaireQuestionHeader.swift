#if canImport(SwiftUI) && !os(watchOS)
import SwiftUI

/// Shared question-page header: large title + optional subtitle + a small
/// "Required" dot. Rendered above the answer affordance on every page.
@ViewBuilder
func questionHeader(title: String, subtitle: String?, required: Bool) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .fixedSize(horizontal: false, vertical: true)
            if required {
                Text("•")
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
            }
        }
        if let subtitle, !subtitle.isEmpty {
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}
#endif
