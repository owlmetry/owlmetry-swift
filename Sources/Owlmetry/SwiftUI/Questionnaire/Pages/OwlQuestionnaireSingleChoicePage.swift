#if canImport(SwiftUI) && !os(watchOS)
import SwiftUI

struct OwlQuestionnaireSingleChoicePage: View {
    let question: OwlQuestionnaireSingleChoiceQuestion
    @Binding var value: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                questionHeader(
                    title: question.title,
                    subtitle: question.subtitle
                )

                VStack(spacing: 10) {
                    ForEach(question.options) { option in
                        choiceRow(option: option)
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }

    private func choiceRow(option: OwlQuestionnaireChoiceOption) -> some View {
        let isSelected = value == option.id
        return Button {
            OwlHaptics.tap()
            value = option.id
        } label: {
            HStack {
                Text(option.label)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .font(.title3)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
    }
}
#endif
