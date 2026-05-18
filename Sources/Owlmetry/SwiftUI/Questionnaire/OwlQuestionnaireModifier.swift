#if canImport(SwiftUI) && !os(watchOS)
import SwiftUI

/// Internal gate view used by `.owlQuestionnaire(...)`. Evaluates the trigger
/// + isEligible predicate against the persistent `OwlQuestionnaireState`
/// snapshot, calls `Owl.fetchQuestionnaire(slug:)` if eligible, and presents
/// the sheet once the spec is loaded.
///
/// **The sheet is attached to a hidden background subview, not the host's
/// view tree.** SwiftUI doesn't reliably support multiple `.sheet(isPresented:)`
/// modifiers on the same view — if a consumer already has `.sheet(...)` on the
/// view we attach to, our presentation gets swallowed and the screen shows the
/// host view dimmed behind nothing. Putting the sheet on a zero-size hidden
/// `Color.clear` decouples our presentation slot from the consumer's.
///
/// Uses `.sheet(item: $spec)` rather than `.sheet(isPresented: $showing)` so
/// the spec is loaded atomically with the presentation flip — no two-`@State`
/// render race where the sheet briefly opens with `spec == nil`.
private struct OwlQuestionnaireGate: ViewModifier {
    let slug: String
    let trigger: OwlQuestionnaireTrigger
    let showsConsent: Bool
    let isEligible: (() -> Bool)?
    let tint: Color?
    let strings: OwlQuestionnaireStrings
    let onSubmitted: ((OwlQuestionnaireReceipt) -> Void)?
    let onCancel: (() -> Void)?
    let onDismissed: (() -> Void)?

    @State private var spec: OwlQuestionnaire?
    @State private var hasEvaluated = false

    func body(content: Content) -> some View {
        content
            .background(sheetHost)
            .task(id: slug) { await evaluate() }
            #if canImport(UIKit)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                Task { await evaluate(force: true) }
            }
            #endif
    }

    private var sheetHost: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .sheet(item: $spec) { spec in
                NavigationStack {
                    OwlQuestionnaireView(
                        questionnaire: spec,
                        showsConsent: showsConsent,
                        strings: strings,
                        onSubmitted: onSubmitted,
                        onCancel: {
                            onCancel?()
                            self.spec = nil
                        },
                        onDismissed: onDismissed
                    )
                }
                .applyTintIfPresent(tint)
            }
    }

    @MainActor
    private func evaluate(force: Bool = false) async {
        if !force, hasEvaluated { return }
        hasEvaluated = true
        if Owl.questionnaireWasShownThisProcess(slug: slug) { return }
        if trigger.isManual { return }
        let snapshot = OwlQuestionnaireState.shared.snapshot()
        guard trigger.isSatisfied(state: snapshot) else { return }
        if let isEligible, isEligible() == false { return }
        do {
            if let questionnaire = try await Owl.fetchQuestionnaire(slug: slug) {
                Owl.markQuestionnaireShown(slug: slug)
                spec = questionnaire
            }
        } catch {
            // Soft-fail: trigger re-evaluates on next foreground.
        }
    }
}

private extension View {
    @ViewBuilder
    func applyTintIfPresent(_ tint: Color?) -> some View {
        if let tint { self.tint(tint) } else { self }
    }
}

public extension View {
    /// Gate a SwiftUI tree so it auto-presents an Owlmetry questionnaire when
    /// the trigger's conditions hold and the user is eligible per server-side
    /// state (not already-responded, not globally-dismissed). The questionnaire
    /// must already exist on the server with the given slug — create it via
    /// the dashboard, CLI (`owlmetry questionnaires create`), or MCP.
    ///
    /// All `trigger` conditions are ANDed:
    /// ```swift
    /// .owlQuestionnaire(
    ///     slug: "post-onboarding",
    ///     trigger: .when(
    ///         .launches(atLeast: 3),
    ///         .daysSinceFirstLaunch(atLeast: 7)
    ///     ),
    ///     isEligible: { !user.isPaid }
    /// )
    /// ```
    ///
    /// The gate opens at a small "Have a minute for feedback?" detent with
    /// three actions (take the survey, maybe later, don't ask again). It
    /// expands to a full sheet on consent. Set `showsConsent: false` to skip
    /// the consent prompt and go straight to the questionnaire flow.
    ///
    /// The sheet is non-swipe-dismissible — users exit by tapping Cancel,
    /// finishing the flow, or choosing a consent option. The gate attaches to
    /// a hidden background subview, so it's safe to stack other `.sheet(...)`
    /// modifiers on the same view tree.
    ///
    /// Use `OwlQuestionnaireView` directly for fully manual presentation.
    func owlQuestionnaire(
        slug: String,
        trigger: OwlQuestionnaireTrigger = .afterLaunch,
        showsConsent: Bool = true,
        isEligible: (() -> Bool)? = nil,
        tint: Color? = nil,
        strings: OwlQuestionnaireStrings = .default,
        onSubmitted: ((OwlQuestionnaireReceipt) -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
        onDismissed: (() -> Void)? = nil
    ) -> some View {
        modifier(OwlQuestionnaireGate(
            slug: slug,
            trigger: trigger,
            showsConsent: showsConsent,
            isEligible: isEligible,
            tint: tint,
            strings: strings,
            onSubmitted: onSubmitted,
            onCancel: onCancel,
            onDismissed: onDismissed
        ))
    }
}
#endif
