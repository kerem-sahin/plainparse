import Foundation
import Testing
@testable import PlannerCore

struct RepeatRuleTests {
    @Test func noneNeverOccurs() {
        #expect(!RepeatRule.none.occurs(on: date(2026, 10, 9), startingFrom: date(2026, 10, 1), calendar: calendar))
    }

    @Test func dailyStartsOnTheStartDay() {
        let rule = RepeatRule.daily
        #expect(!rule.occurs(on: date(2026, 10, 8), startingFrom: date(2026, 10, 9), calendar: calendar))
        #expect(rule.occurs(on: date(2026, 10, 9), startingFrom: date(2026, 10, 9), calendar: calendar))
        #expect(rule.occurs(on: date(2026, 12, 25), startingFrom: date(2026, 10, 9), calendar: calendar))
    }

    @Test func weeklyFollowsTheMask() {
        let rule = RepeatRule(kind: .weekly, weekdayMask: Weekday.bit(1) | Weekday.bit(3))
        let start = date(2026, 10, 5)
        #expect(rule.occurs(on: date(2026, 10, 5), startingFrom: start, calendar: calendar))
        #expect(!rule.occurs(on: date(2026, 10, 6), startingFrom: start, calendar: calendar))
        #expect(rule.occurs(on: date(2026, 10, 7), startingFrom: start, calendar: calendar))
        #expect(rule.occurs(on: date(2026, 10, 12), startingFrom: start, calendar: calendar))
    }

    @Test func weeklyWithoutMaskUsesTheStartWeekday() {
        let rule = RepeatRule(kind: .weekly)
        let start = date(2026, 10, 9)
        #expect(rule.occurs(on: date(2026, 10, 16), startingFrom: start, calendar: calendar))
        #expect(!rule.occurs(on: date(2026, 10, 10), startingFrom: start, calendar: calendar))
    }

    @Test func weekdaysSkipTheWeekend() {
        let rule = RepeatRule(kind: .weekly, weekdayMask: Weekday.weekdaysMask)
        let start = date(2026, 10, 5)
        #expect(rule.occurs(on: date(2026, 10, 9), startingFrom: start, calendar: calendar))
        #expect(!rule.occurs(on: date(2026, 10, 10), startingFrom: start, calendar: calendar))
        #expect(!rule.occurs(on: date(2026, 10, 11), startingFrom: start, calendar: calendar))
        #expect(rule.occurs(on: date(2026, 10, 12), startingFrom: start, calendar: calendar))
    }

    @Test func monthlyClampsToShortMonths() {
        let rule = RepeatRule(kind: .monthly)
        let start = date(2026, 1, 31)
        #expect(rule.occurs(on: date(2026, 1, 31), startingFrom: start, calendar: calendar))
        #expect(!rule.occurs(on: date(2026, 2, 27), startingFrom: start, calendar: calendar))
        #expect(rule.occurs(on: date(2026, 2, 28), startingFrom: start, calendar: calendar))
        #expect(rule.occurs(on: date(2026, 3, 31), startingFrom: start, calendar: calendar))
    }

    @Test func weekdayNumbersAreIso() {
        #expect(Weekday.iso(of: date(2026, 10, 5), calendar: calendar) == 1)
        #expect(Weekday.iso(of: date(2026, 10, 9), calendar: calendar) == 5)
        #expect(Weekday.iso(of: date(2026, 10, 11), calendar: calendar) == 7)
    }

    @Test func storedRawValuesNeverChange() {
        #expect(RepeatKind.allCases.map(\.rawValue) == ["none", "daily", "weekly", "monthly"])
        #expect(Weekday.weekdaysMask == 31)
        #expect(Weekday.weekendMask == 96)
    }
}

struct TurkishTextTests {
    @Test func foldStripsTurkishLetters() {
        #expect(TurkishText.fold("ŞUBAT") == "subat")
        #expect(TurkishText.fold("Işık") == "isik")
        #expect(TurkishText.fold("Çarşamba") == "carsamba")
        #expect(TurkishText.fold("İş Sağlığı") == "is sagligi")
    }

    @Test func capitalisesWithTurkishRules() {
        #expect(TurkishText.capitalizedFirst("istanbul") == "İstanbul")
        #expect(TurkishText.capitalizedFirst("ıslak") == "Islak")
        #expect(TurkishText.capitalizedFirst("") == "")
    }
}
