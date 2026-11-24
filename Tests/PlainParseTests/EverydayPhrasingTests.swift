import Foundation
import Testing
@testable import PlainParse

/// The way people actually type: endings split off, ranges, afternoons, numbers in words, "in ten minutes".
/// Now: Friday 9 October 2026, 11:06.
struct EverydayPhrasingTests {
    let tr = QuickAddParser(calendar: calendar, preferredLanguage: .turkish, slashDateDayFirst: true)
    let en = QuickAddParser(calendar: calendar, preferredLanguage: .english, slashDateDayFirst: false)

    @Test func endingTypedApart() {
        let entry = tr.parse("18 de spor", now: now)
        #expect(entry.minute == 18 * 60)
        #expect(entry.title == "Spor")
        let morning = tr.parse("sabah 6 da uyan", now: now)
        #expect(morning.minute == 6 * 60)
        #expect(morning.title == "Uyan")
        #expect(tr.parse("yarın 09 da servis", now: now).minute == 9 * 60)
        #expect(tr.parse("3 te toplantı", now: now).minute == 15 * 60)
    }

    @Test func aRangeKeepsItsStart() {
        let joined = tr.parse("13:00-15:00 ders", now: now)
        #expect(joined.minute == 13 * 60)
        #expect(joined.title == "Ders")
        let spaced = tr.parse("13:00 - 15:00 ders", now: now)
        #expect(spaced.minute == 13 * 60)
        #expect(spaced.title == "Ders")
        let words = tr.parse("saat 3 ile 5 arası ders", now: now)
        #expect(words.minute == 15 * 60)
        #expect(words.title == "Ders")
        let bare = tr.parse("3 ile 5 arası ders", now: now)
        #expect(bare.minute == 15 * 60)
        #expect(bare.title == "Ders")
        #expect(tr.parse("3-5 arası ders", now: now).minute == 15 * 60)
        #expect(en.parse("meeting 3pm to 5pm", now: now).minute == 15 * 60)
        #expect(en.parse("meeting 3pm to 5pm", now: now).title == "Meeting")
    }

    @Test func aRangeKeepsItsEnd() {
        func check(_ text: String, _ start: Int?, _ end: Int?, _ title: String, parser: QuickAddParser? = nil) {
            let entry = (parser ?? tr).parse(text, now: now)
            #expect(entry.minute == start, "\(text) start")
            #expect(entry.endMinute == end, "\(text) end")
            #expect(entry.title == title, "\(text) title")
        }
        check("saat 3:00 ile 5:00 arası ders", 15 * 60, 17 * 60, "Ders")
        check("10:00-1:30 atölye", 10 * 60, 13 * 60 + 30, "Atölye")
        check("13:00-15:00 arası toplantı", 13 * 60, 15 * 60, "Toplantı")
        // The ways a phone keyboard writes it.
        for text in ["bugün 20:00 21:30 deneme", "bugün 20:00 -21:30 deneme", "bugün 20:00- 21:30 deneme",
                     "bugün 20:00—21:30 deneme", "bugün 20:00 — 21:30 deneme", "bugün 20:00−21:30 deneme"] {
            check(text, 20 * 60, 21 * 60 + 30, "Deneme")
        }
        // Night shifts: no end (it would be the next day), never a made-up 20:00–21:00.
        check("nöbet 20:00-09:00", 20 * 60, nil, "Nöbet")
        check("nöbet 21:00-10:00", 21 * 60, nil, "Nöbet")
        check("20-9 arası nöbet", 20 * 60, nil, "Nöbet")
        check("10:00-1:30 arası atölye", 10 * 60, 13 * 60 + 30, "Atölye")
        check("13:00-15:00 ders", 13 * 60, 15 * 60, "Ders")
        check("13:00 - 15:00 ders", 13 * 60, 15 * 60, "Ders")
        check("saat 3 ile 5 arası ders", 15 * 60, 17 * 60, "Ders")
        check("3 ile 5 arası ders", 15 * 60, 17 * 60, "Ders")
        check("3-5 arası ders", 15 * 60, 17 * 60, "Ders")
        check("9-12 arası seminer", 9 * 60, 12 * 60, "Seminer")
        check("11 ile 1 arası ders", 11 * 60, 13 * 60, "Ders")
        check("22:00-01:00 nöbet", 22 * 60, nil, "Nöbet")
        check("14:00 toplantı", 14 * 60, nil, "Toplantı")
        check("meeting 3pm to 5pm", 15 * 60, 17 * 60, "Meeting", parser: en)
        check("meeting 14:00 - 16:30", 14 * 60, 16 * 60 + 30, "Meeting", parser: en)
        check("meeting at 3pm", 15 * 60, nil, "Meeting", parser: en)
        let tomorrow = tr.parse("yarın 14:00-16:00 toplantı", now: now)
        #expect(tomorrow.day != nil)
        #expect(tomorrow.minute == 14 * 60)
        #expect(tomorrow.endMinute == 16 * 60)
        #expect(tomorrow.title == "Toplantı")
        #expect(tr.parse("10 dakika sonra çayı kapat", now: now).endMinute == nil)
    }

