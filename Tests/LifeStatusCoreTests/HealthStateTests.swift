import XCTest
@testable import LifeStatusCore

final class HealthStateTests: XCTestCase {
    var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value }
    func date(_ value: String = "2026-10-21T09:00:00Z") -> Date { ISO8601DateFormatter().date(from: value)! }
    func fresh() -> HealthState { HealthState(now: date(), calendar: calendar) }

    func testFixedDurationsAndWaterPortion() {
        var state = fresh()
        state.work(for: 45 * 60, endingAt: date().addingTimeInterval(45 * 60), calendar: calendar)
        XCTAssertEqual(state.levels.hp, 0); XCTAssertEqual(state.levels.san, 0)
        XCTAssertEqual(state.levels.water, 75, accuracy: 0.0001)
        state.levels.water = 0
        state.replenish(.water, at: date(), calendar: calendar)
        XCTAssertEqual(state.levels.water, 100 / 3, accuracy: 0.0001)
        for _ in 0..<10 { state.replenish(.water, at: date(), calendar: calendar) }
        XCTAssertEqual(state.levels.water, 100)
    }
    func testGraceIsStrictAndFailureCannotBeRepaired() {
        var state = fresh()
        state.work(for: 210 * 60, endingAt: date().addingTimeInterval(210 * 60), calendar: calendar)
        XCTAssertFalse(state.failedToday)
        state.work(for: 1, endingAt: date().addingTimeInterval(210 * 60 + 1), calendar: calendar)
        XCTAssertTrue(state.failedToday)
        state.replenish(.hp, at: date(), calendar: calendar)
        state.rest(at: date(), calendar: calendar)
        XCTAssertTrue(state.failedToday); XCTAssertEqual(state.levels, Levels())
    }
    func testReplenishingAnyGaugeClearsGrace() {
        var state = fresh(); state.levels = Levels(hp: 0, water: 0, san: 0)
        state.work(for: 14 * 60, endingAt: date(), calendar: calendar)
        state.replenish(.san, at: date(), calendar: calendar)
        XCTAssertEqual(state.emptyDuration, 0); XCTAssertFalse(state.failedToday)
    }
    func testCrossMidnightResetsAndSettlesExactlyOnce() {
        var state = HealthState(now: date("2026-10-21T23:50:00Z"), calendar: calendar)
        state.work(for: 20 * 60, endingAt: date("2026-10-22T00:10:00Z"), calendar: calendar)
        XCTAssertEqual(state.streak, 1); XCTAssertTrue(state.usedToday)
        XCTAssertEqual(state.levels.san, 50, accuracy: 0.001)
        state.rollDay(to: date("2026-10-22T12:00:00Z"), calendar: calendar)
        XCTAssertEqual(state.streak, 1)
    }
    func testDaysWithoutWorkFreezeStreakAndFailedDayResets() {
        var state = fresh(); state.streak = 4; state.usedToday = true
        state.rollDay(to: date("2026-10-25T09:00:00Z"), calendar: calendar)
        XCTAssertEqual(state.streak, 5)
        state.rollDay(to: date("2026-10-26T09:00:00Z"), calendar: calendar)
        XCTAssertEqual(state.streak, 5)
        state.failedToday = true
        state.rollDay(to: date("2026-10-27T09:00:00Z"), calendar: calendar)
        XCTAssertEqual(state.streak, 0); XCTAssertFalse(state.failedToday)
    }
    func testClockRollbackDoesNotResettleDays() {
        var state = fresh(); state.usedToday = true
        state.rollDay(to: date("2026-10-22T09:00:00Z"), calendar: calendar)
        state.rollDay(to: date("2026-10-21T09:00:00Z"), calendar: calendar)
        state.rollDay(to: date("2026-10-22T09:00:00Z"), calendar: calendar)
        XCTAssertEqual(state.streak, 1); XCTAssertEqual(state.day, "2026-10-22")
    }
    func testMenuBoundaryTiesAndEmptyState() {
        XCTAssertEqual(Levels(hp: 40, water: 40, san: 40).theme(), "normal")
        XCTAssertEqual(Levels(hp: 39.99, water: 80, san: 80).theme(), "hp")
        XCTAssertEqual(Levels(hp: 20, water: 20, san: 80).theme(current: "water"), "water")
        XCTAssertEqual(Levels(hp: 20, water: 20, san: 80).theme(current: "san"), "hp")
        XCTAssertEqual(Levels(hp: 0, water: 0, san: 0).theme(), "empty")
    }
    func testLongAbsenceDiscardsTentativeFailure() {
        var state = fresh(); state.levels = Levels(hp: 0, water: 0, san: 0)
        var tracker = ActivityTracker(state: state, now: date(), uptime: 0, calendar: calendar)
        tracker.sample(now: date().addingTimeInterval(10 * 60), uptime: 10 * 60, idle: 10 * 60, calendar: calendar)
        XCTAssertFalse(tracker.state.failedToday)
        tracker.sample(now: date().addingTimeInterval(31 * 60), uptime: 31 * 60, idle: 0, calendar: calendar)
        XCTAssertFalse(tracker.state.failedToday); XCTAssertEqual(tracker.state.levels, Levels())
    }
    func testShortIdleBecomesWorkWhenInputResumes() {
        var state = fresh(); state.levels = Levels(hp: 0, water: 0, san: 0); state.emptyDuration = 29 * 60
        var tracker = ActivityTracker(state: state, now: date(), uptime: 0, calendar: calendar)
        tracker.sample(now: date().addingTimeInterval(2 * 60), uptime: 2 * 60, idle: 0, calendar: calendar)
        XCTAssertTrue(tracker.state.failedToday)
    }
    func testRestThresholdRestoresAndDoesNotEarnDays() {
        var state = fresh(); state.levels = Levels(hp: 10, water: 20, san: 30)
        var tracker = ActivityTracker(state: state, now: date(), uptime: 0, calendar: calendar)
        tracker.sample(now: date().addingTimeInterval(15 * 60), uptime: 15 * 60, idle: 15 * 60, calendar: calendar)
        XCTAssertTrue(tracker.resting); XCTAssertEqual(tracker.visibleLevels, Levels())
        XCTAssertFalse(tracker.state.usedToday)
    }
    func testSleepPausesWorkAndPreservesConfirmedFailure() {
        var state = fresh(); state.failedToday = true
        var tracker = ActivityTracker(state: state, now: date(), uptime: 0, calendar: calendar)
        tracker.suspend(now: date(), uptime: 0, calendar: calendar)
        tracker.sample(now: date().addingTimeInterval(5000), uptime: 5000, idle: 0, calendar: calendar)
        XCTAssertEqual(tracker.visibleLevels, Levels())
        tracker.resume(now: date().addingTimeInterval(5000), uptime: 5000, calendar: calendar)
        XCTAssertTrue(tracker.state.failedToday); XCTAssertEqual(tracker.state.levels, Levels())
    }
    func testRestartDoesNotChargeOfflineTime() throws {
        var state = fresh(); state.levels = Levels(hp: 60, water: 70, san: 80)
        let saved = try JSONEncoder().encode(state)
        let restored = try JSONDecoder().decode(HealthState.self, from: saved)
        let tracker = ActivityTracker(state: restored, now: date().addingTimeInterval(3600), uptime: 9000, calendar: calendar)
        XCTAssertEqual(tracker.visibleLevels, state.levels)
    }
    func testAlreadyIdleAtLaunchRestoresImmediately() {
        var state = fresh(); state.levels = Levels(hp: 10, water: 20, san: 30)
        var tracker = ActivityTracker(state: state, now: date(), uptime: 10000, calendar: calendar)
        tracker.sample(now: date(), uptime: 10000, idle: 15 * 60, calendar: calendar)
        XCTAssertTrue(tracker.resting); XCTAssertEqual(tracker.state.levels, Levels())
    }
    func testContinuousWorkFailsOnlyAfterThirtyMinutesOfEmpty() {
        var tracker = ActivityTracker(state: fresh(), now: date(), uptime: 0, calendar: calendar)
        for minute in 1...210 {
            tracker.sample(now: date().addingTimeInterval(Double(minute * 60)), uptime: Double(minute * 60), idle: 0, calendar: calendar)
        }
        XCTAssertFalse(tracker.state.failedToday)
        tracker.sample(now: date().addingTimeInterval(211 * 60), uptime: 211 * 60, idle: 0, calendar: calendar)
        XCTAssertTrue(tracker.state.failedToday)
    }
    func testTimezoneRollbackDoesNotAddAnotherStreakDay() {
        var state = fresh(); state.usedToday = true
        var east = calendar; east.timeZone = TimeZone(secondsFromGMT: 14 * 3600)!
        state.rollDay(to: date("2026-10-21T12:00:00Z"), calendar: east)
        XCTAssertEqual(state.streak, 1)
        state.rollDay(to: date("2026-10-21T12:00:00Z"), calendar: calendar)
        state.rollDay(to: date("2026-10-22T09:00:00Z"), calendar: calendar)
        XCTAssertEqual(state.streak, 1)
    }
}
