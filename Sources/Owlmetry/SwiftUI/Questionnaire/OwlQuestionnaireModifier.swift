#if canImport(SwiftUI) && !os(watchOS)
import SwiftUI

/// Internal gate view used by `.owlQuestionnaire(...)`. Evaluates the trigger
/// + isEligible predicate against the persistent `OwlQuestionnaireState`
/// snapshot, calls `Owl.fetchQuestionnaire(slug:)` if eligible, and presents
/// the sheet once the spec is loaded.
private struct OwlQuestionnaireGate: ViewModifier {
    let slug: String
    let trigger: OwlQuestionnaireTrigger
    let isEligible: (() -> Bool)?
    let tint: Color?
    let strings: OwlQuestionnaireStrings
    let onSubmitted: ((OwlQuestionnaireReceipt) -> Void)?
    let onDismissed: (() -> Void)?

    @State private var spec: OwlQuestionnaire?
    @State private var showing = false
    @State private var hasEvaluated = false

    func body(content: Content) -> some View {
        content
            .task(id: slug) { await evaluate() }
            #if canImport(UIKit)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                Task { await evaluate(force: true) }
            }
            #endif
            .sheet(isPresented: $showing) {
                if let spec {
                    NavigationStack {
                        OwlQuestionnaireView(
                            questionnaire: spec,
                            strings: strings,
                            onSubmitted: onSubmitted,
                            onCancel: { showing = false },
                            onDismissed: onDismissed
                        )
                        .navigationTitle(Text(strings.title))
                        #if !os(macOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                    }
                    .applyTintIfPresent(tint)
                }
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
                showing = true
            }
        } catch {
            // Soft-fail: log via the OS logger but don't crash the host view.
            // Transport / server errors at trigger time are not fatal — the
            // SDK will re-evaluate next launch or foreground.
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
    /// Use `OwlQuestionnaireView` directly for fully manual presentation.
    func owlQuestionnaire(
        slug: String,
        trigger: OwlQuestionnaireTrigger = .afterLaunch,
        isEligible: (() -> Bool)? = nil,
        tint: Color? = nil,
        strings: OwlQuestionnaireStrings = .default,
        onSubmitted: ((OwlQuestionnaireReceipt) -> Void)? = nil,
        onDismissed: (() -> Void)? = nil
    ) -> some View {
        modifier(OwlQuestionnaireGate(
            slug: slug,
            trigger: trigger,
            isEligible: isEligible,
            tint: tint,
            strings: strings,
            onSubmitted: onSubmitted,
            onDismissed: onDismissed
        ))
    }
}
#endif