    @Test func notARange() {
        // A score, a headcount, a dashed number: not hours.
        #expect(tr.parse("maç 3-1 bitti", now: now).minute == nil)
        let headcount = tr.parse("14:00 ile 15 kişi toplantı", now: now)
        #expect(headcount.minute == 14 * 60)
        #expect(headcount.title.hasSuffix("le 15 kişi toplantı"))
    }

    @Test func afternoonAndEvening() {
        let afternoon = tr.parse("yarın öğleden sonra kargo", now: now)
        #expect(afternoon.minute == 15 * 60)
        #expect(afternoon.title == "Kargo")
        #expect(tr.parse("öğleden sonra 3 te ders", now: now).minute == 15 * 60)
        #expect(tr.parse("akşama market", now: now).minute == 19 * 60)
        #expect(tr.parse("akşamüstü çay", now: now).minute == 17 * 60)
        // Lunch is a meal, not a time.
        #expect(tr.parse("öğle yemeği", now: now).minute == nil)
    }

    @Test func daysInWords() {
        #expect(tr.parse("iki gün sonra fatura", now: now).day == date(2026, 10, 11))
        #expect(tr.parse("iki gün sonra fatura", now: now).title == "Fatura")
        #expect(tr.parse("bir hafta sonra rapor", now: now).day == date(2026, 10, 16))
        #expect(en.parse("in two days pay rent", now: now).day == date(2026, 10, 11))
    }

    @Test func fromNow() {
        let tea = tr.parse("10 dakika sonra çayı kapat", now: now)
        #expect(tea.minute == 11 * 60 + 16)
        #expect(tea.day == date(2026, 10, 9))
        #expect(tea.title == "Çayı kapat")
        #expect(tr.parse("1 saat sonra ara", now: now).minute == 12 * 60 + 6)
        #expect(tr.parse("iki saat sonra ara", now: now).minute == 13 * 60 + 6)
        #expect(en.parse("call back in 20 minutes", now: now).minute == 11 * 60 + 26)
        // Past midnight it is tomorrow.
        let late = tr.parse("2 saat sonra uyu", now: date(2026, 10, 9, 23, 30))
        #expect(late.minute == 1 * 60 + 30)
        #expect(late.day == date(2026, 10, 10))
        // A length of time, not a time.
        #expect(tr.parse("1 saat yürüyüş", now: now).minute == nil)
    }

    @Test func dayOfThisMonth() {
        let rent = tr.parse("ayın 15'i kira", now: now)
        #expect(rent.day == date(2026, 10, 15))
        #expect(rent.title == "Kira")
        #expect(rent.rule == .none)
        #expect(tr.parse("ayın 5'inde fatura", now: now).day == date(2026, 11, 5))
    }
}

