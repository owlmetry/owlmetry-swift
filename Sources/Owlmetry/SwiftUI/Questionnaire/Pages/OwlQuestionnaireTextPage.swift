#if canImport(SwiftUI) && !os(watchOS)
import SwiftUI

struct OwlQuestionnaireTextPage: View {
    let question: OwlQuestionnaireTextQuestion
    @Binding var value: String
    // Container-owned focus so the keyboard tracks the current question across
    // TabView page swaps. TabView(.page) keeps neighbouring pages alive, so a
    // page-local @FocusState would stay `true` after the user moved off this
    // page and the keyboard would never dismiss.
    var focused: FocusState<String?>.Binding

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                questionHeader(
                    title: question.title,
                    subtitle: question.subtitle
                )

                if question.multiline {
                    // Hide TextEditor's built-in white background so the outer
                    // rounded fill is the only visible surface — matches the
                    // single-line TextField branch below.
                    TextEditor(text: $value)
                        .focused(focused, equals: question.id)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 160)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08)))
                        .accessibilityLabel(Text(question.title))
                } else {
                    let field = TextField(question.placeholder ?? "", text: $value)
                        .focused(focused, equals: question.id)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08)))
                        .accessibilityLabel(Text(question.title))
                    #if os(iOS) || os(tvOS) || os(visionOS)
                    field.textInputAutocapitalization(.sentences)
                    #else
                    field
                    #endif
                }
            }
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}
#endif
