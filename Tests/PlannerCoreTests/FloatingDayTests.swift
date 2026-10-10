import Foundation
import Testing
@testable import PlannerCore

struct FloatingDayTests {
    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func day(_ y: Int, _ m: Int, _ d: Int, in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    @Test func dayStaysTheSameAfterChangingTimeZone() {
        let istanbul = calendar("Europe/Istanbul")
        let newYork = calendar("America/New_York")
        let stored = FloatingDay.store(day(2026, 10, 16, in: istanbul), calendar: istanbul)

        let seenInNewYork = FloatingDay.local(stored, calendar: newYork)
        #expect(newYork.dateComponents([.year, .month, .day], from: seenInNewYork) == DateComponents(year: 2026, month: 10, day: 16))
        #expect(seenInNewYork == newYork.startOfDay(for: seenInNewYork))
    }

    @Test func roundTripsInEveryZone() {
        for zone in ["Pacific/Auckland", "Asia/Tokyo", "Europe/London", "America/Los_Angeles", "Pacific/Honolulu"] {
            let cal = calendar(zone)
            let local = day(2026, 3, 29, in: cal)
            #expect(FloatingDay.local(FloatingDay.store(local, calendar: cal), calendar: cal) == local, "\(zone)")
        }
    }

    @Test func anyMomentOfTheDayStoresTheSameValue() {
        let cal = calendar("Europe/Istanbul")
        let morning = cal.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 0, minute: 5))!
        let night = cal.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 23, minute: 55))!
        #expect(FloatingDay.store(morning, calendar: cal) == FloatingDay.store(night, calendar: cal))
    }

    @Test func oldLocalMidnightValuesAreStillReadAsTheirLocalDay() {
        let cal = calendar("Europe/Istanbul")
        let legacy = day(2026, 10, 16, in: cal) // local midnight, as stored before floating days existed
        #expect(FloatingDay.local(legacy, calendar: cal) == legacy)
    }
}
