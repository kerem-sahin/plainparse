import Foundation

/// How a calendar event, which may start the day before or end the day after, falls on one day.
public enum EventSpan {
    public enum Part: Equatable, Sendable {
        /// Covers the whole day (an all-day event, or one that starts earlier and ends later).
        case wholeDay
        /// Minutes after midnight, clipped to the day: 0...1440.
        case minutes(Range<Int>)
    }

    /// nil when the event does not touch `day`. `end` is exclusive, like a calendar shows it.
    public static func part(start: Date, end: Date, isAllDay: Bool, on day: Date, calendar: Calendar) -> Part? {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
        let eventEnd = max(end, start)

        if isAllDay {
            // An all-day event ends at the very end of its last day (or at midnight after it); treat that end as exclusive.
            let lastInstant = eventEnd > start ? eventEnd.addingTimeInterval(-1) : start
            return start < dayEnd && lastInstant >= dayStart ? .wholeDay : nil
        }
        // A zero-length event is a point in time.
        let effectiveEnd = eventEnd == start ? start.addingTimeInterval(1) : eventEnd
        guard start < dayEnd, effectiveEnd > dayStart else { return nil }
        if start <= dayStart, effectiveEnd >= dayEnd { return .wholeDay }

        let low = start <= dayStart ? 0 : minutes(of: start, from: dayStart, calendar: calendar)
        let high = effectiveEnd >= dayEnd ? 24 * 60 : minutes(of: effectiveEnd, from: dayStart, calendar: calendar)
        // A point or a very short event still gets a sliver, so it can be drawn and counted.
        return .minutes(low..<max(high, min(low + 1, 24 * 60)))
    }

    /// The clock reading on the day, so daylight-saving days are not an hour off.
    private static func minutes(of date: Date, from dayStart: Date, calendar: Calendar) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }
}
