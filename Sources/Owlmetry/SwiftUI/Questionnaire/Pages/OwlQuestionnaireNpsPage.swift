#if canImport(SwiftUI) && !os(watchOS)
import SwiftUI

struct OwlQuestionnaireNpsPage: View {
    let question: OwlQuestionnaireNpsQuestion
    @Binding var value: Int?
    let lowLabel: LocalizedStringResource
    let highLabel: LocalizedStringResource

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            questionHeader(
                title: question.title,
                subtitle: question.subtitle,
                required: question.required
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0...10, id: \.self) { score in
                        npsButton(for: score)
                    }
                }
                .padding(.vertical, 4)
            }

            HStack {
                Text(lowLabel)
                Spacer()
                Text(highLabel)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.bottom, 24)
    }

    private func npsButton(for score: Int) -> some View {
        let isSelected = value == score
        return Button {
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
