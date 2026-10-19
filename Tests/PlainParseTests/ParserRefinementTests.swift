import Foundation
import Testing
@testable import PlainParse

/// Reference "now": Friday 9 October 2026, 11:06.
struct ParserRefinementTests {
    let tr = QuickAddParser(calendar: calendar, preferredLanguage: .turkish, slashDateDayFirst: true)
    let en = QuickAddParser(calendar: calendar, preferredLanguage: .english, slashDateDayFirst: false)
    let enDayFirst = QuickAddParser(calendar: calendar, preferredLanguage: .english, slashDateDayFirst: true)

    // MARK: 1. am/pm after a clock or an hour

    @Test func meridiemAfterSpacedHour() {
        let entry = en.parse("dinner at 6 pm", now: now)
        #expect(entry.minute == 18 * 60)
        #expect(entry.title == "Dinner")
    }

    @Test func meridiemAfterSpacedClock() {
        let entry = en.parse("dinner 6:30 pm", now: now)
        #expect(entry.minute == 18 * 60 + 30)
        #expect(entry.title == "Dinner")
        #expect(en.parse("dinner 7.30 pm", now: now).minute == 19 * 60 + 30)
        #expect(en.parse("dinner 7.30 pm", now: now).title == "Dinner")
        #expect(enDayFirst.parse("dinner 7.10 pm", now: now).minute == 19 * 60 + 10)
    }

    @Test func meridiemWithAtAndEdgeHours() {
        let entry = en.parse("call at 6:30 pm", now: now)
        #expect(entry.minute == 18 * 60 + 30)
        #expect(entry.title == "Call")
        #expect(en.parse("backup 12:15 am", now: now).minute == 15)
        #expect(en.parse("lunch 12 pm", now: now).minute == 12 * 60)
        #expect(en.parse("lunch 12 pm", now: now).title == "Lunch")
        #expect(en.parse("dinner at 6 p.m.", now: now).minute == 18 * 60)
        #expect(en.parse("dinner at 6 p.m.", now: now).title == "Dinner")
    }

    @Test func meridiemHighlightCoversBothWords() {
        let entry = en.parse("dinner at 6 pm", now: now)
        #expect(entry.highlights == [Highlight(kind: .time, range: 7..<14)])
    }

    // MARK: 2. Turkish hour with locative suffix

    @Test func locativeHour() {
        let entry = tr.parse("yarın 18'de annemi ara", now: now)
        #expect(entry.minute == 18 * 60)
        #expect(entry.day == date(2026, 10, 10))
        #expect(entry.title == "Annemi ara")
        #expect(entry.highlights == [Highlight(kind: .date, range: 0..<5), Highlight(kind: .time, range: 6..<11)])
    }

    @Test func locativeHourWithRepeat() {
        let entry = tr.parse("her pazartesi 9'da spor", now: now)
        #expect(entry.minute == 9 * 60)
        #expect(entry.title == "Spor")
        #expect(entry.rule == RepeatRule(kind: .weekly, weekdayMask: Weekday.bit(1)))
    }

    @Test func locativeHourAloneAndTypographicApostrophe() {
        #expect(tr.parse("8'de koşu", now: now).minute == 8 * 60)
        #expect(tr.parse("8'de koşu", now: now).title == "Koşu")
        let entry = tr.parse("yarın 18’de annemi ara", now: now)
        #expect(entry.minute == 18 * 60)
        #expect(entry.title == "Annemi ara")
        #expect(en.parse("yarın 18'de annemi ara", now: now).minute == 18 * 60)
    }

    @Test func plainNumbersAreNotHours() {
        let entry = tr.parse("3 elma al", now: now)
        #expect(entry.minute == nil)
        #expect(entry.title == "3 elma al")
        #expect(en.parse("buy 3 apples", now: now).minute == nil)
    }

    // MARK: 3. Dotted numbers, explicit years, leap day

    @Test func dottedPairIsADateInDayFirstLocales() {
        let entry = tr.parse("15.10 rapor", now: now)
        #expect(entry.day == date(2026, 10, 15))
        #expect(entry.minute == nil)
        #expect(entry.title == "Rapor")
        #expect(enDayFirst.parse("15.10 report", now: now).day == date(2026, 10, 15))
    }

