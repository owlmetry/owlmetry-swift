import Foundation

/// Pure value-type collector for the questionnaire flow's per-question
/// answers. Lives separately from the SwiftUI container so the validation +
/// wire-encoding logic is unit-testable without a SwiftUI runtime.
struct OwlQuestionnaireAnswerStore: Equatable {
    var text: [String: String] = [:]
    var single: [String: String] = [:]
    var multi: [String: Set<String>] = [:]
    var rating: [String: Int] = [:]
    var nps: [String: Int] = [:]

    /// Hydrate the store from server-side draft state (the `in_progress`
    /// payload of the eligibility envelope). Unknown question shapes are
    /// silently skipped — pre-fill is best-effort and the server prunes
    /// stale keys when the user completes.
    mutating func prefill(from answers: [String: OwlQuestionnaireAnswerValue]) {
        for (key, value) in answers {
            switch value {
            case .text(let s):       text[key] = s
            case .choice(let s):     single[key] = s
            case .choices(let arr):  multi[key] = Set(arr)
            case .rating(let n):     rating[key] = n
            case .nps(let n):        nps[key] = n
            }
        }
    }

    /// Index of the first question in `schema.questions` whose id is not
    /// answered yet. Returns `schema.questions.count - 1` when every question
    /// is answered (so the flow lands on the last page with the Submit
    /// button live). Returns 0 for an empty store.
    func firstUnansweredIndex(in schema: OwlQuestionnaireSchema) -> Int {
        let questions = schema.questions
        for (i, q) in questions.enumerated() {
            if !isAnswered(q) { return i }
        }
        return max(0, questions.count - 1)
    }

    func isAnswered(_ question: OwlQuestionnaireQuestion) -> Bool {
        switch question {
        case .text(let q):
            let v = text[q.id] ?? ""
            return !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .singleChoice(let q):
            return single[q.id] != nil
        case .multiChoice(let q):
            return !(multi[q.id]?.isEmpty ?? true)
        case .rating(let q):
            return rating[q.id] != nil
        case .nps(let q):
            return nps[q.id] != nil
        }
    }

    func hasAllRequired(_ schema: OwlQuestionnaireSchema) -> Bool {
        for q in schema.questions where q.required {
            if !isAnswered(q) { return false }
        }
        return true
    }

    func collected(_ schema: OwlQuestionnaireSchema) -> [String: OwlQuestionnaireAnswerValue] {
        var out: [String: OwlQuestionnaireAnswerValue] = [:]
        for q in schema.questions {
            switch q {
            case .text(let tq):
                let raw = (text[tq.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !raw.isEmpty { out[tq.id] = .text(raw) }
            case .singleChoice(let sq):
                if let v = single[sq.id] { out[sq.id] = .choice(v) }
            case .multiChoice(let mq):
                if let set = multi[mq.id], !set.isEmpty {
                    out[mq.id] = .choices(Array(set).sorted())
                }
            case .rating(let rq):
                if let v = rating[rq.id] { out[rq.id] = .rating(v) }
            case .nps(let nq):
                if let v = nps[nq.id] { out[nq.id] = .nps(v) }
            }
        }
        return out
    }
}
