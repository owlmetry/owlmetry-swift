#if canImport(SwiftUI) && !os(watchOS)
import SwiftUI

/// Phase of the questionnaire flow. The container starts in `.consent` when
/// the consumer asks for it, otherwise jumps straight to `.running(index: 0)`.
/// Internal — not part of the SDK's public surface.
enum OwlQuestionnairePhase: Equatable {
    case consent
    case running(index: Int)
    case success(OwlQuestionnaireReceipt)
}

/// Internal host that owns the questionnaire flow: phase machine, answer
/// state, sheet-detent state. Used by both the public `OwlQuestionnaireView`
/// (manual presentation) and the auto-trigger `.owlQuestionnaire(...)` view
/// modifier — they pass `showsConsent` differently but share this container.
///
/// **Why the container owns the detent:** `.presentationDetents(...)`,
/// `.interactiveDismissDisabled(true)`, and `.presentationDragIndicator(.hidden)`
/// only take effect when applied **inside** the sheet's content view, so the
/// container is the one place that can wire them. A `@State` selection binding
/// here drives the smooth small→large animation when consent is accepted.
struct OwlQuestionnaireFlowContainer: View {
    let questionnaire: OwlQuestionnaire
    let showsConsent: Bool
    let consentIcon: Image?
    let strings: OwlQuestionnaireStrings
    let onSubmitted: ((OwlQuestionnaireReceipt) -> Void)?
    let onCancel: (() -> Void)?
    let onDismissed: (() -> Void)?

    /// Height of the small consent detent. Sized to fit the title + body + 3
    /// stacked buttons + padding on iPhone SE without scrolling.
    static let consentDetentHeight: CGFloat = 380

    @Environment(\.dismiss) private var dismiss

    @State private var phase: OwlQuestionnairePhase
    @State private var detent: PresentationDetent

    // Answer state — backed by a unit-testable value-type store.
    @State private var answers = OwlQuestionnaireAnswerStore()

    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showDismissConfirm = false

