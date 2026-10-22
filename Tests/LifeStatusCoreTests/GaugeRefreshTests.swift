import XCTest
@testable import LifeStatusCore

final class GaugeRefreshTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private let start = ISO8601DateFormatter().date(from: "2026-10-21T09:00:00Z")!
    private func tracker(levels: Levels = Levels()) -> ActivityTracker {
        var state = HealthState(now: start, calendar: calendar)
        state.levels = levels
        return ActivityTracker(state: state, now: start, uptime: 0, calendar: calendar)
    }
    private func sample(_ tracker: inout ActivityTracker, at seconds: Double, idle: Double = 0) {
        tracker.sample(now: start.addingTimeInterval(seconds), uptime: seconds, idle: idle, calendar: calendar)
    }
    private func assertFiveMinutes(_ levels: Levels, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(levels.hp, 88.8888888889, accuracy: 0.000001, file: file, line: line)
        XCTAssertEqual(levels.water, 97.2222222222, accuracy: 0.000001, file: file, line: line)
        XCTAssertEqual(levels.san, 75, accuracy: 0.000001, file: file, line: line)
    }

    func testFrequentSamplesChangeAllVisibleGaugesOnlyEveryFiveMinutes() {
        var tracker = tracker()
        var snapshot = tracker.visibleLevels
        var updates: [Int] = []
        for second in 1...600 {
            sample(&tracker, at: Double(second))
            if tracker.visibleLevels != snapshot {
                updates.append(second)
                snapshot = tracker.visibleLevels
            }
            if second == 300 { assertFiveMinutes(snapshot) }
        }
        XCTAssertEqual(updates, [300, 600])
        XCTAssertEqual(tracker.visibleLevels.hp, 77.7777777778, accuracy: 0.000001)
        XCTAssertEqual(tracker.visibleLevels.water, 94.4444444444, accuracy: 0.000001)
        XCTAssertEqual(tracker.visibleLevels.san, 50, accuracy: 0.000001)
    }

    func testUnconfirmedIdleUpdatesTheDisplayWithoutCommittingWork() {
        var tracker = tracker()
        sample(&tracker, at: 300, idle: 300)
        assertFiveMinutes(tracker.visibleLevels)
        XCTAssertEqual(tracker.state.levels, Levels())
        XCTAssertFalse(tracker.state.usedToday)
        sample(&tracker, at: 900, idle: 900)
        XCTAssertEqual(tracker.visibleLevels, Levels())
        XCTAssertFalse(tracker.state.failedToday)
    }

    func testReplenishmentIsImmediateAndPanelInteractionsKeepTheSharedSchedule() {
        var tracker = tracker(levels: Levels(hp: 60, water: 50, san: 40))
        tracker.interact(now: start.addingTimeInterval(120), uptime: 120, calendar: calendar)
        XCTAssertEqual(tracker.visibleLevels, Levels(hp: 60, water: 50, san: 40))
        tracker.replenish(.water, now: start.addingTimeInterval(150), uptime: 150, calendar: calendar)
        let replenished = tracker.visibleLevels
        XCTAssertEqual(replenished.hp, 60)
        XCTAssertEqual(replenished.san, 40)
        XCTAssertEqual(replenished.water, 81.9444444444, accuracy: 0.000001)
        tracker.interact(now: start.addingTimeInterval(299), uptime: 299, calendar: calendar)
        XCTAssertEqual(tracker.visibleLevels, replenished)
        sample(&tracker, at: 300)
        XCTAssertEqual(tracker.visibleLevels.hp, 48.8888888889, accuracy: 0.000001)
        XCTAssertEqual(tracker.visibleLevels.water, 80.5555555556, accuracy: 0.000001)
        XCTAssertEqual(tracker.visibleLevels.san, 15, accuracy: 0.000001)
    }

    func testSleepRestoresImmediatelyAndWakeStartsAFreshFiveMinutes() {
        var tracker = tracker(levels: Levels(hp: 20, water: 30, san: 40))
        tracker.suspend(now: start.addingTimeInterval(100), uptime: 100, calendar: calendar)
        XCTAssertEqual(tracker.visibleLevels, Levels())
        sample(&tracker, at: 1000)
        XCTAssertEqual(tracker.visibleLevels, Levels())
        tracker.resume(now: start.addingTimeInterval(2000), uptime: 2000, calendar: calendar)
        sample(&tracker, at: 2299)
        XCTAssertEqual(tracker.visibleLevels, Levels())
        sample(&tracker, at: 2300)
        assertFiveMinutes(tracker.visibleLevels)
    }

    func testIdleRestAndReturnResetTheCadence() {
        var tracker = tracker(levels: Levels(hp: 20, water: 30, san: 40))
        sample(&tracker, at: 200)
        sample(&tracker, at: 1100, idle: 900)
        XCTAssertTrue(tracker.resting)
        XCTAssertEqual(tracker.visibleLevels, Levels())
        sample(&tracker, at: 1107)
        XCTAssertFalse(tracker.resting)
        sample(&tracker, at: 1406)
        XCTAssertEqual(tracker.visibleLevels, Levels())
        sample(&tracker, at: 1407)
        assertFiveMinutes(tracker.visibleLevels)
    }

    func testDayRolloverRestoresBeforeTheNextScheduledUpdate() {
        let late = ISO8601DateFormatter().date(from: "2026-10-21T23:58:00Z")!
        var state = HealthState(now: late, calendar: calendar)
        state.levels = Levels(hp: 60, water: 50, san: 40)
        var tracker = ActivityTracker(state: state, now: late, uptime: 0, calendar: calendar)
        for seconds in [120.0, 419.0] {
            tracker.sample(now: late.addingTimeInterval(seconds), uptime: seconds, idle: 0, calendar: calendar)
            XCTAssertEqual(tracker.visibleLevels, Levels())
        }
        tracker.sample(now: late.addingTimeInterval(420), uptime: 420, idle: 0, calendar: calendar)
        assertFiveMinutes(tracker.visibleLevels)
        XCTAssertEqual(tracker.state.streak, 1)
    }

    func testLateSamplesCatchUpWithoutDriftingTheSchedule() {
        var tracker = tracker()
        sample(&tracker, at: 350)
        let snapshot = tracker.visibleLevels
        XCTAssertEqual(snapshot, tracker.state.levels)
        sample(&tracker, at: 599)
        XCTAssertEqual(tracker.visibleLevels, snapshot)
        sample(&tracker, at: 600)
        XCTAssertEqual(tracker.visibleLevels.san, 50, accuracy: 0.000001)
        sample(&tracker, at: 1199)
        XCTAssertGreaterThan(tracker.visibleLevels.san, 0)
        sample(&tracker, at: 1200)
        XCTAssertEqual(tracker.visibleLevels.san, 0, accuracy: 0.000001)
    }

    func testOnboardingStartsTheClockWhenTheUserBegins() {
        var tracker = tracker()
        tracker.completeOnboarding(now: start.addingTimeInterval(240), uptime: 240, calendar: calendar)
        XCTAssertEqual(tracker.visibleLevels, Levels())
        XCTAssertEqual(tracker.state.levels, Levels())
        sample(&tracker, at: 539)
        XCTAssertEqual(tracker.visibleLevels, Levels())
        sample(&tracker, at: 540)
        assertFiveMinutes(tracker.visibleLevels)
    }
}