    @Test func dottedPairStaysATimeWhenItLooksLikeOne() {
        let withSaat = tr.parse("saat 15.10 rapor", now: now)
        #expect(withSaat.minute == 15 * 60 + 10)
        #expect(withSaat.title == "Rapor")
        let evening = tr.parse("18.30 toplantı", now: now)
        #expect(evening.minute == 18 * 60 + 30)
        #expect(evening.title == "Toplantı")
        #expect(en.parse("at 15.10 report", now: now).minute == 15 * 60 + 10)
        // Month-first locales never read "15.10" as a date.
        #expect(en.parse("15.10 report", now: now).minute == 15 * 60 + 10)
    }

    @Test func dottedPairWithAnotherDateIsATime() {
        let entry = tr.parse("8.10 yarın yürüyüş", now: now)
        #expect(entry.day == date(2026, 10, 10))
        #expect(entry.minute == 8 * 60 + 10)
    }

    @Test func priceLikeNumberIsNotADate() {
        let entry = tr.parse("çay 3.50", now: now)
        #expect(entry.day != date(2027, 3, 5))
        // Existing behaviour: a dotted pair with minutes 13-59 is read as a time.
        #expect(entry.minute == 3 * 60 + 50)
        #expect(tr.parse("çay 3.5 litre", now: now).minute == nil)
    }

    @Test func fullDottedDates() {
        #expect(tr.parse("20.11.2026 toplantı", now: now).day == date(2026, 11, 20))
        #expect(tr.parse("20.11.2026 toplantı", now: now).title == "Toplantı")
        #expect(tr.parse("20.11.26 toplantı", now: now).day == date(2026, 11, 20))
        #expect(en.parse("11.20.2026 meeting", now: now).day == date(2026, 11, 20))
    }

    @Test func explicitYearIsHonoured() {
        let turkish = tr.parse("15 ekim 2028 rapor", now: now)
        #expect(turkish.day == date(2028, 10, 15))
        #expect(turkish.title == "Rapor")
        let english = en.parse("Oct 15 2028 dentist", now: now)
        #expect(english.day == date(2028, 10, 15))
        #expect(english.title == "Dentist")
        #expect(en.parse("october 15th, 2028 dentist", now: now).day == date(2028, 10, 15))
        #expect(en.parse("15 october 2028 dentist", now: now).title == "Dentist")
    }

    @Test func leapDayRollsToTheNextLeapYear() {
        let turkish = tr.parse("29 şubat doğum günü", now: now)
        #expect(turkish.day == date(2028, 2, 29))
        #expect(turkish.title == "Doğum günü")
        #expect(en.parse("feb 29 party", now: now).day == date(2028, 2, 29))
        // Without a valid occurrence anywhere it is still not a date.
        #expect(tr.parse("29 şubat 2027 doğum günü", now: now).day == nil)
    }

    // MARK: 4. "pazar" (market) versus Sunday

    @Test func marketIsNotSunday() {
        #expect(tr.parse("pazardan sebze al", now: now).day == nil)
        #expect(tr.parse("pazardan sebze al", now: now).title == "Pazardan sebze al")
        #expect(tr.parse("pazara git", now: now).day == nil)
        #expect(tr.parse("pazarda buluş", now: now).day == nil)
        #expect(tr.parse("pazarı gez", now: now).day == nil)
        #expect(tr.parse("pazar sebze al", now: now).day == nil)
    }

    @Test func sundayWithACue() {
        #expect(tr.parse("pazar günü sebze al", now: now).day == date(2026, 10, 11))
        #expect(tr.parse("pazar günü sebze al", now: now).title == "Sebze al")
        #expect(tr.parse("bu pazar kahvaltı", now: now).day == date(2026, 10, 11))
        #expect(tr.parse("haftaya pazar rapor", now: now).day == date(2026, 10, 18))
        let withTime = tr.parse("pazar 18:00 maç", now: now)
        #expect(withTime.day == date(2026, 10, 11))
        #expect(withTime.minute == 18 * 60)
        #expect(withTime.title == "Maç")
        #expect(tr.parse("her pazar koşu", now: now).rule == RepeatRule(kind: .weekly, weekdayMask: Weekday.bit(7)))
        #expect(en.parse("sunday brunch", now: now).day == date(2026, 10, 11))
    }

    // MARK: 5. Common phrasings

