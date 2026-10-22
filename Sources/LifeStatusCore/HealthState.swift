import Foundation

public enum Gauge: String, Codable, CaseIterable, Sendable {
    case hp, water, san
    public var duration: TimeInterval {
        switch self { case .hp: return 45 * 60; case .water: return 180 * 60; case .san: return 20 * 60 }
    }
    public var label: String {
        switch self { case .hp: return "HP"; case .water: return "水分"; case .san: return "SAN" }
    }
    public var action: String {
        switch self {
        case .hp: return "起身走几步或舒展一下，完成后点击"
        case .water: return "喝一杯水，完成后点击"
        case .san: return "远眺约 6 米外至少 20 秒，完成后点击"
        }
    }
}

public enum Rules {
    public static let restThreshold: TimeInterval = 15 * 60
    public static let emptyGrace: TimeInterval = 30 * 60
    public static let feedbackDuration: TimeInterval = 1.2
}

public struct Levels: Codable, Equatable, Sendable {
    public var hp: Double
    public var water: Double
    public var san: Double
    public init(hp: Double = 100, water: Double = 100, san: Double = 100) {
        self.hp = Self.clamp(hp); self.water = Self.clamp(water); self.san = Self.clamp(san)
    }
    private static func clamp(_ value: Double) -> Double { value.isFinite ? min(100, max(0, value)) : 100 }
    public subscript(_ gauge: Gauge) -> Double {
        get { switch gauge { case .hp: return hp; case .water: return water; case .san: return san } }
        set { switch gauge { case .hp: hp = Self.clamp(newValue); case .water: water = Self.clamp(newValue); case .san: san = Self.clamp(newValue) } }
    }
    public var allEmpty: Bool { Gauge.allCases.allSatisfy { self[$0] <= 0 } }
    public var timeToEmpty: TimeInterval { Gauge.allCases.map { self[$0] / 100 * $0.duration }.max() ?? 0 }
    public func decayed(by duration: TimeInterval) -> Levels {
        var copy = self
        for gauge in Gauge.allCases { copy[gauge] -= max(0, duration) / gauge.duration * 100 }
        return copy
    }
    public mutating func replenish(_ gauge: Gauge) {
        self[gauge] = gauge == .water ? self[gauge] + 100 / 3 : 100
    }
    public func theme(current: String = "normal") -> String {
        if allEmpty { return "empty" }
        let minimum = Gauge.allCases.map { self[$0] }.min() ?? 100
        if minimum >= 40 { return "normal" }
        if let previous = Gauge(rawValue: current), self[previous] == minimum { return current }
        return Gauge.allCases.first { self[$0] == minimum }!.rawValue
    }
}

public struct HealthState: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var levels = Levels()
    public var day: String
    public var usedToday = false
    public var failedToday = false
    public var streak = 0
    public var emptyDuration: TimeInterval = 0
    public var onboardingComplete = false
    public init(now: Date, calendar: Calendar = .current) { day = Self.dayID(now, calendar: calendar) }
    public static func dayID(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
    public var isValid: Bool {
        schemaVersion == 1 && day.count == 10 && streak >= 0 && emptyDuration.isFinite && emptyDuration >= 0
        && Gauge.allCases.allSatisfy { levels[$0].isFinite && (0...100).contains(levels[$0]) }
    }
    /// A day identifier only moves forward: clock/time-zone rollback cannot settle a day twice.
    public mutating func rollDay(to date: Date, calendar: Calendar = .current) {
        let next = Self.dayID(date, calendar: calendar)
        guard next > day else { return }
        if failedToday { streak = 0 }
        else if usedToday { streak += 1 }
        day = next; usedToday = false; failedToday = false
        levels = Levels(); emptyDuration = 0
    }
    public mutating func rest(at date: Date, calendar: Calendar = .current) {
        rollDay(to: date, calendar: calendar)
        levels = Levels(); emptyDuration = 0
    }
    public mutating func replenish(_ gauge: Gauge, at date: Date, calendar: Calendar = .current) {
        rollDay(to: date, calendar: calendar)
        usedToday = true; levels.replenish(gauge); emptyDuration = 0
    }
    /// Only confirmed working time reaches this method. Pending idle time stays outside the ledger.
    public mutating func work(for duration: TimeInterval, endingAt end: Date, calendar: Calendar = .current) {
        guard duration.isFinite, duration >= 0 else { return }
        var cursor = end.addingTimeInterval(-duration)
        rollDay(to: cursor, calendar: calendar)
        while cursor < end {
            let boundary = calendar.dateInterval(of: .day, for: cursor)?.end ?? end
            let stop = min(end, boundary)
            let seconds = stop.timeIntervalSince(cursor)
            guard seconds > 0 else { break }
            usedToday = true
            let untilEmpty = levels.timeToEmpty
            levels = levels.decayed(by: seconds)
            if levels.allEmpty {
                emptyDuration += max(0, seconds - untilEmpty)
                // Repeated decay steps can accumulate a sub-microsecond rounding error.
                if emptyDuration > Rules.emptyGrace + 0.000001 { failedToday = true }
            } else { emptyDuration = 0 }
            cursor = stop
            if cursor >= boundary { rollDay(to: cursor, calendar: calendar) }
        }
        rollDay(to: end, calendar: calendar)
    }
}
