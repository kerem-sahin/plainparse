import Foundation
import Testing
@testable import PlannerCore

struct EnglishParserTests {
    let parser = QuickAddParser(calendar: calendar, preferredLanguage: .english, slashDateDayFirst: false)
    let math = ListRef(id: UUID(), name: "Math")

    @Test func weekdayTimeAndList() {
        let entry = parser.parse("friday math homework 6pm", now: now, lists: [math])
        #expect(entry.title == "Math homework")
        #expect(entry.day == date(2026, 10, 16))
        #expect(entry.minute == 18 * 60)
        #expect(entry.listID == math.id)
        #expect(entry.highlights == [
            Highlight(kind: .date, range: 0..<6),
            Highlight(kind: .list, range: 7..<11),
            Highlight(kind: .time, range: 21..<24),
        ])
    }

    @Test func tomorrow() {
        let entry = parser.parse("tomorrow call mom", now: now)
        #expect(entry.title == "Call mom")
        #expect(entry.day == date(2026, 10, 10))
    }

    @Test func dayAfterTomorrow() {
        let entry = parser.parse("day after tomorrow dentist", now: now)
        #expect(entry.day == date(2026, 10, 11))
        #expect(entry.title == "Dentist")
    }

    @Test func everyDay() {
        let entry = parser.parse("every day vitamin 9pm", now: now)
        #expect(entry.title == "Vitamin")
        #expect(entry.rule == .daily)
        #expect(entry.minute == 21 * 60)
        #expect(entry.day == date(2026, 10, 9))
    }

    @Test func everyWeekday() {
        let entry = parser.parse("every weekday gym", now: now)
        #expect(entry.title == "Gym")
        #expect(entry.rule == RepeatRule(kind: .weekly, weekdayMask: Weekday.weekdaysMask))
    }

    @Test func weekdaysAlone() {
        let entry = parser.parse("stretch weekdays", now: now)
        #expect(entry.title == "Stretch")
        #expect(entry.rule == RepeatRule(kind: .weekly, weekdayMask: Weekday.weekdaysMask))
    }

    @Test func everyWeekend() {
        let entry = parser.parse("every weekend long run", now: now)
        #expect(entry.rule == RepeatRule(kind: .weekly, weekdayMask: Weekday.weekendMask))
        #expect(entry.title == "Long run")
    }

    @Test func severalWeekdays() {
        let entry = parser.parse("every monday and wednesday swim", now: now)
        #expect(entry.title == "Swim")
        #expect(entry.rule == RepeatRule(kind: .weekly, weekdayMask: Weekday.bit(1) | Weekday.bit(3)))
    }

    @Test func weeklyAndMonthly() {
        #expect(parser.parse("weekly review", now: now).rule == RepeatRule(kind: .weekly))
        #expect(parser.parse("pay rent every month", now: now).rule == RepeatRule(kind: .monthly))
        #expect(parser.parse("monthly report", now: now).rule == RepeatRule(kind: .monthly))
    }

    @Test func nextWeekday() {
        let entry = parser.parse("next tuesday report", now: now)
        #expect(entry.day == date(2026, 10, 13))
        #expect(entry.title == "Report")
    }

    @Test func nextWeek() {
        let entry = parser.parse("next week review", now: now)
        #expect(entry.day == date(2026, 10, 16))
        #expect(entry.title == "Review")
    }

    @Test func monthThenDay() {
        let entry = parser.parse("oct 15 pay rent", now: now)
        #expect(entry.day == date(2026, 10, 15))
        #expect(entry.title == "Pay rent")
    }

    @Test func dayThenMonth() {
        let entry = parser.parse("15 october pay rent", now: now)
        #expect(entry.day == date(2026, 10, 15))
    }

    @Test func ordinalDay() {
        let entry = parser.parse("october 15th dentist", now: now)
        #expect(entry.day == date(2026, 10, 15))
        #expect(entry.title == "Dentist")
    }

    @Test func slashDateMonthFirst() {
        let entry = parser.parse("10/15 dentist", now: now)
        #expect(entry.day == date(2026, 10, 15))
    }

    @Test func slashDateDayFirstWhenRegionWritesItThatWay() {
        let dayFirst = QuickAddParser(calendar: calendar, preferredLanguage: .english, slashDateDayFirst: true)
        #expect(dayFirst.parse("15/10 dentist", now: now).day == date(2026, 10, 15))
    }

    @Test func timeWithAt() {
        let entry = parser.parse("at 6:30pm call", now: now)
        #expect(entry.minute == 18 * 60 + 30)
        #expect(entry.title == "Call")
        #expect(entry.day == date(2026, 10, 9))
    }

    @Test func spacedMeridiem() {
        let entry = parser.parse("6 pm dinner", now: now)
        #expect(entry.minute == 18 * 60)
        #expect(entry.title == "Dinner")
    }

    @Test func noonAndMidnight() {
        #expect(parser.parse("12pm lunch", now: now).minute == 12 * 60)
        #expect(parser.parse("12am backup", now: now).minute == 0)
    }

    @Test func twentyFourHourClock() {
        #expect(parser.parse("standup 14:30", now: now).minute == 14 * 60 + 30)
    }

    @Test func deadlineWordIsPartOfTheDate() {
        let entry = parser.parse("by friday report", now: now)
        #expect(entry.day == date(2026, 10, 16))
        #expect(entry.title == "Report")
    }

    @Test func plainTitle() {
        let entry = parser.parse("buy milk", now: now)
        #expect(entry.title == "Buy milk")
        #expect(entry.day == nil)
        #expect(entry.highlights.isEmpty)
    }

    @Test func abbreviationsThatAreOrdinaryWordsAreIgnored() {
        let entry = parser.parse("sun cream", now: now)
        #expect(entry.day == nil)
        #expect(entry.title == "Sun cream")
    }

    @Test func turkishStillWorksWhenEnglishIsPreferred() {
        let entry = parser.parse("yarın annemi ara 18:00", now: now)
        #expect(entry.title == "Annemi ara")
        #expect(entry.day == date(2026, 10, 10))
        #expect(entry.minute == 18 * 60)
    }

    @Test func turkishCapitalisationOnlyForTurkishText() {
        #expect(parser.parse("iphone case", now: now).title == "Iphone case")
    }
}