    @Test func thisWeekday() {
        let turkish = tr.parse("bu cuma rapor", now: now)
        #expect(turkish.day == date(2026, 10, 16))
        #expect(turkish.title == "Rapor")
        let english = en.parse("this friday dentist", now: now)
        #expect(english.day == date(2026, 10, 16))
        #expect(english.title == "Dentist")
        #expect(tr.parse("bu raporu yaz", now: now).title == "Bu raporu yaz")
        #expect(en.parse("this is a note", now: now).title == "This is a note")
    }

    @Test func standaloneWeekendIsTheComingSaturday() {
        let turkish = tr.parse("hafta sonu alışveriş", now: now)
        #expect(turkish.day == date(2026, 10, 10))
        #expect(turkish.rule == .none)
        #expect(turkish.title == "Alışveriş")
        #expect(tr.parse("bu hafta sonu alışveriş", now: now).day == date(2026, 10, 10))
        #expect(tr.parse("bu hafta sonu alışveriş", now: now).title == "Alışveriş")
        #expect(en.parse("weekend hike", now: now).day == date(2026, 10, 10))
        #expect(en.parse("this weekend hike", now: now).day == date(2026, 10, 10))
        #expect(en.parse("this weekend hike", now: now).title == "Hike")
        #expect(en.parse("weekend hike", now: now).rule == .none)
    }

    @Test func repeatingWeekendStaysARepeat() {
        let turkish = tr.parse("her hafta sonu koşu", now: now)
        #expect(turkish.rule == RepeatRule(kind: .weekly, weekdayMask: Weekday.weekendMask))
        #expect(turkish.title == "Koşu")
        #expect(en.parse("every weekend run", now: now).rule == RepeatRule(kind: .weekly, weekdayMask: Weekday.weekendMask))
    }

    @Test func relativeDates() {
        let days = tr.parse("3 gün sonra rapor", now: now)
        #expect(days.day == date(2026, 10, 12))
        #expect(days.title == "Rapor")
        #expect(tr.parse("2 hafta sonra rapor", now: now).day == date(2026, 10, 23))
        #expect(en.parse("in 3 days report", now: now).day == date(2026, 10, 12))
        #expect(en.parse("in 3 days report", now: now).title == "Report")
        #expect(en.parse("in 2 weeks report", now: now).day == date(2026, 10, 23))
        #expect(tr.parse("3 gün rapor", now: now).day == nil)
    }

    @Test func turkishDayParts() {
        // 11:06 now: morning 09:00 is behind us, so it means tomorrow.
        let morning = tr.parse("sabah koşu", now: now)
        #expect(morning.minute == 9 * 60)
        #expect(morning.day == date(2026, 10, 10))
        #expect(morning.title == "Koşu")
        #expect(tr.parse("öğlen toplantı", now: now).minute == 12 * 60)
        #expect(tr.parse("akşam annemi ara", now: now).minute == 19 * 60)
        let tonight = tr.parse("bu akşam annemi ara", now: now)
        #expect(tonight.minute == 19 * 60)
        #expect(tonight.day == date(2026, 10, 9))
        #expect(tonight.title == "Annemi ara")
        #expect(tr.parse("yarın akşam annemi ara", now: now).day == date(2026, 10, 10))
    }

    @Test func turkishDayPartWithHour() {
        #expect(tr.parse("akşam 8 yürüyüş", now: now).minute == 20 * 60)
        #expect(tr.parse("akşam 8 yürüyüş", now: now).title == "Yürüyüş")
        #expect(tr.parse("sabah 9 toplantı", now: now).minute == 9 * 60)
        #expect(tr.parse("gece 11 uyku", now: now).minute == 23 * 60)
        #expect(tr.parse("akşam saat 8 yürüyüş", now: now).minute == 20 * 60)
        #expect(tr.parse("yarın akşam 8'de yürüyüş", now: now).minute == 20 * 60)
    }

    @Test func dayPartNounsStayInTheTitle() {
        let entry = tr.parse("akşam yemeği hazırla", now: now)
        #expect(entry.minute == nil)
        #expect(entry.title == "Akşam yemeği hazırla")
    }

    @Test func explicitClockBeatsDayPart() {
        let entry = tr.parse("yarın sabah 07:30 koşu", now: now)
        #expect(entry.minute == 7 * 60 + 30)
        #expect(entry.title == "Koşu")
        let english = en.parse("tomorrow morning 7:30am run", now: now)
        #expect(english.minute == 7 * 60 + 30)
        #expect(english.title == "Run")
    }

