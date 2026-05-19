import XCTest
@testable import Owlmetry

final class OwlQuestionnaireFlowTests: XCTestCase {

    // MARK: - Phase equality

    func testPhaseEquality() {
        let receipt = OwlQuestionnaireReceipt(id: "r1", createdAt: Date(timeIntervalSince1970: 0), wasSubmitted: true)
        XCTAssertEqual(OwlQuestionnairePhase.consent, .consent)
        XCTAssertEqual(OwlQuestionnairePhase.running(index: 2), .running(index: 2))
        XCTAssertNotEqual(OwlQuestionnairePhase.running(index: 0), .running(index: 1))
        XCTAssertEqual(OwlQuestionnairePhase.success(receipt), .success(receipt))
        XCTAssertNotEqual(OwlQuestionnairePhase.consent, .running(index: 0))
    }

    // MARK: - Answer store

    private func schemaWithEveryType() -> OwlQuestionnaireSchema {
        OwlQuestionnaireSchema(version: 1, questions: [
            .text(OwlQuestionnaireTextQuestion(
                id: "t1", title: "What's on your mind?", subtitle: nil,
                required: true, placeholder: nil, multiline: true
            )),
            .singleChoice(OwlQuestionnaireSingleChoiceQuestion(
                id: "s1", title: "Pick one", subtitle: nil, required: true,
                options: [
                    OwlQuestionnaireChoiceOption(id: "a", label: "A"),
                    OwlQuestionnaireChoiceOption(id: "b", label: "B"),
                ]
            )),
            .multiChoice(OwlQuestionnaireMultiChoiceQuestion(
                id: "m1", title: "Pick any", subtitle: nil, required: false,
                options: [
                    OwlQuestionnaireChoiceOption(id: "x", label: "X"),
                    OwlQuestionnaireChoiceOption(id: "y", label: "Y"),
                ]
            )),
            .rating(OwlQuestionnaireRatingQuestion(
                id: "r1", title: "Rate it", subtitle: nil, required: true, scale: 5
            )),
            .nps(OwlQuestionnaireNpsQuestion(
                id: "n1", title: "How likely", subtitle: nil, required: false
            )),
        ])
    }

    func testEmptyStoreNothingAnswered() {
        let store = OwlQuestionnaireAnswerStore()
        for q in schemaWithEveryType().questions {
            XCTAssertFalse(store.isAnswered(q), "empty store should not satisfy \(q.id)")
        }
    }

    func testTextWhitespaceOnlyIsNotAnswered() {
        var store = OwlQuestionnaireAnswerStore()
        store.text["t1"] = "   \n\t  "
        let q = schemaWithEveryType().questions.first { $0.id == "t1" }!
        XCTAssertFalse(store.isAnswered(q))
        XCTAssertTrue(store.collected(schemaWithEveryType())["t1"] == nil,
                      "whitespace-only text should not be collected")
    }

    func testTextTrimmedAndCollected() {
        var store = OwlQuestionnaireAnswerStore()
        store.text["t1"] = "  hello  "
        let collected = store.collected(schemaWithEveryType())
        XCTAssertEqual(collected["t1"], .text("hello"))
    }

    func testSingleChoiceAnsweredCollected() {
        var store = OwlQuestionnaireAnswerStore()
        store.single["s1"] = "b"
        let q = schemaWithEveryType().questions.first { $0.id == "s1" }!
        XCTAssertTrue(store.isAnswered(q))
        XCTAssertEqual(store.collected(schemaWithEveryType())["s1"], .choice("b"))
    }

    func testMultiChoiceEmptySetNotAnswered() {
        var store = OwlQuestionnaireAnswerStore()
        store.multi["m1"] = []
        let q = schemaWithEveryType().questions.first { $0.id == "m1" }!
        XCTAssertFalse(store.isAnswered(q))
        XCTAssertNil(store.collected(schemaWithEveryType())["m1"])
    }

    func testMultiChoiceCollectionSorted() {
        var store = OwlQuestionnaireAnswerStore()
        store.multi["m1"] = ["y", "x"]
        let collected = store.collected(schemaWithEveryType())
        // Sorted for deterministic wire output across encoder runs.
        XCTAssertEqual(collected["m1"], .choices(["x", "y"]))
    }