    init(
        questionnaire: OwlQuestionnaire,
        showsConsent: Bool,
        consentIcon: Image?,
        strings: OwlQuestionnaireStrings,
        onSubmitted: ((OwlQuestionnaireReceipt) -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
        onDismissed: (() -> Void)? = nil
    ) {
        self.questionnaire = questionnaire
        self.showsConsent = showsConsent
        self.consentIcon = consentIcon
        self.strings = strings
        self.onSubmitted = onSubmitted
        self.onCancel = onCancel
        self.onDismissed = onDismissed
        _phase = State(initialValue: showsConsent ? .consent : .running(index: 0))
        _detent = State(initialValue: showsConsent ? .height(Self.consentDetentHeight) : .large)
    }

    var body: some View {
        rootContent
            .presentationDetents(detentOptions, selection: $detent)
            .interactiveDismissDisabled(true)
            .presentationDragIndicator(.hidden)
            .alert(Text(strings.errorTitle), isPresented: errorAlertBinding, actions: {
                Button(role: .cancel) { errorMessage = nil } label: { Text("OK") }
            }, message: {
                if let errorMessage { Text(errorMessage) } else { EmptyView() }
            })
            .confirmationDialog(
                Text(strings.doNotShowAgainConfirmTitle),
                isPresented: $showDismissConfirm,
                titleVisibility: .visible
            ) {
                Button(role: .destructive) {
                    OwlHaptics.tap()
                    Task { await dismissGlobally() }
                } label: { Text(strings.doNotShowAgainConfirmAction) }
                Button(role: .cancel) { OwlHaptics.tap() } label: { Text(strings.doNotShowAgainCancel) }
            } message: {
                Text(strings.doNotShowAgainConfirmMessage)
            }
    }

    private var detentOptions: Set<PresentationDetent> {
        // Only offer the small detent during the consent phase. Once the user
        // accepts (or we open directly into questions), lock to .large so the
        // sheet can't be swiped back down to the consent height.
        if case .consent = phase {
            return [.height(Self.consentDetentHeight), .large]
        }
        return [.large]
    }

    @ViewBuilder
    private var rootContent: some View {
        switch phase {
        case .consent:
            OwlQuestionnaireConsentView(
                icon: consentIcon,
                title: strings.consentTitle,
                message: consentBodyText,
                acceptLabel: strings.consentAccept,
                laterLabel: strings.consentLater,
                neverLabel: strings.consentNever,
                onAccept: acceptConsent,
                onLater: declineLater,
                onNever: { showDismissConfirm = true }
            )
            #if !os(macOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
        case .running(let index):
            runningView(index: index)
        case .success(let receipt):
            OwlQuestionnaireSuccessView(
                title: strings.successTitle,
                message: strings.successBody,
                doneLabel: strings.doneButton,
                onDone: { finishSuccess(receipt: receipt) }
            )
            #if !os(macOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
        }
    }

    @ViewBuilder
    private func runningView(index: Int) -> some View {
        let questions = questionnaire.schema.questions
        let total = questions.count
        let current = max(0, min(index, total - 1))
        let question = questions[current]

        VStack(spacing: 0) {
            OwlQuestionnaireProgressBar(current: current, total: total)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)

            // Pages — TabView gives a smooth horizontal swipe between questions
            // while still letting our buttons drive the actual selection.
            TabView(selection: bindingFor(current: current)) {
                ForEach(Array(questions.enumerated()), id: \.offset) { i, q in
                    pageView(for: q)
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .tag(i)
                }
            }
            #if !os(macOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif
            .animation(.easeInOut(duration: 0.25), value: current)

            buttonBar(index: current, total: total, question: question)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .padding(.top, 8)
        }
        .navigationTitle(Text(strings.title))
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    OwlHaptics.tap()
                    cancelMidFlow()
                } label: {
                    Text(strings.cancelButton)
                }
                .disabled(isSubmitting)
            }
        }
    }

    private func bindingFor(current: Int) -> Binding<Int> {
        Binding(
            get: { current },
            set: { newValue in
                guard newValue != current else { return }
                phase = .running(index: newValue)
            }
        )
    }

    @ViewBuilder
    private func pageView(for question: OwlQuestionnaireQuestion) -> some View {
        switch question {
        case .text(let q):
            OwlQuestionnaireTextPage(
                question: q,
                value: bindingForText(q.id)
            )
        case .singleChoice(let q):
            OwlQuestionnaireSingleChoicePage(
                question: q,
                value: bindingForSingle(q.id)
            )
        case .multiChoice(let q):
            OwlQuestionnaireMultiChoicePage(
                question: q,
                value: bindingForMulti(q.id)
            )
        case .rating(let q):
            OwlQuestionnaireRatingPage(
                question: q,
                value: bindingForRating(q.id)
            )
        case .nps(let q):
            OwlQuestionnaireNpsPage(
                question: q,
                value: bindingForNps(q.id),
                lowLabel: strings.npsLowLabel,
                highLabel: strings.npsHighLabel
            )
        }
    }

    @ViewBuilder
    private func buttonBar(index: Int, total: Int, question: OwlQuestionnaireQuestion) -> some View {
        let isLast = index == total - 1
        let canAdvance = !question.required || isAnswered(question)

        HStack(spacing: 12) {
            if index > 0 {
                Button {
                    OwlHaptics.tap()
                    goBack(from: index)
                } label: {
                    Text(strings.backButton)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.bordered)
                .disabled(isSubmitting)
            }

            Button {
                OwlHaptics.tap()
                if isLast {
                    Task { await submit() }
                } else {
                    goNext(from: index)
                }
            } label: {
                Group {
                    if isLast && isSubmitting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(isLast ? strings.submitButton : strings.nextButton)
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canAdvance || isSubmitting)
        }
    }

    // MARK: - Phase transitions

    private func acceptConsent() {
        withAnimation(.easeInOut(duration: 0.3)) {
            phase = .running(index: 0)
            detent = .large
        }
    }

    private func declineLater() {
        onCancel?()
        dismiss()
    }

    private func goNext(from index: Int) {
        let total = questionnaire.schema.questions.count
        let next = min(index + 1, total - 1)
        guard next != index else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            phase = .running(index: next)
        }
    }

    private func goBack(from index: Int) {
        guard index > 0 else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            phase = .running(index: index - 1)
        }
    }

    private func cancelMidFlow() {
        onCancel?()
        dismiss()
    }

    private func finishSuccess(receipt: OwlQuestionnaireReceipt) {
        onSubmitted?(receipt)
        dismiss()
    }

    // MARK: - Submit / dismiss

    @MainActor
    private func submit() async {
        guard hasAllRequired else {
            errorMessage = String(localized: strings.errorRequiredMissing)
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let receipt = try await Owl.submitQuestionnaireResponse(
                slug: questionnaire.slug,
                answers: collectAnswers()
            )
            withAnimation(.easeInOut(duration: 0.3)) {
                phase = .success(receipt)
            }
        } catch let err as OwlQuestionnaireError {
            errorMessage = err.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func dismissGlobally() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            _ = try await Owl.dismissQuestionnaires()
            onDismissed?()
            dismiss()
        } catch let err as OwlQuestionnaireError {
            errorMessage = err.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Bindings + state

    private var consentBodyText: String {
        if let description = questionnaire.description, !description.isEmpty {
            return description
        }
        return String(localized: strings.consentBody)
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func bindingForText(_ id: String) -> Binding<String> {
        Binding(get: { answers.text[id] ?? "" }, set: { answers.text[id] = $0 })
    }

    private func bindingForSingle(_ id: String) -> Binding<String?> {
        Binding(get: { answers.single[id] }, set: { answers.single[id] = $0 })
    }

    private func bindingForMulti(_ id: String) -> Binding<Set<String>> {
        Binding(get: { answers.multi[id] ?? [] }, set: { answers.multi[id] = $0 })
    }

    private func bindingForRating(_ id: String) -> Binding<Int?> {
        Binding(get: { answers.rating[id] }, set: { answers.rating[id] = $0 })
    }

    private func bindingForNps(_ id: String) -> Binding<Int?> {
        Binding(get: { answers.nps[id] }, set: { answers.nps[id] = $0 })
    }

    private func isAnswered(_ question: OwlQuestionnaireQuestion) -> Bool {
        answers.isAnswered(question)
    }

    private var hasAllRequired: Bool {
        answers.hasAllRequired(questionnaire.schema)
    }

    private func collectAnswers() -> [String: OwlQuestionnaireAnswerValue] {
        answers.collected(questionnaire.schema)
    }
}
#endif
