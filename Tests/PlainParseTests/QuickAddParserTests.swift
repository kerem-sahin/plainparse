import Foundation
import Testing
@testable import PlainParse

struct QuickAddParserTests {
    let parser = QuickAddParser(calendar: calendar, preferredLanguage: .turkish, slashDateDayFirst: true)
    let fizyoloji = ListRef(id: UUID(), name: "Fizyoloji")
    let anatomi = ListRef(id: UUID(), name: "Anatomi")

    @Test func weekdayTimeAndList() {
        let entry = parser.parse("Cuma fizyoloji ödevi 18:00", now: now, lists: [fizyoloji, anatomi])
        #expect(entry.title == "Fizyoloji ödevi")
        #expect(entry.day == date(2026, 10, 16))
        #expect(entry.minute == 18 * 60)
        #expect(entry.listID == fizyoloji.id)
        #expect(entry.rule == .none)
        #expect(entry.highlights == [
            Highlight(kind: .date, range: 0..<4),
            Highlight(kind: .list, range: 5..<14),
            Highlight(kind: .time, range: 21..<26),
        ])
    }

    @Test func tomorrow() {
        let entry = parser.parse("yarın annemi ara", now: now)
        #expect(entry.title == "Annemi ara")
        #expect(entry.day == date(2026, 10, 10))
        #expect(entry.minute == nil)
    }

    @Test func dayAfterTomorrow() {
        let entry = parser.parse("öbür gün rapor", now: now)
        #expect(entry.day == date(2026, 10, 11))
        #expect(entry.title == "Rapor")
    }

    @Test func plainTextHasNoDate() {
        let entry = parser.parse("süt al", now: now)
        #expect(entry.title == "Süt al")
        #expect(entry.day == nil)
        #expect(entry.minute == nil)
        #expect(entry.rule == .none)
        #expect(entry.highlights.isEmpty)
    }

    @Test func dailyRepeat() {
        let entry = parser.parse("her gün vitamin 21:00", now: now)
        #expect(entry.title == "Vitamin")
        #expect(entry.rule == .daily)
        #expect(entry.minute == 21 * 60)
        #expect(entry.day == date(2026, 10, 9))
    }

    @Test func weekdaysRepeat() {
        let entry = parser.parse("hafta içi her gün spor", now: now)
        #expect(entry.title == "Spor")
        #expect(entry.rule == RepeatRule(kind: .weekly, weekdayMask: Weekday.weekdaysMask))
    }

    @Test func severalWeekdaysRepeat() {
        let entry = parser.parse("her salı ve perşembe lab raporu", now: now)
        #expect(entry.title == "Lab raporu")
        #expect(entry.rule == RepeatRule(kind: .weekly, weekdayMask: Weekday.bit(2) | Weekday.bit(4)))
    }

    @Test func commaSeparatedWeekdaysRepeat() {
        let entry = parser.parse("her pazartesi, çarşamba yüzme", now: now)
        #expect(entry.title == "Yüzme")
        #expect(entry.rule == RepeatRule(kind: .weekly, weekdayMask: Weekday.bit(1) | Weekday.bit(3)))
    }

    @Test func monthlyRepeat() {
        let entry = parser.parse("her ay kira öde", now: now)
        #expect(entry.title == "Kira öde")
        #expect(entry.rule == RepeatRule(kind: .monthly))
        #expect(entry.day == date(2026, 10, 9))
    }

    @Test func dayAndMonthName() {
        let entry = parser.parse("15 ekim rapor teslim", now: now)
        #expect(entry.title == "Rapor teslim")
        #expect(entry.day == date(2026, 10, 15))
    }

    @Test func pastDayAndMonthRollsToNextYear() {
        let entry = parser.parse("3 mart sınav", now: now)
        #expect(entry.day == date(2027, 3, 3))
    }

    @Test func invalidDayAndMonthIsNotADate() {
        let entry = parser.parse("31 nisan sınav", now: now)
        #expect(entry.day == nil)
        #expect(entry.title == "31 nisan sınav")
    }

    @Test func slashDate() {
        let entry = parser.parse("20/11 toplantı", now: now)
        #expect(entry.day == date(2026, 11, 20))
        #expect(entry.title == "Toplantı")
    }

    @Test func nextWeekWeekday() {
        let entry = parser.parse("haftaya salı kimya", now: now)
        #expect(entry.day == date(2026, 10, 13))
        #expect(entry.title == "Kimya")
    }

    @Test func nextWeekAlone() {
        let entry = parser.parse("haftaya rapor", now: now)
        #expect(entry.day == date(2026, 10, 16))
    }

    @Test func timeWithSuffixTodayWhenStillAhead() {
        let entry = parser.parse("18:30'da diş hekimi", now: now)
        #expect(entry.minute == 18 * 60 + 30)
        #expect(entry.day == date(2026, 10, 9))
        #expect(entry.title == "Diş hekimi")
    }

    @Test func timeAlreadyPassedMeansTomorrow() {
        let entry = parser.parse("09:00 toplantı", now: now)
        #expect(entry.minute == 9 * 60)
        #expect(entry.day == date(2026, 10, 10))
    }

    @Test func spokenHour() {
        let entry = parser.parse("saat 18 anne", now: now)
        #expect(entry.minute == 18 * 60)
        #expect(entry.title == "Anne")
    }

    @Test func dotSeparatedTime() {
        let entry = parser.parse("yarın 8.30 yürüyüş", now: now)
        #expect(entry.minute == 8 * 60 + 30)
        #expect(entry.title == "Yürüyüş")
    }

    @Test func weekdayDayWordIsConsumed() {
        let entry = parser.parse("cuma günü rapor", now: now)
        #expect(entry.title == "Rapor")
        #expect(entry.day == date(2026, 10, 16))
    }

    @Test func trailingCommaOnDate() {
        let entry = parser.parse("cuma, rapor", now: now)
        #expect(entry.title == "Rapor")
        #expect(entry.day == date(2026, 10, 16))
    }

    @Test func wordsStartingLikeAWeekdayAreNotDates() {
        let entry = parser.parse("pazarlama sunumu", now: now)
        #expect(entry.day == nil)
        #expect(entry.title == "Pazarlama sunumu")
    }

    @Test func suffixedWeekday() {
        let entry = parser.parse("cumaya kadar rapor", now: now)
        #expect(entry.day == date(2026, 10, 16))
        #expect(entry.title == "Rapor")
    }

    @Test func listMatchedThroughSuffix() {
        let entry = parser.parse("fizyolojiden not al", now: now, lists: [fizyoloji, anatomi])
        #expect(entry.listID == fizyoloji.id)
    }

    @Test func listMatchedByMultiWordName() {
        let list = ListRef(id: UUID(), name: "Tıbbi Görüntüleme Giriş")
        let entry = parser.parse("görüntüleme raporu yarın", now: now, lists: [list])
        #expect(entry.listID == list.id)
    }

    @Test func noListWhenNothingMatches() {
        let entry = parser.parse("annemi ara", now: now, lists: [fizyoloji, anatomi])
        #expect(entry.listID == nil)
    }

    @Test func turkishCapitalLetters() {
        let entry = parser.parse("istanbul'a bilet al", now: now)
        #expect(entry.title == "İstanbul'a bilet al")
    }

    @Test func onlyADateLeavesAnEmptyTitle() {
        let entry = parser.parse("yarın", now: now)
        #expect(entry.title.isEmpty)
        #expect(entry.day == date(2026, 10, 10))
    }
}
