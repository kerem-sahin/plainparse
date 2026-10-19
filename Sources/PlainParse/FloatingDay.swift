import Foundation

/// A calendar day that stays the same day in every time zone.
///
/// Stored as noon UTC of that day, so "16 October" is still the 16th after flying to New York or when a
/// second device sits in another zone. Values written before this existed (local midnight) are read as
/// the local day they were meant for.
public enum FloatingDay {
    private static func gregorian(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// The value to store for a day as seen on screen (any moment of that local day).
    public static func store(_ localDay: Date, calendar: Calendar = .current) -> Date {
        let parts = gregorian(in: calendar.timeZone).dateComponents([.year, .month, .day], from: localDay)
        var storeParts = DateComponents()
        storeParts.year = parts.year
        storeParts.month = parts.month
        storeParts.day = parts.day
        storeParts.hour = 12
        return gregorian(in: .gmt).date(from: storeParts) ?? localDay
    }

    /// The start of the local day a stored value stands for.
    public static func local(_ stored: Date, calendar: Calendar = .current) -> Date {
        let utc = gregorian(in: .gmt)
        let time = utc.dateComponents([.hour, .minute, .second], from: stored)
        guard time.hour == 12, time.minute == 0, time.second == 0 else {
            return calendar.startOfDay(for: stored)
        }
        let parts = utc.dateComponents([.year, .month, .day], from: stored)
        return gregorian(in: calendar.timeZone).date(from: parts) ?? calendar.startOfDay(for: stored)
    }
}
