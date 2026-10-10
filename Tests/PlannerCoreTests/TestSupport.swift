import Foundation

/// Gregorian calendar in Istanbul, so tests never depend on the machine's settings.
let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Istanbul") ?? .gmt
    calendar.locale = Locale(identifier: "tr_TR")
    return calendar
}()

func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? .distantPast
}

/// Friday 9 October 2026, 11:06.
let now = date(2026, 10, 9, 11, 6)