/// "2 haftada bir", "Haziran'da", "gelecek ay". Now: Friday 9 October 2026, 11:06.
struct EveryOtherWeekAndMonthTests {
    let tr = QuickAddParser(calendar: calendar, preferredLanguage: .turkish, slashDateDayFirst: true)
    let en = QuickAddParser(calendar: calendar, preferredLanguage: .english, slashDateDayFirst: false)

    @Test func everyOtherWeek() {
        let entry = tr.parse("2 haftada bir pazartesi lab", now: now)
        #expect(entry.rule.kind == .weekly)
        #expect(entry.rule.weekInterval == 2)
        #expect(entry.rule.weekdayMask == Weekday.bit(1))
        #expect(entry.title == "Lab")
        #expect(tr.parse("her iki haftada bir temizlik", now: now).rule.weekInterval == 2)
        #expect(tr.parse("iki haftada bir temizlik", now: now).rule.weekInterval == 2)
        #expect(tr.parse("her 3 hafta rapor", now: now).rule.weekInterval == 3)
        #expect(en.parse("every other week clean", now: now).rule.weekInterval == 2)
        #expect(en.parse("every 2 weeks clean", now: now).rule.weekInterval == 2)
        // A length of time, not a repeat.
        #expect(tr.parse("2 hafta tatil", now: now).rule == .none)
        #expect(tr.parse("2 hafta sonra rapor", now: now).day == date(2026, 10, 23))
    }

    /// "her hafta pazar" names the repeat's day; it used to be read as a one-off Sunday and a weekly repeat
    /// with no day, so the editor and the toast showed no day and "Pazar" could stay in the title.
    @Test func everyWeekThenAWeekday() {
        let timed = tr.parse("her hafta pazar saat 02:00 claude limit yenilenmesi", now: now)
        #expect(timed.rule.kind == .weekly)
        #expect(timed.rule.weekdayMask == Weekday.bit(7))
        #expect(timed.minute == 2 * 60)
        #expect(timed.title == "Claude limit yenilenmesi")
        let plain = tr.parse("her hafta pazar claude", now: now)
        #expect(plain.rule.weekdayMask == Weekday.bit(7))
        #expect(plain.title == "Claude")
        let two = tr.parse("her hafta salı ve perşembe spor", now: now)
        #expect(two.rule.weekdayMask == Weekday.bit(2) | Weekday.bit(4))
        #expect(two.title == "Spor")
        // Without a weekday it stays a plain weekly repeat.
        #expect(tr.parse("her hafta rapor", now: now).rule == RepeatRule(kind: .weekly))
    }

    /// "her sene 11 kasımda" used to become a one-off 11 November with "Her sene" left in the title.
    @Test func everyYear() {
        func check(_ text: String, _ day: Date?, _ title: String, parser: QuickAddParser? = nil) {
            let entry = (parser ?? tr).parse(text, now: now)
            #expect(entry.rule == RepeatRule(kind: .yearly), "\(text) rule")
            #expect(entry.day == day, "\(text) day")
            #expect(entry.title == title, "\(text) title")
        }
        check("her sene 11 kasımda doğum günü", date(2026, 11, 11), "Doğum günü")
        check("her yıl 11 kasım doğum günü", date(2026, 11, 11), "Doğum günü")
        check("her 11 kasımda doğum günü", date(2026, 11, 11), "Doğum günü")
        check("yılda bir 3 mart araba muayenesi", date(2027, 3, 3), "Araba muayenesi")
        check("senede bir 3 mart muayene", date(2027, 3, 3), "Muayene")
        // A date that has passed this year starts next year.
        check("her yıl 5 ekim evlilik yıl dönümü", date(2027, 10, 5), "Evlilik yıl dönümü")
        // No date: from today.
        check("her yıl sağlık kontrolü", date(2026, 10, 9), "Sağlık kontrolü")
        check("every year on november 11 birthday", date(2026, 11, 11), "Birthday", parser: en)
        check("every november 11 birthday", date(2026, 11, 11), "Birthday", parser: en)
        check("pay insurance yearly march 3", date(2027, 3, 3), "Pay insurance", parser: en)
        let timed = tr.parse("her sene 11 kasım saat 9 doğum günü", now: now)
        #expect(timed.minute == 9 * 60)
        // Not a repeat.
        #expect(tr.parse("yıllık izin planla", now: now).rule == .none)
        #expect(tr.parse("11 kasım doğum günü", now: now).rule == .none)
    }

