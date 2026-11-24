import Foundation
import Testing
@testable import PlainParse

struct RepeatKindsTests {
    let tr = QuickAddParser(calendar: calendar, preferredLanguage: .turkish)
    let en = QuickAddParser(calendar: calendar, preferredLanguage: .english)

    func check(_ text: String, title: String, day: Date? = nil, rule: RepeatRule, english: Bool = false,
               sourceLocation: SourceLocation = #_sourceLocation) {
        let entry = (english ? en : tr).parse(text, now: now)
        #expect(entry.title == title, "\(text) title", sourceLocation: sourceLocation)
        #expect(entry.rule == rule, "\(text) rule", sourceLocation: sourceLocation)
        if let day { #expect(entry.day == day, "\(text) day", sourceLocation: sourceLocation) }
    }

    func occurs(_ rule: RepeatRule, _ target: Date, from start: Date) -> Bool {
        rule.occurs(on: target, startingFrom: start, calendar: calendar)
    }

    // MARK: Model

    @Test func everyOldStoredValueDecodesIdentically() {
        for kind in RepeatKind.allCases {
            for mask in 0...0x7F {
                for interval in 1...8 {
                    let stored = mask | (interval - 1) << 8
                    let rule = RepeatRule(kind: kind, storedMask: stored)
                    #expect(rule.weekdayMask == mask)
                    #expect(rule.ordinal == 0)
                    // Only weekly ever stored an interval; the others read it as their own (daily, monthly) or 1.
                    if kind == .weekly { #expect(rule.interval == interval) }
                    if kind == .weekly || kind == .none { #expect(rule.storedMask == stored || kind == .none) }
                }
            }
        }
    }

    @Test func storedMaskLayout() {
        #expect(RepeatRule(kind: .daily, interval: 3).storedMask == 2 << 8)
        #expect(RepeatRule(kind: .weekly, weekdayMask: 5, interval: 8).storedMask == 5 | 7 << 8)
        #expect(RepeatRule.monthly(ordinal: 2, weekday: 1).storedMask == 1 | 2 << 16)
        #expect(RepeatRule.lastDayOfMonth.storedMask == 5 << 16)
        #expect(RepeatRule.monthly(ordinal: 5, weekday: 5, interval: 3).storedMask == 16 | 2 << 8 | 5 << 16)
        for rule in [RepeatRule.lastDayOfMonth, .monthly(ordinal: 1, weekday: 7), .monthly(ordinal: 5, weekday: 3, interval: 12),
                     RepeatRule(kind: .daily, interval: 31), RepeatRule(kind: .monthly, interval: 6), .none, .daily] {
            #expect(RepeatRule(kind: rule.kind, storedMask: rule.storedMask) == rule)
        }
        #expect(RepeatRule(kind: .daily, interval: 99).interval == 31)
        #expect(RepeatRule(kind: .weekly, interval: 99).interval == 8)
        #expect(RepeatRule(kind: .monthly, interval: 99).interval == 12)
        #expect(RepeatRule(kind: .daily, ordinal: 3).ordinal == 0)
    }

    @Test func oldBuildReadsNewRulesAsPlainOnes() {
        // A build that only knows weekday bits and weekly interval sees the start's day of the month.
        let stored = RepeatRule.monthly(ordinal: 1, weekday: 1).storedMask
        #expect(stored & 0x7F == Weekday.bit(1))
        #expect(stored >> 8 & 0xF == 0)
    }

    @Test func everyOtherDay() {
        let rule = RepeatRule(kind: .daily, interval: 2)
        let start = date(2026, 10, 9)
        #expect(occurs(rule, date(2026, 10, 9), from: start))
        #expect(!occurs(rule, date(2026, 10, 10), from: start))
        #expect(occurs(rule, date(2026, 10, 11), from: start))
        #expect(occurs(rule, date(2026, 11, 2), from: start))
        #expect(!occurs(rule, date(2026, 11, 1), from: start))
        // Across the autumn clock change.
        #expect(occurs(RepeatRule(kind: .daily, interval: 3), date(2026, 11, 8), from: date(2026, 10, 9)))
    }

    @Test func everyThreeMonths() {
        let rule = RepeatRule(kind: .monthly, interval: 3)
        let start = date(2026, 10, 31)
        #expect(occurs(rule, date(2026, 10, 31), from: start))
        #expect(!occurs(rule, date(2026, 11, 30), from: start))
        #expect(!occurs(rule, date(2026, 12, 31), from: start))
        #expect(occurs(rule, date(2027, 1, 31), from: start))
        #expect(occurs(rule, date(2027, 4, 30), from: start))
        #expect(!occurs(rule, date(2027, 1, 30), from: start))
    }

    @Test func nthWeekdayOfTheMonth() {
        let rule = RepeatRule.monthly(ordinal: 1, weekday: 1)
        let start = date(2026, 11, 2)
        #expect(occurs(rule, date(2026, 11, 2), from: start))
        #expect(!occurs(rule, date(2026, 11, 9), from: start))
        #expect(occurs(rule, date(2026, 12, 7), from: start))
        #expect(occurs(rule, date(2027, 2, 1), from: start))
        let second = RepeatRule.monthly(ordinal: 2, weekday: 2)
        #expect(occurs(second, date(2026, 10, 13), from: date(2026, 10, 13)))
        #expect(!occurs(second, date(2026, 10, 20), from: date(2026, 10, 13)))
        let fourth = RepeatRule.monthly(ordinal: 4, weekday: 5)
        #expect(occurs(fourth, date(2026, 10, 23), from: date(2026, 10, 1)))
        #expect(!occurs(fourth, date(2026, 10, 30), from: date(2026, 10, 1)))
    }

    @Test func lastWeekdayOfTheMonth() {
        let rule = RepeatRule.monthly(ordinal: 5, weekday: 5)
        let start = date(2026, 10, 1)
        #expect(!occurs(rule, date(2026, 10, 23), from: start))
        #expect(occurs(rule, date(2026, 10, 30), from: start))
        #expect(occurs(rule, date(2026, 11, 27), from: start))
        #expect(occurs(rule, date(2027, 2, 26), from: start))
        // A month with five of them, and one whose last is on the 25th.
        #expect(occurs(rule, date(2027, 4, 30), from: start))
        #expect(rule.isMonthlyByWeekday)
        #expect(!rule.isLastDayOfMonth)
    }

    @Test func lastDayOfTheMonth() {
        let rule = RepeatRule.lastDayOfMonth
        let start = date(2026, 10, 31)
        #expect(rule.isLastDayOfMonth)
        #expect(occurs(rule, date(2026, 10, 31), from: start))
        #expect(!occurs(rule, date(2026, 11, 29), from: start))
        #expect(occurs(rule, date(2026, 11, 30), from: start))
        #expect(occurs(rule, date(2027, 2, 28), from: start))
        #expect(occurs(rule, date(2028, 2, 29), from: start))
        #expect(!occurs(rule, date(2028, 2, 28), from: start))
    }

    @Test func positionWithAnInterval() {
        let rule = RepeatRule.monthly(ordinal: 1, weekday: 1, interval: 3)
        let start = date(2026, 11, 2)
        #expect(occurs(rule, date(2026, 11, 2), from: start))
        #expect(!occurs(rule, date(2026, 12, 7), from: start))
        #expect(occurs(rule, date(2027, 2, 1), from: start))
    }

    // MARK: Parser, Turkish

    @Test func everyNDaysTurkish() {
        let two = RepeatRule(kind: .daily, interval: 2)
        check("iki günde bir ilaç", title: "İlaç", day: date(2026, 10, 9), rule: two)
        check("2 günde bir", title: "", day: date(2026, 10, 9), rule: two)
        check("3 günde bir saç yıka", title: "Saç yıka", day: date(2026, 10, 9), rule: RepeatRule(kind: .daily, interval: 3))
        check("her 3 günde bir", title: "", rule: RepeatRule(kind: .daily, interval: 3))
        check("15 günde bir", title: "", rule: RepeatRule(kind: .daily, interval: 15))
        check("gün aşırı", title: "", rule: two)
        check("günaşırı ilaç", title: "İlaç", rule: two)
        check("2 günde bir yarın", title: "", day: date(2026, 10, 10), rule: two)
    }

    @Test func everyNMonthsTurkish() {
        let three = RepeatRule(kind: .monthly, interval: 3)
        check("3 ayda bir diş kontrolü", title: "Diş kontrolü", day: date(2026, 10, 9), rule: three)
        check("her 3 ayda bir", title: "", rule: three)
        check("6 ayda bir", title: "", rule: RepeatRule(kind: .monthly, interval: 6))
        check("iki ayda bir", title: "", rule: RepeatRule(kind: .monthly, interval: 2))
        check("ayda bir", title: "", day: date(2026, 10, 9), rule: RepeatRule(kind: .monthly))
        check("3 ayda bir 15 kasım", title: "", day: date(2026, 11, 15), rule: three)
        check("12 ayda bir", title: "", rule: RepeatRule(kind: .yearly))
    }

    @Test func monthlyByPositionTurkish() {
        check("her ayın ilk pazartesi toplantı", title: "Toplantı", day: date(2026, 11, 2), rule: .monthly(ordinal: 1, weekday: 1))
        check("her ayın ilk pazartesisi toplantı", title: "Toplantı", day: date(2026, 11, 2), rule: .monthly(ordinal: 1, weekday: 1))
        check("her ayın ikinci salı", title: "", day: date(2026, 10, 13), rule: .monthly(ordinal: 2, weekday: 2))
        check("her ayın son cuması", title: "", day: date(2026, 10, 30), rule: .monthly(ordinal: 5, weekday: 5))
        check("her ayın son günü fatura", title: "Fatura", day: date(2026, 10, 31), rule: .lastDayOfMonth)
        check("her ay sonu", title: "", day: date(2026, 10, 31), rule: .lastDayOfMonth)
        check("her ayın sonu rapor", title: "Rapor", day: date(2026, 10, 31), rule: .lastDayOfMonth)
        check("her ayın ilk günü kira", title: "Kira", day: date(2026, 11, 1), rule: RepeatRule(kind: .monthly))
    }

    @Test func oneOffsStayOneOffs() {
        check("ayın son günü fatura", title: "Fatura", day: date(2026, 10, 31), rule: .none)
        check("ilk pazartesi toplantısı", title: "İlk toplantısı", day: date(2026, 10, 12), rule: .none)
        check("son gün başvuru", title: "Son gün başvuru", rule: .none)
        check("2 gün izin", title: "2 gün izin", rule: .none)
        check("3 ay staj", title: "3 ay staj", rule: .none)
    }

    // MARK: Parser, English

    @Test func everyNDaysAndMonthsEnglish() {
        let two = RepeatRule(kind: .daily, interval: 2)
        check("every other day", title: "", day: date(2026, 10, 9), rule: two, english: true)
        check("every 2 days", title: "", rule: two, english: true)
        check("every three days vitamins", title: "Vitamins", rule: RepeatRule(kind: .daily, interval: 3), english: true)
        check("every 3 months", title: "", day: date(2026, 10, 9), rule: RepeatRule(kind: .monthly, interval: 3), english: true)
        check("every other month", title: "", rule: RepeatRule(kind: .monthly, interval: 2), english: true)
        check("every quarter", title: "", rule: RepeatRule(kind: .monthly, interval: 3), english: true)
        check("quarterly taxes", title: "Taxes", rule: RepeatRule(kind: .monthly, interval: 3), english: true)
        check("once a month", title: "", rule: RepeatRule(kind: .monthly), english: true)
        check("dentist 2 days", title: "Dentist 2 days", rule: .none, english: true)
    }

    @Test func monthlyByPositionEnglish() {
        let firstMonday = RepeatRule.monthly(ordinal: 1, weekday: 1)
        check("first monday of every month meeting", title: "Meeting", day: date(2026, 11, 2), rule: firstMonday, english: true)
        check("every first monday meeting", title: "Meeting", day: date(2026, 11, 2), rule: firstMonday, english: true)
        check("last friday of every month", title: "", day: date(2026, 10, 30), rule: .monthly(ordinal: 5, weekday: 5), english: true)
        check("last day of every month invoices", title: "Invoices", day: date(2026, 10, 31), rule: .lastDayOfMonth, english: true)
        check("every 2nd tuesday of the month", title: "", day: date(2026, 10, 13), rule: .monthly(ordinal: 2, weekday: 2), english: true)
        // Without "of the month" it is still every other week.
        check("every second tuesday", title: "", rule: RepeatRule(kind: .weekly, weekdayMask: Weekday.bit(2), weekInterval: 2), english: true)
        check("first monday meeting", title: "First meeting", day: date(2026, 10, 12), rule: .none, english: true)
        check("last day of the month report", title: "Report", day: date(2026, 10, 31), rule: .none, english: true)
    }

    /// A count of days with no "bir"/"her" is a length: "kitabı 3 günde bitir" is due in three days' time, not a repeat.
    @Test func aLengthIsNotAnInterval() {
        let tr = QuickAddParser(calendar: calendar, preferredLanguage: .turkish, slashDateDayFirst: true)
        for text in ["kitabı 3 günde bitir", "ödevi 2 günde yap", "2 haftada teslim et", "3 ayda öde"] {
            #expect(tr.parse(text, now: now).rule == .none, "\(text)")
        }
        #expect(tr.parse("3 günde bir sula", now: now).rule.interval == 3)
        #expect(tr.parse("her 3 günde sula", now: now).rule.interval == 3)
    }
}
