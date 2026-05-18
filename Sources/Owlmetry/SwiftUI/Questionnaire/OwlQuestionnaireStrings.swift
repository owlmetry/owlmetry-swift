import Foundation

/// User-facing strings rendered by `OwlQuestionnaireView`. Same convention as
/// `OwlFeedbackStrings` — every field is a `LocalizedStringResource` so
/// defaults flow through the SDK's bundled string catalog while callers can
/// override individual entries via `.default.with(...)`.
public struct OwlQuestionnaireStrings: Sendable {
    public var title: LocalizedStringResource
    public var loadingTitle: LocalizedStringResource
    public var submitButton: LocalizedStringResource
    public var submittingButton: LocalizedStringResource
    public var skipButton: LocalizedStringResource
    public var doNotShowAgain: LocalizedStringResource
    public var doNotShowAgainConfirmTitle: LocalizedStringResource
    public var doNotShowAgainConfirmMessage: LocalizedStringResource
    public var doNotShowAgainConfirmAction: LocalizedStringResource
    public var doNotShowAgainCancel: LocalizedStringResource
    public var requiredLabel: LocalizedStringResource
    public var successTitle: LocalizedStringResource
    public var successBody: LocalizedStringResource
    public var errorTitle: LocalizedStringResource
    public var errorRequiredMissing: LocalizedStringResource
    public var errorGeneric: LocalizedStringResource
    public var npsLowLabel: LocalizedStringResource
    public var npsHighLabel: LocalizedStringResource

    public init(
        title: LocalizedStringResource = .init("owl.questionnaire.title", defaultValue: "Quick survey", bundle: .atURL(OwlmetryBundle.resources.bundleURL)),
        loadingTitle: LocalizedStringResource = .init("owl.questionnaire.loading", defaultValue: "Loading…", bundle: .atURL(OwlmetryBundle.resources.bundleURL)),
        submitButton: LocalizedStringResource = .init("owl.questionnaire.submit", defaultValue: "Submit", bundle: .atURL(OwlmetryBundle.resources.bundleURL)),
        submittingButton: LocalizedStringResource = .init("owl.questionnaire.submitting", defaultValue: "Sending…", bundle: .atURL(OwlmetryBundle.resources.bundleURL)),
        skipButton: LocalizedStringResource = .init("owl.questionnaire.skip", defaultValue: "Not now", bundle: .atURL(OwlmetryBundle.resources.bundleURL)),
        doNotShowAgain: LocalizedStringResource = .init("owl.questionnaire.dismiss", defaultValue: "Don't show again", bundle: .atURL(OwlmetryBundle.resources.bundleURL)),
        doNotShowAgainConfirmTitle: LocalizedStringResource = .init("owl.questionnaire.dismiss.confirm.title", defaultValue: "Don't show questionnaires?", bundle: .atURL(OwlmetryBundle.resources.bundleURL)),
        doNotShowAgainConfirmMessage: LocalizedStringResource = .init("owl.questionnaire.dismiss.confirm.message", defaultValue: "We won't ask you to fill in another questionnaire.", bundle: .atURL(OwlmetryBundle.resources.bundleURL)),
        doNotShowAgainConfirmAction: LocalizedStringResource = .init("owl.questionnaire.dismiss.confirm.action", defaultValue: "Don't show again", bundle: .atURL(OwlmetryBundle.resources.bundleURL)),
        doNotShowAgainCancel: LocalizedStringResource = .init("owl.questionnaire.dismiss.cancel", defaultValue: "Keep showing", bundle: .atURL(OwlmetryBundle.resources.bundleURL)),
        requiredLabel: LocalizedStringResource = .init("owl.questionnaire.required", defaultValue: "Required", bundle: .atURL(OwlmetryBundle.resources.bundleURL)),
        successTitle: LocalizedStringResource = .init("owl.questionnaire.success.title", defaultValue: "Thanks!", bundle: .atURL(OwlmetryBundle.resources.bundleURL)),
        successBody: LocalizedStringResource = .init("owl.questionnaire.success.body", defaultValue: "Your answers help us improve.", bundle: .atURL(OwlmetryBundle.resources.bundleURL)),
        errorTitle: LocalizedStringResource = .init("owl.questionnaire.error.title", defaultValue: "Couldn't send response", bundle: .atURL(OwlmetryBundle.resources.bundleURL)),
        errorRequiredMissing: LocalizedStringResource = .init("owl.questionnaire.error.required", defaultValue: "Please answer the required questions.", bundle: .atURL(OwlmetryBundle.resources.bundleURL)),
        errorGeneric: LocalizedStringResource = .init("owl.questionnaire.error.generic", defaultValue: "Something went wrong. Please try again.", bundle: .atURL(OwlmetryBundle.resources.bundleURL)),
        npsLowLabel: LocalizedStringResource = .init("owl.questionnaire.nps.low", defaultValue: "Not at all likely", bundle: .atURL(OwlmetryBundle.resources.bundleURL)),
        npsHighLabel: LocalizedStringResource = .init("owl.questionnaire.nps.high", defaultValue: "Extremely likely", bundle: .atURL(OwlmetryBundle.resources.bundleURL))
    ) {
        self.title = title
        self.loadingTitle = loadingTitle
        self.submitButton = submitButton
        self.submittingButton = submittingButton
        self.skipButton = skipButton
        self.doNotShowAgain = doNotShowAgain
        self.doNotShowAgainConfirmTitle = doNotShowAgainConfirmTitle
        self.doNotShowAgainConfirmMessage = doNotShowAgainConfirmMessage
        self.doNotShowAgainConfirmAction = doNotShowAgainConfirmAction
        self.doNotShowAgainCancel = doNotShowAgainCancel
        self.requiredLabel = requiredLabel
        self.successTitle = successTitle
        self.successBody = successBody
        self.errorTitle = errorTitle
        self.errorRequiredMissing = errorRequiredMissing
        self.errorGeneric = errorGeneric
        self.npsLowLabel = npsLowLabel
        self.npsHighLabel = npsHighLabel
    }

    public static let `default` = OwlQuestionnaireStrings()

    public func with(
        title: LocalizedStringResource? = nil,
        submitButton: LocalizedStringResource? = nil,
        skipButton: LocalizedStringResource? = nil,
        doNotShowAgain: LocalizedStringResource? = nil,
        successTitle: LocalizedStringResource? = nil,
        successBody: LocalizedStringResource? = nil,
        errorTitle: LocalizedStringResource? = nil,
        errorRequiredMissing: LocalizedStringResource? = nil,
        errorGeneric: LocalizedStringResource? = nil,
        npsLowLabel: LocalizedStringResource? = nil,
        npsHighLabel: LocalizedStringResource? = nil
    ) -> OwlQuestionnaireStrings {
        var copy = self
        if let title { copy.title = title }
        if let submitButton { copy.submitButton = submitButton }
        if let skipButton { copy.skipButton = skipButton }
        if let doNotShowAgain { copy.doNotShowAgain = doNotShowAgain }
        if let successTitle { copy.successTitle = successTitle }
        if let successBody { copy.successBody = successBody }
        if let errorTitle { copy.errorTitle = errorTitle }
        if let errorRequiredMissing { copy.errorRequiredMissing = errorRequiredMissing }
        if let errorGeneric { copy.errorGeneric = errorGeneric }
        if let npsLowLabel { copy.npsLowLabel = npsLowLabel }
        if let npsHighLabel { copy.npsHighLabel = npsHighLabel }
        return copy
    }
}
