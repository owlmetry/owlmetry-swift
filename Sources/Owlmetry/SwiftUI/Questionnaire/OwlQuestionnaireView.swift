#if canImport(SwiftUI) && !os(watchOS)
import SwiftUI

/// SwiftUI view that renders an `OwlQuestionnaire` as a step-through flow
/// (one question per page, with a progress bar) and submits via
/// `Owl.submitQuestionnaireResponse`. The sheet is non-swipe-dismissible by
/// default — consumers exit via the toolbar Cancel button or by finishing
/// the flow.
///
/// Manual presentation:
///
/// ```swift
/// .sheet(isPresented: $show) {
///     NavigationStack {
///         OwlQuestionnaireView(
///             questionnaire: spec,
///             onSubmitted: { _ in show = false },
///             onCancel: { show = false }
///         )
///     }
/// }
/// ```
///
/// Pass `showsConsent: true` to add the small "Have a minute for feedback?"
/// detent up front. For auto-trigger gated on launch / foreground / install-age
/// conditions, use the `.owlQuestionnaire(slug:trigger:...)` modifier instead —
/// it defaults `showsConsent` to `true`.
public struct OwlQuestionnaireView: View {
    private let questionnaire: OwlQuestionnaire
    private let inProgress: OwlQuestionnaireDraft?
    private let showsConsent: Bool
    private let consentIcon: Image?
    private let strings: OwlQuestionnaireStrings
    private let onSubmitted: ((OwlQuestionnaireReceipt) -> Void)?
    private let onCancel: (() -> Void)?
    private let onDismissed: (() -> Void)?

    public init(
        questionnaire: OwlQuestionnaire,
        inProgress: OwlQuestionnaireDraft? = nil,
        showsConsent: Bool = false,
        consentIcon: Image? = Image(systemName: "quote.bubble.fill"),
        strings: OwlQuestionnaireStrings = .default,
        onSubmitted: ((OwlQuestionnaireReceipt) -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
        onDismissed: (() -> Void)? = nil
    ) {
        self.questionnaire = questionnaire
        self.inProgress = inProgress
        self.showsConsent = showsConsent
        self.consentIcon = consentIcon
        self.strings = strings
        self.onSubmitted = onSubmitted
        self.onCancel = onCancel
        self.onDismissed = onDismissed
    }

    public var body: some View {
        OwlQuestionnaireFlowContainer(
            questionnaire: questionnaire,
            inProgress: inProgress,
            showsConsent: showsConsent,
            consentIcon: consentIcon,
            strings: strings,
            onSubmitted: onSubmitted,
            onCancel: onCancel,
            onDismissed: onDismissed
        )
    }
}
#endif