    @Test func englishDayParts() {
        let tonight = en.parse("tonight movie", now: now)
        #expect(tonight.day == date(2026, 10, 9))
        #expect(tonight.minute == 20 * 60)
        #expect(tonight.title == "Movie")
        let morning = en.parse("tomorrow morning gym", now: now)
        #expect(morning.day == date(2026, 10, 10))
        #expect(morning.minute == 9 * 60)
        #expect(morning.title == "Gym")
        #expect(en.parse("tomorrow evening dinner", now: now).minute == 18 * 60)
        #expect(en.parse("noon lunch", now: now).minute == 12 * 60)
        #expect(en.parse("midnight snack", now: now).minute == 0)
        #expect(en.parse("tonight at 9 movie", now: now).minute == 21 * 60)
        #expect(en.parse("tomorrow evening at 7 dinner", now: now).minute == 19 * 60)
    }

    // MARK: 6. Bare hours after "at"/"saat"

    @Test func bareHoursOneToSixMeanAfternoon() {
        let english = en.parse("call dentist at 3", now: now)
        #expect(english.minute == 15 * 60)
        #expect(english.title == "Call dentist")
        #expect(tr.parse("saat 3 toplantı", now: now).minute == 15 * 60)
        #expect(tr.parse("saat 3 toplantı", now: now).title == "Toplantı")
        #expect(en.parse("call at 3:30", now: now).minute == 15 * 60 + 30)
        #expect(tr.parse("saat 5'te toplantı", now: now).minute == 17 * 60)
    }

    @Test func otherBareHoursStayLiteral() {
        #expect(en.parse("call at 7", now: now).minute == 7 * 60)
        #expect(en.parse("call at 11", now: now).minute == 11 * 60)
        #expect(en.parse("call at 12", now: now).minute == 12 * 60)
        #expect(tr.parse("saat 9 toplantı", now: now).minute == 9 * 60)
        #expect(tr.parse("saat 18 toplantı", now: now).minute == 18 * 60)
    }

    @Test func literalFormsAreNotShifted() {
        #expect(en.parse("call at 03:00", now: now).minute == 3 * 60)
        #expect(tr.parse("saat 03:00 toplantı", now: now).minute == 3 * 60)
        #expect(en.parse("standup 3:30", now: now).minute == 3 * 60 + 30)
        #expect(tr.parse("3:30 toplantı", now: now).minute == 3 * 60 + 30)
        #expect(en.parse("call at 3pm", now: now).minute == 15 * 60)
        #expect(tr.parse("3'te toplantı", now: now).minute == 3 * 60)
    }

    // MARK: 7. Capitalisation

    @Test func englishWordOnTurkishDeviceIsNotTurkishCased() {
        #expect(tr.parse("invoice send", now: now).title == "Invoice send")
        #expect(tr.parse("iphone case", now: now).title == "Iphone case")
    }

    @Test func turkishTextKeepsTurkishCasing() {
        #expect(tr.parse("istanbul'a bilet al", now: now).title == "İstanbul'a bilet al")
        #expect(tr.parse("ilaç al", now: now).title == "İlaç al")
        #expect(tr.parse("yarın internet faturası", now: now).title == "İnternet faturası")
        #expect(en.parse("ilaç al", now: now).title == "İlaç al")
        #expect(en.parse("iphone case", now: now).title == "Iphone case")
    }

    // MARK: "her sabah" and "8de"

    @Test func everyMorningIsDailyAtThatHour() {
        let entry = tr.parse("Her sabah 8de", now: now)
        #expect(entry.rule == .daily)
        #expect(entry.minute == 8 * 60)
        #expect(entry.day == date(2026, 10, 9))
    }

    @Test func everyMorningWithoutAnHourUsesTheDefault() {
        let entry = tr.parse("her sabah koşu", now: now)
        #expect(entry.rule == .daily)
        #expect(entry.minute == 9 * 60)
        #expect(entry.title == "Koşu")
    }

    @Test func everyEveningHourIsTheEvening() {
        let entry = tr.parse("her akşam 8 yürüyüş", now: now)
        #expect(entry.rule == .daily)
        #expect(entry.minute == 20 * 60)
        #expect(entry.title == "Yürüyüş")
    }

