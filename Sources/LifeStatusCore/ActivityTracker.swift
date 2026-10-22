import Foundation

/// Commit work only after input confirms an interval was shorter than a rest.
/// This keeps an absence from producing an irreversible working-time failure.
public struct ActivityTracker {
    public private(set) var state: HealthState
    /// All gauges share a five-minute display snapshot. Work accounting remains
    /// precise so resting and streak decisions do not depend on display timing.
    public private(set) var visibleLevels: Levels
    private var accountedUptime: TimeInterval
    private var lastInputUptime: TimeInterval
    private var nextLevelUpdate: TimeInterval
    public private(set) var resting = false
    private var suspended = false

    public init(state: HealthState, now: Date, uptime: TimeInterval, calendar: Calendar = .current) {
        self.state = state
        self.state.rollDay(to: now, calendar: calendar)
        visibleLevels = self.state.levels
        accountedUptime = uptime; lastInputUptime = uptime
        nextLevelUpdate = uptime + Rules.levelUpdateInterval
    }
    public mutating func sample(now: Date, uptime: TimeInterval, idle: TimeInterval, calendar: Calendar = .current) {
        guard !suspended, uptime.isFinite, idle.isFinite else { return }
        let previousDay = state.day
        var restored = false
        let input = uptime - max(0, idle)
        if input > lastInputUptime + 0.001 {
            if resting || input - lastInputUptime >= Rules.restThreshold {
                state.rest(at: now.addingTimeInterval(-max(0, idle)), calendar: calendar)
                restored = true
            } else {
                state.work(for: max(0, input - accountedUptime), endingAt: now.addingTimeInterval(-max(0, idle)), calendar: calendar)
            }
            state.usedToday = true
            accountedUptime = input; lastInputUptime = input; resting = false
        }
        if idle >= Rules.restThreshold || uptime - lastInputUptime >= Rules.restThreshold {
            state.rest(at: now, calendar: calendar)
            accountedUptime = uptime; resting = true
            restored = true
        }
        if restored || state.day != previousDay { resetVisibleLevels(uptime: uptime) }
        else { updateVisibleLevels(uptime: uptime) }
    }
    private mutating func resetVisibleLevels(uptime: TimeInterval) {
        visibleLevels = state.levels
        nextLevelUpdate = uptime + Rules.levelUpdateInterval
    }
    private mutating func updateVisibleLevels(uptime: TimeInterval) {
        guard uptime >= nextLevelUpdate else { return }
        visibleLevels = state.levels.decayed(by: max(0, uptime - accountedUptime))
        // A late sample catches up without moving the shared schedule forward
        // on every tick, panel opening, or individual replenishment.
        let intervals = floor((uptime - nextLevelUpdate) / Rules.levelUpdateInterval) + 1
        nextLevelUpdate += intervals * Rules.levelUpdateInterval
    }
    public mutating func interact(now: Date, uptime: TimeInterval, calendar: Calendar = .current) {
        sample(now: now, uptime: uptime, idle: 0, calendar: calendar)
        let previousDay = state.day
        state.rollDay(to: now, calendar: calendar); state.usedToday = true
        if state.day != previousDay { resetVisibleLevels(uptime: uptime) }
    }
    public mutating func replenish(_ gauge: Gauge, now: Date, uptime: TimeInterval, calendar: Calendar = .current) {
        interact(now: now, uptime: uptime, calendar: calendar)
        state.replenish(gauge, at: now, calendar: calendar)
        visibleLevels[gauge] = state.levels[gauge]
    }
    public mutating func suspend(now: Date, uptime: TimeInterval, calendar: Calendar = .current) {
        state.rest(at: now, calendar: calendar)
        accountedUptime = uptime; lastInputUptime = uptime; resting = true; suspended = true
        resetVisibleLevels(uptime: uptime)
    }
    public mutating func resume(now: Date, uptime: TimeInterval, calendar: Calendar = .current) {
        state.rest(at: now, calendar: calendar)
        accountedUptime = uptime; lastInputUptime = uptime; resting = false; suspended = false
        resetVisibleLevels(uptime: uptime)
    }
    public mutating func completeOnboarding(now: Date, uptime: TimeInterval, calendar: Calendar = .current) {
        state.onboardingComplete = true
        resume(now: now, uptime: uptime, calendar: calendar)
        state.usedToday = true
    }
}