    @Test func yearlyOccursOnItsDay() {
        let rule = RepeatRule(kind: .yearly)
        let start = date(2026, 11, 11)
        #expect(rule.occurs(on: date(2026, 11, 11), startingFrom: start, calendar: calendar))
        #expect(rule.occurs(on: date(2027, 11, 11), startingFrom: start, calendar: calendar))
        #expect(!rule.occurs(on: date(2026, 12, 11), startingFrom: start, calendar: calendar))
        #expect(!rule.occurs(on: date(2025, 11, 11), startingFrom: start, calendar: calendar))
        // 29 February: the 28th in other years.
        let leap = date(2028, 2, 29)
        #expect(rule.occurs(on: date(2029, 2, 28), startingFrom: leap, calendar: calendar))
        #expect(rule.occurs(on: date(2032, 2, 29), startingFrom: leap, calendar: calendar))
        #expect(!rule.occurs(on: date(2032, 2, 28), startingFrom: leap, calendar: calendar))
        #expect(RepeatKind(rawValue: "yearly") == .yearly)
    }

    @Test func everyOtherWeekSkipsAWeek() {
        let rule = RepeatRule(kind: .weekly, weekdayMask: Weekday.bit(1), weekInterval: 2)
        let start = date(2026, 10, 12)
        #expect(rule.occurs(on: date(2026, 10, 12), startingFrom: start, calendar: calendar))
        #expect(!rule.occurs(on: date(2026, 10, 19), startingFrom: start, calendar: calendar))
        #expect(rule.occurs(on: date(2026, 10, 26), startingFrom: start, calendar: calendar))
        // Started mid-week: the start day's week counts as week one.
        #expect(rule.occurs(on: date(2026, 10, 19), startingFrom: date(2026, 10, 14), calendar: calendar))
    }

    @Test func storedMaskKeepsTheWeekdaysReadable() {
        let rule = RepeatRule(kind: .weekly, weekdayMask: Weekday.bit(1) | Weekday.bit(3), weekInterval: 2)
        #expect(rule.storedMask & 0x7F == rule.weekdayMask)
        #expect(RepeatRule(kind: .weekly, storedMask: rule.storedMask) == rule)
        #expect(RepeatRule(kind: .weekly, storedMask: Weekday.weekdaysMask).weekInterval == 1)
    }

    @Test func aMonthOnItsOwn() {
        let june = tr.parse("Haziran'da tatil planı", now: now)
        #expect(june.day == date(2027, 6, 1))
        #expect(june.title == "Tatil planı")
        #expect(tr.parse("aralık ayında hediye al", now: now).day == date(2026, 12, 1))
        #expect(tr.parse("ekim ayında vize", now: now).day == date(2026, 10, 9))
        #expect(en.parse("trip in june", now: now).day == date(2027, 6, 1))
        // Everyday words that are also month names stay words.
        #expect(tr.parse("ocakta yemek var", now: now).day == nil)
        #expect(en.parse("may call bob", now: now).day == nil)
    }

    @Test func nextMonth() {
        let entry = tr.parse("gelecek ay vize", now: now)
        #expect(entry.day == date(2026, 11, 1))
        #expect(entry.title == "Vize")
        #expect(en.parse("dentist next month", now: now).day == date(2026, 11, 1))
    }
}
