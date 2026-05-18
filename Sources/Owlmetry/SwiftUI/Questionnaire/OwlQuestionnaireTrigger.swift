import Foundation

/// A single condition that must hold for an auto-triggered questionnaire to
/// present. Conditions read from the persistent `OwlQuestionnaireState`
/// (launch / foreground counts) and a wall-clock `now`.
public enum OwlQuestionnaireCondition: Sendable, Equatable {
    /// Number of times `Owl.configure(...)` has completed (one bump per process).
    case launches(atLeast: Int)
    /// Number of foreground transitions since install.
    case foregrounds(atLeast: Int)
    /// Days since the very first `Owl.configure(...)` call.
    case daysSinceFirstLaunch(atLeast: Int)
    /// Hours since the very first `Owl.configure(...)` call.
    case hoursSinceFirstLaunch(atLeast: Int)

    /// Pure evaluator used by the view modifier and unit tests.
    public func isSatisfied(state: OwlQuestionnaireState.Snapshot) -> Bool {
        switch self {
        case .launches(let n):
            return state.launchCount >= n
        case .foregrounds(let n):
            return state.foregroundCount >= n
        case .daysSinceFirstLaunch(let d):
            return state.daysSinceFirstLaunch() >= Double(d)
        case .hoursSinceFirstLaunch(let h):
            return state.hoursSinceFirstLaunch() >= Double(h)
        }
    }
}

/// A composable trigger for the `.owlQuestionnaire(...)` view modifier. All
/// conditions are ANDed — if you want OR logic, use the `isEligible` closure
/// or split into two modifier applications. `.manual` opts out of auto-trigger
/// entirely.
public struct OwlQuestionnaireTrigger: Sendable, Equatable {
    public let conditions: [OwlQuestionnaireCondition]
    public let isManual: Bool

    /// Never auto-trigger. The consumer drives presentation directly via
    /// `OwlQuestionnaireView` or by binding to a `@State` flag.
    public static let manual = OwlQuestionnaireTrigger(conditions: [], isManual: true)

    /// Shortcut for `.launches(atLeast: 1)` — fire on first launch.
    public static let afterLaunch = OwlQuestionnaireTrigger(
        conditions: [.launches(atLeast: 1)],
        isManual: false
    )

    /// Shortcut for `.launches(atLeast: n)`.
    public static func afterLaunches(_ n: Int) -> OwlQuestionnaireTrigger {
        OwlQuestionnaireTrigger(conditions: [.launches(atLeast: n)], isManual: false)
    }

    /// Composable form — ALL conditions must evaluate true (ANDed). An empty
    /// argument list means "always", which combined with `isEligible` is the
    /// hook for fully custom gating.
    public static func when(_ conditions: OwlQuestionnaireCondition...) -> OwlQuestionnaireTrigger {
        OwlQuestionnaireTrigger(conditions: conditions, isManual: false)
    }

    /// Evaluate against a state snapshot. Returns true only when every
    /// condition is satisfied; `.manual` always returns false (handled
    /// separately by the modifier).
    public func isSatisfied(state: OwlQuestionnaireState.Snapshot) -> Bool {
        if isManual { return false }
        for c in conditions {
            if !c.isSatisfied(state: state) { return false }
        }
        return true
    }
}
