import Foundation

/// Stored raw values never change: existing records and iCloud copies depend on them.
public enum RepeatKind: String, Sendable, CaseIterable, Codable {
    case none
    case daily
    case weekly
    case monthly
    /// Added in 1.3. A build that predates it reads the task as a one-off on its start day.
    case yearly
}

public struct RepeatRule: Equatable, Sendable {
    public var kind: RepeatKind
    /// Bit 0 = Monday ... bit 6 = Sunday. `.weekly`: the weekdays (0 means "the weekday of the start day").
    /// `.monthly` with an `ordinal`: the single weekday of "first Monday".
    public var weekdayMask: Int
    /// Every N days (`.daily`, max 31), weeks (`.weekly`, max 8, counted from the start day's week) or months
    /// (`.monthly`, max 12). "2 haftada bir" is `.weekly` with 2.
    public var interval: Int
    /// `.monthly` only: 0 = the start's day of the month; 1...4 = the first...fourth `weekday` of the month;
    /// 5 = the last one. With 5 and no weekday: the last day of the month.
    public var ordinal: Int

    public static let none = RepeatRule(kind: .none, weekdayMask: 0)
    public static let daily = RepeatRule(kind: .daily, weekdayMask: 0)
    public static let lastDayOfMonth = RepeatRule(kind: .monthly, ordinal: Self.lastOrdinal)

    public static let lastOrdinal = 5

    /// "Her ayın ilk pazartesi": `ordinal` 1...4, or `lastOrdinal` for the last one; `weekday` is ISO (1 = Monday).
    public static func monthly(ordinal: Int, weekday: Int, interval: Int = 1) -> RepeatRule {
        RepeatRule(kind: .monthly, weekdayMask: Weekday.bit(weekday), interval: interval, ordinal: ordinal)
    }

    public init(kind: RepeatKind, weekdayMask: Int = 0, interval: Int = 1, ordinal: Int = 0) {
        self.kind = kind
        self.weekdayMask = weekdayMask
        self.interval = max(1, min(interval, Self.maxInterval(for: kind)))
        self.ordinal = kind == .monthly ? max(0, min(ordinal, Self.lastOrdinal)) : 0
    }

    public init(kind: RepeatKind, weekdayMask: Int = 0, weekInterval: Int) {
        self.init(kind: kind, weekdayMask: weekdayMask, interval: weekInterval)
    }

    public var weekInterval: Int { interval }

    public static func maxInterval(for kind: RepeatKind) -> Int {
        switch kind {
        case .daily: 31
        case .weekly: maxWeekInterval
        case .monthly: 12
        case .none, .yearly: 1
        }
    }

    public static let maxWeekInterval = 8

    /// "Her ayın ilk pazartesi", "her ayın son cuması": a weekday by position in the month.
    public var isMonthlyByWeekday: Bool { kind == .monthly && (1...Self.lastOrdinal).contains(ordinal) && weekdayMask & 0x7F != 0 }
    /// "Ayın son günü".
    public var isLastDayOfMonth: Bool { kind == .monthly && ordinal == Self.lastOrdinal && weekdayMask & 0x7F == 0 }

    /// The rule as one stored number (the model needs no new field and no new schema version):
    /// bits 0-6 weekdays, bits 8-15 interval - 1, bits 16-18 ordinal. A build that predates these reads only
    /// the weekday bits and (for weekly) bits 8-11: an older device shows an every-N-days or every-N-months
    /// task every day or every month, and a "first Monday" task on the start's day of the month.
    public var storedMask: Int {
        weekdayMask & 0x7F | (interval - 1) << 8 | ordinal << 16
    }

    public init(kind: RepeatKind, storedMask: Int) {
        self.init(kind: kind, weekdayMask: storedMask & 0x7F, interval: (storedMask >> 8 & 0xFF) + 1, ordinal: storedMask >> 16 & 0x7)
    }

    public var isRepeating: Bool { kind != .none }

    /// Whether this repeating rule produces an occurrence on `day`, counting from `start`.
    /// Missed occurrences are simply skipped; nothing piles up.
    public func occurs(on day: Date, startingFrom start: Date, calendar: Calendar) -> Bool {
        guard kind != .none else { return false }
        let target = calendar.startOfDay(for: day)
        let first = calendar.startOfDay(for: start)
        guard target >= first else { return false }

        switch kind {
        case .none:
            return false
        case .daily:
            guard interval > 1 else { return true }
            let days = calendar.dateComponents([.day], from: first, to: target).day ?? 0
            return days % interval == 0
        case .weekly:
            let mask = weekdayMask == 0 ? Weekday.bit(Weekday.iso(of: first, calendar: calendar)) : weekdayMask
            guard Weekday.mask(mask, contains: Weekday.iso(of: target, calendar: calendar)) else { return false }
            guard weekInterval > 1 else { return true }
            // Weeks run Monday to Sunday, counted from the week of the first occurrence: a Monday class every
            // other week, started on a Wednesday, begins the coming Monday.
            func monday(_ day: Date) -> Date {
                calendar.date(byAdding: .day, value: 1 - Weekday.iso(of: day, calendar: calendar), to: day) ?? day
            }
            let anchor = (0..<7).lazy
                .compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
                .first { Weekday.mask(mask, contains: Weekday.iso(of: $0, calendar: calendar)) } ?? first
            let days = calendar.dateComponents([.day], from: monday(anchor), to: monday(target)).day ?? 0
            return days >= 0 && (days / 7) % weekInterval == 0
        case .monthly:
            if interval > 1 {
                let months = (calendar.component(.year, from: target) - calendar.component(.year, from: first)) * 12
                    + calendar.component(.month, from: target) - calendar.component(.month, from: first)
                guard months % interval == 0 else { return false }
            }
            let targetDay = calendar.component(.day, from: target)
            let monthLength = calendar.range(of: .day, in: .month, for: target)?.count ?? 31
            if ordinal == 0 {
                return targetDay == min(calendar.component(.day, from: first), monthLength)
            }
            guard let weekday = Weekday.isos(in: weekdayMask).first else {
                return ordinal == Self.lastOrdinal && targetDay == monthLength
            }
            guard Weekday.iso(of: target, calendar: calendar) == weekday else { return false }
            return ordinal == Self.lastOrdinal ? targetDay + 7 > monthLength : (targetDay - 1) / 7 + 1 == ordinal
        case .yearly:
            // Same day and month every year; 29 February falls on the 28th in other years.
            guard calendar.component(.month, from: target) == calendar.component(.month, from: first) else { return false }
            let startDay = calendar.component(.day, from: first)
            let monthLength = calendar.range(of: .day, in: .month, for: target)?.count ?? 31
            return calendar.component(.day, from: target) == min(startDay, monthLength)
        }
    }
}