    @Test func everyNightHasNoTimeButLeavesTheTitle() {
        let entry = tr.parse("her gece vitamin", now: now)
        #expect(entry.rule == .daily)
        #expect(entry.minute == nil)
        #expect(entry.title == "Vitamin")
    }

    @Test func everyMorningInEnglish() {
        let entry = en.parse("every morning run", now: now)
        #expect(entry.rule == .daily)
        #expect(entry.minute == 9 * 60)
        #expect(entry.title == "Run")
    }

    @Test func everyDinnerNounIsNotARepeat() {
        let entry = tr.parse("her akşam yemeği hazırla", now: now)
        #expect(entry.rule == .none)
    }

    @Test func hourWithSuffixButNoApostrophe() {
        #expect(tr.parse("yarın 8de koşu", now: now).minute == 8 * 60)
        #expect(tr.parse("yarın 18de annemi ara", now: now).minute == 18 * 60)
        #expect(tr.parse("akşam 8de yürüyüş", now: now).minute == 20 * 60)
        #expect(tr.parse("yarın 5te toplantı", now: now).minute == tr.parse("yarın 5'te toplantı", now: now).minute)
    }

    @Test func aNumberWithAnotherEndingIsNotAnHour() {
        #expect(tr.parse("3kg elma al", now: now).minute == nil)
        #expect(tr.parse("2adet süt", now: now).minute == nil)
    }

    // MARK: Pre-release audit

    @Test func thisEveningLateIsStillToday() {
        let late = date(2026, 10, 9, 19, 30)
        #expect(tr.parse("bu akşam annemi ara", now: late).day == date(2026, 10, 9))
        #expect(tr.parse("akşam annemi ara", now: late).day == date(2026, 10, 9))
        #expect(en.parse("this evening call mom", now: date(2026, 10, 9, 18, 30)).day == date(2026, 10, 9))
        // An explicit hour that has passed still means tomorrow.
        #expect(tr.parse("akşam 7 annemi ara", now: date(2026, 10, 9, 21, 0)).day == date(2026, 10, 10))
    }

    @Test func tonightHasADayAndLeavesTheTitle() {
        let entry = tr.parse("bu gece film", now: now)
        #expect(entry.day == date(2026, 10, 9))
        #expect(entry.title == "Film")
    }

    @Test func dottedPairJustPastIsATime() {
        let entry = tr.parse("15.10 toplantı", now: date(2026, 10, 16, 9, 0))
        #expect(entry.minute == 15 * 60 + 10)
        #expect(entry.title == "Toplantı")
        // Still a date when it is near.
        #expect(tr.parse("20.10 toplantı", now: date(2026, 10, 16, 9, 0)).day == date(2026, 10, 20))
    }

    @Test func weekdaysJoinedAreAWeeklyRepeat() {
        let entry = tr.parse("pazartesi ve perşembe 18:00 spor", now: now)
        #expect(entry.rule == RepeatRule(kind: .weekly, weekdayMask: Weekday.bit(1) | Weekday.bit(4)))
        #expect(entry.minute == 18 * 60)
        #expect(entry.title == "Spor")
        // One weekday alone stays a one-off.
        #expect(tr.parse("pazartesi spor", now: now).rule == .none)
    }

    @Test func monthlyByDayOfMonth() {
        let rent = tr.parse("her ayın 1'i kira", now: date(2026, 10, 16, 9, 0))
        #expect(rent.rule == RepeatRule(kind: .monthly))
        #expect(rent.day == date(2026, 11, 1))
        #expect(rent.title == "Kira")
        let bill = tr.parse("her ay 20'sinde fatura", now: date(2026, 10, 16, 9, 0))
        #expect(bill.day == date(2026, 10, 20))
        #expect(bill.title == "Fatura")
        let english = en.parse("every month on the 1st pay rent", now: date(2026, 10, 16, 9, 0))
        #expect(english.rule == RepeatRule(kind: .monthly))
        #expect(english.day == date(2026, 11, 1))
        #expect(english.title == "Pay rent")
    }

    @Test func atNoonLeavesNoAt() {
        let entry = en.parse("lunch at noon", now: now)
        #expect(entry.title == "Lunch")
        #expect(entry.minute == 12 * 60)
    }
}
