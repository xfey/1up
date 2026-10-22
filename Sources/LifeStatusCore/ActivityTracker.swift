import Foundation

/// Commit work only after input confirms an interval was shorter than a rest.
/// This keeps an absence from producing an irreversible working-time failure.
public struct ActivityTracker {
    public private(set) var state: HealthState
    private var accountedUptime: TimeInterval
    private var lastInputUptime: TimeInterval
    public private(set) var resting = false
    private var suspended = false

    public init(state: HealthState, now: Date, uptime: TimeInterval, calendar: Calendar = .current) {
        self.state = state
        self.state.rollDay(to: now, calendar: calendar)
        accountedUptime = uptime; lastInputUptime = uptime
    }
    public mutating func sample(now: Date, uptime: TimeInterval, idle: TimeInterval, calendar: Calendar = .current) {
        guard !suspended, uptime.isFinite, idle.isFinite else { return }
        let input = uptime - max(0, idle)
        if input > lastInputUptime + 0.001 {
            if resting || input - lastInputUptime >= Rules.restThreshold {
                state.rest(at: now.addingTimeInterval(-max(0, idle)), calendar: calendar)
            } else {
                state.work(for: max(0, input - accountedUptime), endingAt: now.addingTimeInterval(-max(0, idle)), calendar: calendar)
            }
            state.usedToday = true
            accountedUptime = input; lastInputUptime = input; resting = false
        }
        if idle >= Rules.restThreshold || uptime - lastInputUptime >= Rules.restThreshold {
            state.rest(at: now, calendar: calendar)
            accountedUptime = uptime; resting = true
        }
    }
    public func visibleLevels(uptime: TimeInterval) -> Levels {
        guard !suspended, !resting else { return state.levels }
        return state.levels.decayed(by: max(0, uptime - accountedUptime))
    }
    public mutating func interact(now: Date, uptime: TimeInterval, calendar: Calendar = .current) {
        sample(now: now, uptime: uptime, idle: 0, calendar: calendar)
        state.rollDay(to: now, calendar: calendar); state.usedToday = true
    }
    public mutating func replenish(_ gauge: Gauge, now: Date, uptime: TimeInterval, calendar: Calendar = .current) {
        interact(now: now, uptime: uptime, calendar: calendar)
        state.replenish(gauge, at: now, calendar: calendar)
    }
    public mutating func suspend(now: Date, uptime: TimeInterval, calendar: Calendar = .current) {
        state.rest(at: now, calendar: calendar)
        accountedUptime = uptime; lastInputUptime = uptime; resting = true; suspended = true
    }
    public mutating func resume(now: Date, uptime: TimeInterval, calendar: Calendar = .current) {
        state.rest(at: now, calendar: calendar)
        accountedUptime = uptime; lastInputUptime = uptime; resting = false; suspended = false
    }
    public mutating func completeOnboarding(now: Date, uptime: TimeInterval) {
        state.onboardingComplete = true
        state.rest(at: now)
        interact(now: now, uptime: uptime)
    }
}
