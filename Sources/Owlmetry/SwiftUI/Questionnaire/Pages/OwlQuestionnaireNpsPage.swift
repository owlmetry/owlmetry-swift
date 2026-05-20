#if canImport(SwiftUI) && !os(watchOS)
import SwiftUI

struct OwlQuestionnaireNpsPage: View {
    let question: OwlQuestionnaireNpsQuestion
    @Binding var value: Int?
    let lowLabel: LocalizedStringResource
    let highLabel: LocalizedStringResource

    var body: some View {
        // Outer vertical ScrollView so a long title/subtitle scrolls instead
        // of pushing the score row off-screen. Inner horizontal ScrollView
        // around the 0-10 chips stays — they need their own axis since the
        // row is wider than the sheet on small phones.
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                questionHeader(
                    title: question.title,
                    subtitle: question.subtitle
                )

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(0...10, id: \.self) { score in
                            npsButton(for: score)
                        }
                    }
                    .padding(.leading, 24)
                    .padding(.trailing, 16)
                    .padding(.vertical, 4)
                }
                // Negate the page's 24pt horizontal padding so the scroller bleeds
                // to both screen edges. The inner HStack restores 24pt of leading
                // padding so the first chip lines up with the rest of the page
                // content when un-scrolled.
                .padding(.horizontal, -24)

                HStack {
                    Text(lowLabel)
                    Spacer()
                    Text(highLabel)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.bottom, 24)
        }
    }

    private func npsButton(for score: Int) -> some View {
        let isSelected = value == score
        return Button {
            OwlHaptics.tap()
            value = score
        } label: {
            Text("\(score)")
                .font(.callout.weight(.medium))
                .frame(width: 40, height: 40)
                .background(
                    Circle().fill(
                        isSelected
                            ? AnyShapeStyle(.tint)
                            : AnyShapeStyle(Color.secondary.opacity(0.12))
                    )
                )
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(score)"))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
    }
}
#endif
