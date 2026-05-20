#if canImport(SwiftUI) && !os(watchOS)
import SwiftUI

struct OwlQuestionnaireRatingPage: View {
    let question: OwlQuestionnaireRatingQuestion
    @Binding var value: Int?

    var body: some View {
        // ScrollView so a long title/subtitle (a real concern — copy is
        // server-driven and may be paragraph-length) scrolls instead of
        // pushing the stars off-screen. The header already uses
        // `.fixedSize(horizontal: false, vertical: true)` so it always
        // renders at full natural height.
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                questionHeader(
                    title: question.title,
                    subtitle: question.subtitle
                )

                HStack(spacing: 8) {
                    ForEach(1...question.scale, id: \.self) { star in
                        starButton(for: star)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.bottom, 24)
        }
    }

    private func starButton(for star: Int) -> some View {
        let filled = (value ?? 0) >= star
        return Button {
            OwlHaptics.tap()
            value = star
        } label: {
            Image(systemName: filled ? "star.fill" : "star")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .foregroundStyle(filled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .padding(8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(star)"))
        .accessibilityAddTraits([.isButton])
    }
}
#endif