    func testRatingAndNpsCollected() {
        var store = OwlQuestionnaireAnswerStore()
        store.rating["r1"] = 4
        store.nps["n1"] = 9
        let collected = store.collected(schemaWithEveryType())
        XCTAssertEqual(collected["r1"], .rating(4))
        XCTAssertEqual(collected["n1"], .nps(9))
    }

    func testHasAllRequiredFalseUntilAllRequiredAnswered() {
        var store = OwlQuestionnaireAnswerStore()
        let schema = schemaWithEveryType()
        XCTAssertFalse(store.hasAllRequired(schema))
        store.text["t1"] = "ok"
        XCTAssertFalse(store.hasAllRequired(schema))
        store.single["s1"] = "a"
        XCTAssertFalse(store.hasAllRequired(schema))
        store.rating["r1"] = 5
        XCTAssertTrue(store.hasAllRequired(schema), "all required types (text, single, rating) now answered")
    }

    func testOptionalQuestionsDoNotBlockHasAllRequired() {
        var store = OwlQuestionnaireAnswerStore()
        let schema = schemaWithEveryType()
        store.text["t1"] = "hi"
        store.single["s1"] = "a"
        store.rating["r1"] = 3
        // multi/nps both optional, untouched — should not block
        XCTAssertTrue(store.hasAllRequired(schema))
    }

    // MARK: - Resume / prefill

    func testPrefillHydratesEveryAnswerType() {
        var store = OwlQuestionnaireAnswerStore()
        store.prefill(from: [
            "t1": .text("hello"),
            "s1": .choice("a"),
            "m1": .choices(["x", "y"]),
            "r1": .rating(3),
            "n1": .nps(8),
        ])
        XCTAssertEqual(store.text["t1"], "hello")
        XCTAssertEqual(store.single["s1"], "a")
        XCTAssertEqual(store.multi["m1"], ["x", "y"])
        XCTAssertEqual(store.rating["r1"], 3)
        XCTAssertEqual(store.nps["n1"], 8)
    }

    func testFirstUnansweredLandsOnFirstMissingRequiredOrOptional() {
        let schema = schemaWithEveryType()
        var store = OwlQuestionnaireAnswerStore()
        // Nothing answered → land on index 0 (t1)
        XCTAssertEqual(store.firstUnansweredIndex(in: schema), 0)
        // Answer t1 → land on s1 (index 1)
        store.text["t1"] = "ok"
        XCTAssertEqual(store.firstUnansweredIndex(in: schema), 1)
        // Answer s1 → land on m1 (index 2). m1 is optional but empty, so
        // it still counts as unanswered for landing-position purposes.
        store.single["s1"] = "a"
        XCTAssertEqual(store.firstUnansweredIndex(in: schema), 2)
    }

    func testFirstUnansweredLandsOnLastWhenAllAnswered() {
        let schema = schemaWithEveryType()
        var store = OwlQuestionnaireAnswerStore()
        store.prefill(from: [
            "t1": .text("hi"),
            "s1": .choice("a"),
            "m1": .choices(["x"]),
            "r1": .rating(4),
            "n1": .nps(9),
        ])
        // All five questions answered, no Submit yet → land on last index
        // so the Submit button is live on the resumed page.
        XCTAssertEqual(store.firstUnansweredIndex(in: schema), schema.questions.count - 1)
    }

    // MARK: - Public API surface (compile-time check)

    func testPublicViewCompilesWithAndWithoutConsent() {
        // Pure surface verification — if this compiles, the public init
        // signatures both still exist with the right defaults.
        let q = OwlQuestionnaire(
            id: "id", slug: "demo", name: "n", description: nil,
            schema: schemaWithEveryType()
        )
        #if canImport(SwiftUI) && !os(watchOS)
        _ = OwlQuestionnaireView(questionnaire: q)
        _ = OwlQuestionnaireView(questionnaire: q, showsConsent: true)
        #endif
        XCTAssertEqual(q.slug, "demo")
    }
}
