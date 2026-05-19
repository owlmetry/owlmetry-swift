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
    let consentIcon: Image?
    let isEligible: (() -> Bool)?
    let forceShow: Bool
    let tint: Color?
    let strings: OwlQuestionnaireStrings
    let onSubmitted: ((OwlQuestionnaireReceipt) -> Void)?
    let onCancel: (() -> Void)?
    let onDismissed: (() -> Void)?

    /// Identifiable container so `.sheet(item:)` carries both the
    /// questionnaire and any in-progress draft for resume. Identified by
    /// the questionnaire id (stable across the gate's lifetime).
    private struct PresentationPayload: Identifiable {
        let questionnaire: OwlQuestionnaire
        let inProgress: OwlQuestionnaireDraft?
        var id: String { questionnaire.id }
    }

    @State private var payload: PresentationPayload?
    @State private var hasEvaluated = false

    func body(content: Content) -> some View {
        content
            .background(sheetHost)
            // Task id folds in forceShow so toggling the debug flag at runtime
            // (e.g., from a debug menu) re-fires evaluation instead of waiting
            // for a slug change or foreground transition.
            .task(id: "\(slug)|\(forceShow)") { await evaluate() }
            #if canImport(UIKit)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                Task { await evaluate(force: true) }
            }
            #endif
    }

    private var sheetHost: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .sheet(item: $payload) { payload in
                NavigationStack {
                    OwlQuestionnaireView(
                        questionnaire: payload.questionnaire,
                        inProgress: payload.inProgress,
                        // Resume on top of an existing draft means the user
                        // already opted in earlier — replaying the consent
                        // detent would feel rude. Skip it on resume.
                        showsConsent: showsConsent && payload.inProgress == nil,
                        consentIcon: consentIcon,
                        strings: strings,
                        onSubmitted: onSubmitted,
                        onCancel: {
                            onCancel?()
                            self.payload = nil
                        },
                        onDismissed: onDismissed
                    )
                }
                .applyTintIfPresent(tint)
            }
    }

    @MainActor
    private func evaluate(force: Bool = false) async {
        // forceShow bypasses every local gate (per-process dedup, manual
        // trigger, condition checks, isEligible closure) and asks the server
        // to ignore already-responded / globally-dismissed too. Intended for
        // previewing the UI in debug builds — wrap it in `#if DEBUG` or wire
        // it to a debug-menu toggle in your app.
        if !forceShow {
            if !force, hasEvaluated { return }
        }
        hasEvaluated = true
        if !forceShow {
            if Owl.questionnaireWasShownThisProcess(slug: slug) { return }
            if trigger.isManual { return }
            let snapshot = OwlQuestionnaireState.shared.snapshot()
            guard trigger.isSatisfied(state: snapshot) else { return }
            if let isEligible, isEligible() == false { return }
        }
        do {
            let result = try await Owl.fetchQuestionnaire(slug: slug, force: forceShow)
            if let questionnaire = result.questionnaire {
                // Skip the per-process "shown" mark under forceShow so the
                // debug toggle stays re-presentable across dismiss cycles.
                if !forceShow {
                    Owl.markQuestionnaireShown(slug: slug)
                }
                payload = PresentationPayload(
                    questionnaire: questionnaire,
                    inProgress: result.inProgress
                )
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
    ///
    /// Set `forceShow: true` to bypass every local gate (trigger conditions,
    /// `isEligible`, per-process dedup) and ask the server to also ignore
    /// `alreadyResponded` and `globallyDismissed`. `inactive` is still
    /// respected. Intended for previewing the questionnaire UI in debug
    /// builds — gate it yourself with `#if DEBUG` or a debug-menu toggle so
    /// production users never trip it.
    func owlQuestionnaire(
        slug: String,
        trigger: OwlQuestionnaireTrigger = .afterLaunch,
        showsConsent: Bool = true,
        consentIcon: Image? = Image(systemName: "quote.bubble.fill"),
        isEligible: (() -> Bool)? = nil,
        forceShow: Bool = false,
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
            consentIcon: consentIcon,
            isEligible: isEligible,
            forceShow: forceShow,
            tint: tint,
            strings: strings,
            onSubmitted: onSubmitted,
            onCancel: onCancel,
            onDismissed: onDismissed
        ))
    }
}
#endif
