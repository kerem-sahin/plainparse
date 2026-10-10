import Foundation

/// Stored raw values never change: existing records and iCloud copies depend on them.
public enum RepeatKind: String, Sendable, CaseIterable, Codable {
    case none
    case daily
    case weekly
    case monthly
}

public struct RepeatRule: Equatable, Sendable {
    public var kind: RepeatKind
    /// Bit 0 = Monday ... bit 6 = Sunday. Only used by `.weekly`; 0 means "the weekday of the start day".
    public var weekdayMask: Int

    public static let none = RepeatRule(kind: .none, weekdayMask: 0)
    public static let daily = RepeatRule(kind: .daily, weekdayMask: 0)

    public init(kind: RepeatKind, weekdayMask: Int = 0) {
        self.kind = kind
        self.weekdayMask = weekdayMask
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
            return true
        case .weekly:
            let mask = weekdayMask == 0 ? Weekday.bit(Weekday.iso(of: first, calendar: calendar)) : weekdayMask
            return Weekday.mask(mask, contains: Weekday.iso(of: target, calendar: calendar))
        case .monthly:
            let startDay = calendar.component(.day, from: first)
            let monthLength = calendar.range(of: .day, in: .month, for: target)?.count ?? 31
            return calendar.component(.day, from: target) == min(startDay, monthLength)
        }
    }
}
