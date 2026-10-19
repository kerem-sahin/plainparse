import Foundation

/// The days on which a step of a repeating task was ticked, kept as a small comma-separated text
/// ("2026-10-11,2026-10-12") so it syncs as a plain string. A one-off task uses a simple on/off instead.
public enum StepDays {
    public static func contains(_ raw: String, day: Date, calendar: Calendar = .current) -> Bool {
        let key = dayString(day, calendar: calendar)
        return raw.split(separator: ",").contains { $0 == Substring(key) }
    }

    /// Adds or removes `day`, keeping only the most recent `limit` days so the text never grows without bound.
    public static func setting(_ raw: String, day: Date, on: Bool, calendar: Calendar = .current, limit: Int = 90) -> String {
        let key = dayString(day, calendar: calendar)
        var keys = raw.split(separator: ",").map(String.init).filter { $0 != key }
        if on { keys.append(key) }
        keys.sort()
        if keys.count > limit { keys.removeFirst(keys.count - limit) }
        return keys.joined(separator: ",")
    }

    /// "2026-10-16" for a calendar day, in that calendar's own time zone.
    public static func dayString(_ day: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
