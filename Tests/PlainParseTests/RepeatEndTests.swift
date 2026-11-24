import Foundation
import Testing
@testable import PlainParse

/// A repeat that ends: "cumaya kadar her gün", "3 gün boyunca". Now: Friday 9 October 2026, 11:06.
struct RepeatEndTests {
    let tr = QuickAddParser(calendar: calendar, preferredLanguage: .turkish, slashDateDayFirst: true)
    let en = QuickAddParser(calendar: calendar, preferredLanguage: .english, slashDateDayFirst: false)

    func check(_ text: String, title: String, day: Date? = nil, end: Date?, rule: RepeatRule? = nil, english: Bool = false,
               sourceLocation: SourceLocation = #_sourceLocation) {
        let entry = (english ? en : tr).parse(text, now: now)
        #expect(entry.title == title, "\(text) title", sourceLocation: sourceLocation)
        #expect(entry.repeatEnd == end, "\(text) end", sourceLocation: sourceLocation)
        if let day { #expect(entry.day == day, "\(text) day", sourceLocation: sourceLocation) }
        if let rule { #expect(entry.rule == rule, "\(text) rule", sourceLocation: sourceLocation) }
    }

    @Test func untilWithRepeatEndsTheSeries() {
        check("cumaya kadar her gün rapor", title: "Rapor", day: date(2026, 10, 9), end: date(2026, 10, 16), rule: .daily)
        check("15 aralığa kadar her gün ilaç", title: "İlaç", end: date(2026, 12, 15), rule: .daily)
        check("her pazartesi ay sonuna kadar", title: "", end: date(2026, 10, 31),
              rule: RepeatRule(kind: .weekly, weekdayMask: Weekday.bit(1)))
        check("every day until friday gym", title: "Gym", day: date(2026, 10, 9), end: date(2026, 10, 16), rule: .daily, english: true)
        check("every day till friday gym", title: "Gym", end: date(2026, 10, 16), english: true)
        check("pazartesiden itibaren cumaya kadar her gün spor", title: "Spor", day: date(2026, 10, 12), end: date(2026, 10, 16), rule: .daily)
        check("her gün cumaya kadar spor", title: "Spor", end: date(2026, 10, 16))
    }

    @Test func lengthOfTimeEndsTheSeries() {
        check("3 gün boyunca ilaç", title: "İlaç", day: date(2026, 10, 9), end: date(2026, 10, 11), rule: .daily)
        check("bir hafta boyunca ilaç", title: "İlaç", end: date(2026, 10, 15), rule: .daily)
        check("2 hafta boyunca her gün", title: "", end: date(2026, 10, 22), rule: .daily)
        check("her gün bir ay boyunca ilaç", title: "İlaç", end: date(2026, 11, 8), rule: .daily)
        check("for 3 days vitamins", title: "Vitamins", end: date(2026, 10, 11), rule: .daily, english: true)
        check("for a week vitamins", title: "Vitamins", end: date(2026, 10, 15), english: true)
        check("every day for 2 weeks vitamins", title: "Vitamins", end: date(2026, 10, 22), english: true)
        check("every day for a month vitamins", title: "Vitamins", end: date(2026, 11, 8), english: true)
        check("yarından 3 gün boyunca ilaç", title: "İlaç", day: date(2026, 10, 10), end: date(2026, 10, 12))
    }

    @Test func withoutRepeatItStaysADeadline() {
        let entry = tr.parse("cumaya kadar rapor", now: now)
        #expect(entry.rule == .none)
        #expect(entry.repeatEnd == nil)
        #expect(entry.day == date(2026, 10, 16))
        #expect(entry.title == "Rapor")
        let english = en.parse("report until friday", now: now)
        #expect(english.repeatEnd == nil)
        #expect(english.day == date(2026, 10, 16))
    }

    @Test func badOrUnrelatedPhrasesAreIgnored() {
        // The end is before the start.
        check("15 ekimden itibaren 12 ekime kadar her gün spor", title: "Spor", end: nil)
        let mom = en.parse("buy a gift for mom", now: now)
        #expect(mom.repeatEnd == nil)
        #expect(mom.rule == .none)
        let hours = en.parse("study for 2 hours", now: now)
        #expect(hours.repeatEnd == nil)
        #expect(tr.parse("her gün spor", now: now).repeatEnd == nil)
    }

    @Test func spanCountsFromTheFirstOccurrence() {
        let monday = RepeatRule(kind: .weekly, weekdayMask: Weekday.bit(1))
        check("her pazartesi 3 gün boyunca", title: "", end: date(2026, 10, 14), rule: monday)
        check("every monday for 3 weeks", title: "", end: date(2026, 11, 1), rule: monday, english: true)
        // An explicit end before the first occurrence is dropped.
        check("her pazartesi yarına kadar spor", title: "Spor", end: nil, rule: monday)
        check("every monday until saturday gym", title: "Gym", end: nil, rule: monday, english: true)
    }

    @Test func englishSpanWithoutRepeatOnlyAtTheStart() {
        check("for 3 days vitamins", title: "Vitamins", end: date(2026, 10, 11), rule: .daily, english: true)
        check("buy gift for a week", title: "Buy gift for a week", end: nil, rule: RepeatRule.none, english: true)
        check("call mom for 2 days", title: "Call mom for 2 days", end: nil, rule: RepeatRule.none, english: true)
        check("3 gün boyunca ilaç", title: "İlaç", end: date(2026, 10, 11), rule: .daily)
    }

    @Test func untilTomorrowAndBareMonth() {
        check("her gün yarına kadar spor", title: "Spor", end: date(2026, 10, 10), rule: .daily)
        check("every day until tomorrow gym", title: "Gym", end: date(2026, 10, 10), rule: .daily, english: true)
        check("every month until december rent", title: "Rent", end: date(2026, 11, 30), rule: RepeatRule(kind: .monthly), english: true)
        check("her ay aralığa kadar kira", title: "Kira", end: date(2026, 11, 30), rule: RepeatRule(kind: .monthly))
    }

    @Test func weeklyDeadlineIsTheWeekday() {
        let friday = RepeatRule(kind: .weekly, weekdayMask: Weekday.bit(5))
        check("her hafta cumaya kadar rapor gönder", title: "Rapor gönder", end: nil, rule: friday)
        check("every week by friday send report", title: "Send report", end: nil, rule: friday, english: true)
    }
}
