#if canImport(SwiftUI) && !os(watchOS)
import SwiftUI

struct OwlQuestionnaireNpsPage: View {
    let question: OwlQuestionnaireNpsQuestion
    @Binding var value: Int?
    let lowLabel: LocalizedStringResource
    let highLabel: LocalizedStringResource

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                questionHeader(
                    title: question.title,
                    subtitle: question.subtitle
                )

                // Size chips to fit all 11 across the available width. Spacing
                // shrinks before chip size does so the row never overflows on
                // narrow phones, while still hitting a reasonable touch target.
                GeometryReader { geo in
                    let spacing: CGFloat = 4
                    let chipSize = max(28, (geo.size.width - spacing * 10) / 11)
                    HStack(spacing: spacing) {
                        ForEach(0...10, id: \.self) { score in
                            npsButton(for: score, size: chipSize)
                        }
                    }
                    .frame(width: geo.size.width, alignment: .leading)
                }
                .frame(height: 44)

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

    private func npsButton(for score: Int, size: CGFloat) -> some View {
        let isSelected = value == score
        return Button {
            OwlHaptics.tap()
            value = score
        } label: {
            Text("\(score)")
                .font(.callout.weight(.medium))
                .frame(width: size, height: size)
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
