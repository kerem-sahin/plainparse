import Foundation
import Testing
@testable import PlannerCore

/// Hours written as words: "saat sekizde", "on ikide", "dokuz buçukta", "at eight thirty".
/// Now: Friday 9 October 2026, 11:06.
struct WrittenHourTests {
    let tr = QuickAddParser(calendar: calendar, preferredLanguage: .turkish, slashDateDayFirst: true)
    let en = QuickAddParser(calendar: calendar, preferredLanguage: .english, slashDateDayFirst: false)

    @Test func saatSekizde() {
        let entry = tr.parse("yarın saat sekizde koşu", now: now)
        #expect(entry.minute == 8 * 60)
        #expect(entry.title == "Koşu")
        #expect(entry.day == date(2026, 10, 10))
    }

    @Test func endingAloneIsEnough() {
        #expect(tr.parse("sekizde koşu", now: now).minute == 8 * 60)
        #expect(tr.parse("sekizde koşu", now: now).title == "Koşu")
        #expect(tr.parse("dokuza toplantı koy", now: now).minute == 9 * 60)
        #expect(tr.parse("yedide kalk", now: now).minute == 7 * 60)
        #expect(tr.parse("dörtte çay", now: now).minute == 4 * 60)
        #expect(tr.parse("dörde kadar rapor", now: now).minute == 4 * 60)
    }

    @Test func twoWordHours() {
        #expect(tr.parse("on ikide öğle yemeği", now: now).minute == 12 * 60)
        #expect(tr.parse("on birde ders", now: now).minute == 11 * 60)
        #expect(tr.parse("on sekizde spor", now: now).minute == 18 * 60)
        #expect(tr.parse("yirmi birde dizi", now: now).minute == 21 * 60)
        #expect(tr.parse("on ikide öğle yemeği", now: now).title == "Öğle yemeği")
    }

    @Test func dayPartShiftsAWrittenHour() {
        #expect(tr.parse("akşam sekizde yürüyüş", now: now).minute == 20 * 60)
        #expect(tr.parse("sabah yedide kalk", now: now).minute == 7 * 60)
        #expect(tr.parse("akşam sekizde yürüyüş", now: now).title == "Yürüyüş")
    }

    @Test func saatBeforeAnAfternoonHour() {
        #expect(tr.parse("saat ikide toplantı", now: now).minute == 14 * 60)
        #expect(tr.parse("saat beş toplantı", now: now).minute == 17 * 60)
    }

    @Test func halfPast() {
        #expect(tr.parse("dokuz buçukta ders", now: now).minute == 9 * 60 + 30)
        #expect(tr.parse("saat sekiz buçuk servis", now: now).minute == 8 * 60 + 30)
        #expect(tr.parse("8 buçukta servis", now: now).minute == 8 * 60 + 30)
        #expect(tr.parse("akşam yedi buçukta sinema", now: now).minute == 19 * 60 + 30)
        #expect(tr.parse("dokuz buçukta ders", now: now).title == "Ders")
    }

    @Test func everydayWordsStayInTheTitle() {
        // "birde" (also), "onda" (with him), "ikide bir" (now and then), a bare number or "buçuk" are not times.
        #expect(tr.parse("birde süt al", now: now).minute == nil)
        #expect(tr.parse("kitap onda kalsın", now: now).minute == nil)
        #expect(tr.parse("ikide bir su iç", now: now).minute == nil)
        #expect(tr.parse("sekiz bardak su iç", now: now).minute == nil)
        #expect(tr.parse("iki buçuk kilo elma al", now: now).minute == nil)
        #expect(tr.parse("2 buçuk kilo elma al", now: now).minute == nil)
        #expect(tr.parse("birde süt al", now: now).title == "Birde süt al")
    }

    @Test func cueMakesEverydayWordsAnHour() {
        #expect(tr.parse("saat birde yemek", now: now).minute == 13 * 60)
        #expect(tr.parse("saat onda toplantı", now: now).minute == 10 * 60)
    }

    @Test func english() {
        #expect(en.parse("call mom at eight", now: now).minute == 8 * 60)
        #expect(en.parse("call mom at eight", now: now).title == "Call mom")
        #expect(en.parse("dinner seven pm", now: now).minute == 19 * 60)
        #expect(en.parse("standup at nine thirty", now: now).minute == 9 * 60 + 30)
        #expect(en.parse("gym six o'clock", now: now).minute == 6 * 60)
        #expect(en.parse("buy eight eggs", now: now).minute == nil)
        #expect(en.parse("buy eight eggs", now: now).title == "Buy eight eggs")
    }
}
