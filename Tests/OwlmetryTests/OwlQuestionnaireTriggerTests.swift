import XCTest
@testable import Owlmetry

final class OwlQuestionnaireTriggerTests: XCTestCase {
    private func snapshot(
        launches: Int = 0,
        foregrounds: Int = 0,
        firstLaunch: Date? = nil,
        now: Date = Date()
    ) -> OwlQuestionnaireState.Snapshot {
        OwlQuestionnaireState.Snapshot(
            launchCount: launches,
            foregroundCount: foregrounds,
            firstLaunchAt: firstLaunch,
            now: now
        )
    }

    func testLaunchesAtLeast() {
        XCTAssertFalse(OwlQuestionnaireCondition.launches(atLeast: 3).isSatisfied(state: snapshot(launches: 2)))
        XCTAssertTrue(OwlQuestionnaireCondition.launches(atLeast: 3).isSatisfied(state: snapshot(launches: 3)))
        XCTAssertTrue(OwlQuestionnaireCondition.launches(atLeast: 3).isSatisfied(state: snapshot(launches: 10)))
    }

    func testForegroundsAtLeast() {
        XCTAssertFalse(OwlQuestionnaireCondition.foregrounds(atLeast: 5).isSatisfied(state: snapshot(foregrounds: 4)))
        XCTAssertTrue(OwlQuestionnaireCondition.foregrounds(atLeast: 5).isSatisfied(state: snapshot(foregrounds: 5)))
    }

    func testDaysSinceFirstLaunch() {
        let now = Date()
        let oneDayAgo = now.addingTimeInterval(-86_400)
        let eightDaysAgo = now.addingTimeInterval(-8 * 86_400)
        XCTAssertFalse(OwlQuestionnaireCondition.daysSinceFirstLaunch(atLeast: 7)
            .isSatisfied(state: snapshot(firstLaunch: oneDayAgo, now: now)))
        XCTAssertTrue(OwlQuestionnaireCondition.daysSinceFirstLaunch(atLeast: 7)
            .isSatisfied(state: snapshot(firstLaunch: eightDaysAgo, now: now)))
        // No firstLaunch yet => 0 days elapsed
        XCTAssertFalse(OwlQuestionnaireCondition.daysSinceFirstLaunch(atLeast: 1)
            .isSatisfied(state: snapshot(firstLaunch: nil, now: now)))
    }

    func testHoursSinceFirstLaunch() {
        let now = Date()
        let twoHoursAgo = now.addingTimeInterval(-2 * 3_600)
        XCTAssertTrue(OwlQuestionnaireCondition.hoursSinceFirstLaunch(atLeast: 1)
            .isSatisfied(state: snapshot(firstLaunch: twoHoursAgo, now: now)))
        XCTAssertFalse(OwlQuestionnaireCondition.hoursSinceFirstLaunch(atLeast: 3)
            .isSatisfied(state: snapshot(firstLaunch: twoHoursAgo, now: now)))
    }

    func testWhenAllConditionsTrue() {
        let now = Date()
        let trigger: OwlQuestionnaireTrigger = .when(.launches(atLeast: 3), .daysSinceFirstLaunch(atLeast: 7))
        XCTAssertTrue(trigger.isSatisfied(state: snapshot(launches: 5, firstLaunch: now.addingTimeInterval(-8 * 86_400), now: now)))
        // Only one true → trigger fails (AND-only)
        XCTAssertFalse(trigger.isSatisfied(state: snapshot(launches: 5, firstLaunch: now.addingTimeInterval(-1 * 86_400), now: now)))
        XCTAssertFalse(trigger.isSatisfied(state: snapshot(launches: 1, firstLaunch: now.addingTimeInterval(-8 * 86_400), now: now)))
    }

    func testEmptyConditionsListMatches() {
        let trigger = OwlQuestionnaireTrigger.when()
        XCTAssertTrue(trigger.isSatisfied(state: snapshot()))
    }

    func testManualNeverSatisfies() {
        XCTAssertFalse(OwlQuestionnaireTrigger.manual.isSatisfied(state: snapshot(launches: 100, foregrounds: 100)))
    }

    func testAfterLaunchShortcut() {
        XCTAssertTrue(OwlQuestionnaireTrigger.afterLaunch.isSatisfied(state: snapshot(launches: 1)))
        XCTAssertFalse(OwlQuestionnaireTrigger.afterLaunch.isSatisfied(state: snapshot(launches: 0)))
    }

    // MARK: - State persistence

    func testLaunchCounterIncrementsOnce() {
        let defaults = UserDefaults(suiteName: "owl.test.questionnaire.\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.dictionaryRepresentation().keys.first ?? "") }
        let state = OwlQuestionnaireState(defaults: defaults)
        state.markConfiguredOnce()
        state.markConfiguredOnce()  // idempotent within process
        state.markConfiguredOnce()
        XCTAssertEqual(state.launchCount, 1)
        XCTAssertNotNil(state.firstLaunchAt)
    }

    func testForegroundIncrementsRepeatedly() {
        let defaults = UserDefaults(suiteName: "owl.test.questionnaire.\(UUID().uuidString)")!
        let state = OwlQuestionnaireState(defaults: defaults)
        state.incrementForeground()
        state.incrementForeground()
        state.incrementForeground()
        XCTAssertEqual(state.foregroundCount, 3)
    }

    func testFirstLaunchPreservedAcrossInstances() {
        let suite = "owl.test.questionnaire.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let early = Date(timeIntervalSinceReferenceDate: 100_000)
        let later = Date(timeIntervalSinceReferenceDate: 200_000)

        let first = OwlQuestionnaireState(defaults: defaults)
        first.markConfiguredOnce(now: early)
        XCTAssertEqual(first.firstLaunchAt?.timeIntervalSinceReferenceDate, 100_000)

        // Second process / second instance shouldn't overwrite firstLaunchAt.
        let second = OwlQuestionnaireState(defaults: defaults)
        second.markConfiguredOnce(now: later)
        XCTAssertEqual(second.firstLaunchAt?.timeIntervalSinceReferenceDate, 100_000)
        XCTAssertEqual(second.launchCount, 2)
    }
}
