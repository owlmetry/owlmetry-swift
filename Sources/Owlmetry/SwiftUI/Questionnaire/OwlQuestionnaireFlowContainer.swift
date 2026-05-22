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
    let inProgress: OwlQuestionnaireDraft?
    let showsConsent: Bool
    let consentIcon: Image?
    let strings: OwlQuestionnaireStrings
    let onSubmitted: ((OwlQuestionnaireReceipt) -> Void)?
    let onCancel: (() -> Void)?
    let onDismissed: (() -> Void)?

    /// Initial height of the small consent detent. The actual detent is
    /// driven by `measuredConsentDetentHeight` once the content's intrinsic
    /// size has been measured — see `ConsentContentHeightPreferenceKey`.
    /// This initial value covers the common case (icon + 1-2 line title +
    /// 1-2 line body + 3 buttons) so the sheet rarely needs to grow on first
    /// render. Floor is `minConsentDetentHeight` so the sheet never collapses
    /// awkwardly on a missed measurement.
    static let initialConsentDetentHeight: CGFloat = 380
    static let minConsentDetentHeight: CGFloat = 320
    /// Hard ceiling for the dynamic detent. Above this, `.large` is the
    /// better experience (full-sheet) so we don't render a near-fullscreen
    /// "small" detent.
    static let maxConsentDetentHeight: CGFloat = 720

    @Environment(\.dismiss) private var dismiss

    @State private var phase: OwlQuestionnairePhase
    @State private var detent: PresentationDetent
    /// Tracks the consent view's intrinsic content height so the detent can
    /// grow to fit longer titles/descriptions (or shrink for shorter ones).
    /// Updated via `ConsentContentHeightPreferenceKey` from a GeometryReader
    /// background on the consent view.
    @State private var measuredConsentDetentHeight: CGFloat = OwlQuestionnaireFlowContainer.initialConsentDetentHeight

    // Answer state — backed by a unit-testable value-type store. Pre-filled
    // from `inProgress.answers` on init when resuming an existing draft.
    @State private var answers: OwlQuestionnaireAnswerStore

    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showDismissConfirm = false

    // Keyboard focus follows the *current* question, not page lifecycle —
    // TabView(.page) keeps neighbouring pages alive so a page-local
    // @FocusState would leave the keyboard up after the user advanced off a
    // text question. nil = no field focused / keyboard dismissed.
    @FocusState private var focusedTextQuestionId: String?

    init(
        questionnaire: OwlQuestionnaire,
        inProgress: OwlQuestionnaireDraft? = nil,
        showsConsent: Bool,
        consentIcon: Image?,
        strings: OwlQuestionnaireStrings,
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

        // Hydrate the answer store from any server-side draft before SwiftUI
        // creates page bindings, so the first render already has the saved
        // values visible.
        var hydrated = OwlQuestionnaireAnswerStore()
        if let inProgress {
            hydrated.prefill(from: inProgress.answers)
        }
        _answers = State(initialValue: hydrated)

        // Resume on top of an existing draft skips consent (the user already
        // opted in earlier) and lands on the first unanswered question. A
        // fresh-flow init still shows consent when the caller asked for it.
        let resuming = inProgress != nil
        let startIndex = resuming
            ? hydrated.firstUnansweredIndex(in: questionnaire.schema)
            : 0
        let showConsentNow = showsConsent && !resuming
        _phase = State(initialValue: showConsentNow ? .consent : .running(index: startIndex))
        _detent = State(initialValue: showConsentNow ? .height(Self.initialConsentDetentHeight) : .large)
    }

    var body: some View {
        rootContent
            .presentationDetents(detentOptions, selection: $detent)
            .interactiveDismissDisabled(true)
            .presentationDragIndicator(.hidden)
            .onPreferenceChange(ConsentContentHeightPreferenceKey.self) { measured in
                applyMeasuredConsentHeight(measured)
            }
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
            return [.height(measuredConsentDetentHeight), .large]
        }
        return [.large]
    }

    /// Clamp the measured consent content height and propagate it to the
    /// detent. Skips no-op updates (sub-pixel drift) to avoid render loops.
    /// Falls back to `.large` when content exceeds the ceiling — at that
    /// point a small detent stops being "small" and the full sheet is the
    /// better UX.
    private func applyMeasuredConsentHeight(_ measured: CGFloat) {
        guard measured > 1 else { return }
        // Pad the measured intrinsic height so the sheet has a touch of
        // breathing room under the last button instead of clipping to its
        // baseline.
        let padded = ceil(measured) + 16
        let clamped = min(max(padded, Self.minConsentDetentHeight), Self.maxConsentDetentHeight)
        guard abs(clamped - measuredConsentDetentHeight) > 0.5 else { return }
        measuredConsentDetentHeight = clamped
        guard case .consent = phase else { return }
        // Above the ceiling, switch the active detent to .large — the small
        // detent would now obscure the buttons or feel oppressive.
        if padded > Self.maxConsentDetentHeight {
            detent = .large
        } else {
            detent = .height(clamped)
        }
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
            // Measure the consent view's intrinsic height so the small detent
            // resizes to fit longer titles/descriptions. The view itself hugs
            // its content (no greedy Spacer), so the GeometryReader's reported
            // size matches the natural layout height.
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(
                            key: ConsentContentHeightPreferenceKey.self,
                            value: proxy.size.height
                        )
                }
            )
            .onAppear {
                Owl.info("sdk:questionnaire_consent_shown", attributes: [
                    "_slug": questionnaire.slug,
                ])
            }
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

            // Single-page renderer. Navigation is button-driven only — the
            // earlier TabView(.page) variant let users swipe forward past a
            // half-answered required question, which the Next button is
            // supposed to gate. `.id(current)` triggers the crossfade.
            pageView(for: question)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .id(current)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: current)

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
        // Seed focus for the question we land on (covers fresh starts and the
        // resume-mid-draft path that jumps to firstUnansweredIndex). Subsequent
        // navigation is handled by the onChange below.
        .onAppear { syncFocus(to: current) }
        // One-parameter form for iOS 16 / macOS 13 floor — the two-parameter
        // closure is iOS 17+. Deprecation warning on newer OSes is acceptable.
        .onChange(of: phase) { newPhase in
            if case .running(let idx) = newPhase {
                syncFocus(to: idx)
            } else {
                focusedTextQuestionId = nil
            }
        }
    }

    /// Sets the keyboard focus to match `index`'s question — its id if it's a
    /// text question, otherwise nil. Single source of truth for "which page is
    /// allowed to own the keyboard right now".
    private func syncFocus(to index: Int) {
        let questions = questionnaire.schema.questions
        guard !questions.isEmpty else { return }
        let clamped = max(0, min(index, questions.count - 1))
        if case .text(let q) = questions[clamped] {
            focusedTextQuestionId = q.id
        } else {
            focusedTextQuestionId = nil
        }
    }

    @ViewBuilder
    private func pageView(for question: OwlQuestionnaireQuestion) -> some View {
        switch question {
        case .text(let q):
            OwlQuestionnaireTextPage(
                question: q,
                value: bindingForText(q.id),
                focused: $focusedTextQuestionId
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
                // Override the inherited accent tint — Back is a low-priority
                // exit, shouldn't visually compete with Next/Submit.
                .tint(.gray)
                .disabled(isSubmitting)
            }

            Button {
                OwlHaptics.tap()
                if isLast {
                    Task { await submit() }
                } else {
                    // Persist the current answer set as a draft before
                    // advancing. The server upserts by (project, slug, user)
                    // so we don't track the response id locally. Fire-and-
                    // forget — the UI advances immediately while the network
                    // call resolves in the background. The final submit
                    // sends the full accumulated answer set anyway, so a
                    // dropped draft save is recovered on completion.
                    Task { await saveDraftInBackground() }
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
        Owl.info("sdk:questionnaire_started", attributes: [
            "_slug": questionnaire.slug,
        ])
        withAnimation(.easeInOut(duration: 0.3)) {
            phase = .running(index: 0)
            detent = .large
        }
    }

    private func declineLater() {
        Owl.debug("sdk:questionnaire_consent_dismissed", attributes: [
            "_slug": questionnaire.slug,
            "_reason": "later",
        ])
        focusedTextQuestionId = nil
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
        focusedTextQuestionId = nil
        onCancel?()
        dismiss()
    }

    private func finishSuccess(receipt: OwlQuestionnaireReceipt) {
        focusedTextQuestionId = nil
        onSubmitted?(receipt)
        dismiss()
    }

    // MARK: - Submit / dismiss

    /// Final-submit path. Awaits the server, only transitions to .success
    /// when the response actually flipped to submitted on the server (i.e.,
    /// `wasSubmitted == true`). On a non-flip result (would only happen if
    /// the row was already submitted by a sibling device) we still transition
    /// to .success so the user sees the success screen; their answer set
    /// merged into the existing row.
    @MainActor
    private func submit() async {
        guard hasAllRequired else {
            errorMessage = String(localized: strings.errorRequiredMissing)
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let receipt = try await Owl.saveQuestionnaireResponse(
                slug: questionnaire.slug,
                answers: collectAnswers(),
                isComplete: true
            )
            Owl.info("sdk:questionnaire_submitted", attributes: [
                "_slug": questionnaire.slug,
            ])
            withAnimation(.easeInOut(duration: 0.3)) {
                phase = .success(receipt)
            }
        } catch let err as OwlQuestionnaireError {
            errorMessage = err.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Persist the current answer set as a draft. Called from each non-final
    /// Next tap. Errors are swallowed (logged via the SDK) — partial saves
    /// are best-effort and the eventual final submit retries the full set.
    @MainActor
    private func saveDraftInBackground() async {
        let payload = collectAnswers()
        // Skip empty saves — happens when the user advances past a question
        // they haven't answered yet (optional fields). Sending an empty
        // payload would just hit the server for no reason.
        guard !payload.isEmpty else { return }
        do {
            _ = try await Owl.saveQuestionnaireResponse(
                slug: questionnaire.slug,
                answers: payload,
                isComplete: false
            )
        } catch {
            // Soft-fail: final submit will resend the accumulated answers.
        }
    }

    @MainActor
    private func dismissGlobally() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            _ = try await Owl.dismissQuestionnaires()
            Owl.debug("sdk:questionnaire_consent_dismissed", attributes: [
                "_slug": questionnaire.slug,
                "_reason": "never",
            ])
            focusedTextQuestionId = nil
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

/// Carries the consent view's measured intrinsic height up to the container
/// so the small sheet detent can resize to fit the content. `reduce` takes
/// the max so a stale 0 from a sibling layer never overrides a real
/// measurement.
private struct ConsentContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
#endif
