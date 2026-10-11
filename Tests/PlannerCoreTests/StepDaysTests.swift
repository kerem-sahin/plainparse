import Foundation
import Testing
@testable import PlannerCore

struct StepDaysTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }

    private func day(_ d: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: d, hour: 15))!
    }

    @Test func tickingAndUntickingADay() {
        var raw = ""
        raw = StepDays.setting(raw, day: day(11), on: true, calendar: calendar)
        #expect(StepDays.contains(raw, day: day(11), calendar: calendar))
        #expect(!StepDays.contains(raw, day: day(12), calendar: calendar))
        raw = StepDays.setting(raw, day: day(11), on: false, calendar: calendar)
        #expect(raw.isEmpty)
    }

    @Test func tickingTwiceKeepsOneEntry() {
        var raw = StepDays.setting("", day: day(11), on: true, calendar: calendar)
        raw = StepDays.setting(raw, day: day(11), on: true, calendar: calendar)
        #expect(raw == "2026-10-11")
    }

    @Test func daysStaySortedAndOldOnesDropPastTheLimit() {
        var raw = ""
        for d in [20, 12, 15] { raw = StepDays.setting(raw, day: day(d), on: true, calendar: calendar, limit: 2) }
        #expect(raw == "2026-10-15,2026-10-20")
    }

    @Test func partOfADayStringIsNotAMatch() {
        let raw = "2026-10-11"
        #expect(!StepDays.contains(raw, day: day(1), calendar: calendar))
    }
}
