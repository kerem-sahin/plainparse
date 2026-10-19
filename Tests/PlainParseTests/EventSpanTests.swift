import Foundation
import Testing
@testable import PlainParse

struct EventSpanTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test func meetingInsideTheDayKeepsItsMinutes() {
        let part = EventSpan.part(start: date(16, 9, 30), end: date(16, 10, 45), isAllDay: false, on: date(16, 0), calendar: calendar)
        #expect(part == .minutes(570..<645))
    }

    @Test func eventOnAnotherDayIsNotCounted() {
        #expect(EventSpan.part(start: date(15, 9), end: date(15, 10), isAllDay: false, on: date(16, 0), calendar: calendar) == nil)
        #expect(EventSpan.part(start: date(17, 9), end: date(17, 10), isAllDay: false, on: date(16, 0), calendar: calendar) == nil)
    }

    @Test func eventEndingAtMidnightDoesNotLeakIntoTheNextDay() {
        let part = EventSpan.part(start: date(16, 22), end: date(17, 0), isAllDay: false, on: date(17, 0), calendar: calendar)
        #expect(part == nil)
        #expect(EventSpan.part(start: date(16, 22), end: date(17, 0), isAllDay: false, on: date(16, 0), calendar: calendar) == .minutes(1320..<1440))
    }

    @Test func overnightEventIsClippedOnBothDays() {
        let start = date(16, 22), end = date(17, 6)
        #expect(EventSpan.part(start: start, end: end, isAllDay: false, on: date(16, 0), calendar: calendar) == .minutes(1320..<1440))
        #expect(EventSpan.part(start: start, end: end, isAllDay: false, on: date(17, 0), calendar: calendar) == .minutes(0..<360))
    }

    @Test func multiDayEventCoversTheDaysInBetween() {
        let start = date(15, 10), end = date(18, 10)
        #expect(EventSpan.part(start: start, end: end, isAllDay: false, on: date(16, 0), calendar: calendar) == .wholeDay)
        #expect(EventSpan.part(start: start, end: end, isAllDay: false, on: date(17, 0), calendar: calendar) == .wholeDay)
        #expect(EventSpan.part(start: start, end: end, isAllDay: false, on: date(15, 0), calendar: calendar) == .minutes(600..<1440))
        #expect(EventSpan.part(start: start, end: end, isAllDay: false, on: date(18, 0), calendar: calendar) == .minutes(0..<600))
    }

    @Test func allDayEventUsesItsWholeDaysOnly() {
        // A one-day all-day event as a calendar stores it: midnight to the end of the day.
        let start = date(16, 0)
        let end = calendar.date(byAdding: .second, value: -1, to: date(17, 0))!
        #expect(EventSpan.part(start: start, end: end, isAllDay: true, on: date(16, 0), calendar: calendar) == .wholeDay)
        #expect(EventSpan.part(start: start, end: end, isAllDay: true, on: date(17, 0), calendar: calendar) == nil)
        #expect(EventSpan.part(start: start, end: end, isAllDay: true, on: date(15, 0), calendar: calendar) == nil)
    }

    @Test func allDayEventWithExclusiveMidnightEndDoesNotSpillOver() {
        let part = EventSpan.part(start: date(16, 0), end: date(17, 0), isAllDay: true, on: date(17, 0), calendar: calendar)
        #expect(part == nil)
    }

    @Test func pointInTimeStillGetsASliver() {
        let part = EventSpan.part(start: date(16, 12), end: date(16, 12), isAllDay: false, on: date(16, 0), calendar: calendar)
        #expect(part == .minutes(720..<721))
    }

    @Test func busyEventsShapeTheFreeGaps() {
        let meeting = TimedItem(id: UUID(), title: "Toplantı", kind: .event, startMinute: 600, endMinute: 660)
        let call = TimedItem(id: UUID(), title: "Arama", kind: .event, startMinute: 780, endMinute: 810)
        let task = TimedItem(id: UUID(), title: "İlaç", kind: .task, startMinute: 700)
        let gaps = DayClock.gaps(between: [meeting, task, call])
        #expect(gaps == [660..<780])
    }
}
