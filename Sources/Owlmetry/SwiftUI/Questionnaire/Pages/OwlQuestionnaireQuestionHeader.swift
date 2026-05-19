#if canImport(SwiftUI) && !os(watchOS)
import SwiftUI

/// Shared question-page header: large title + optional subtitle. Required-ness
/// is communicated by the disabled Next button, not a visual marker on the
/// title — keeps the title clean.
@ViewBuilder
func questionHeader(title: String, subtitle: String?) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(title)
            .font(.title3)
            .fontWeight(.semibold)
            .fixedSize(horizontal: false, vertical: true)
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
