import Foundation
import Testing
@testable import PlainParse

/// Phrases people really type that used to be misread or left in the title. Now: Friday 9 October 2026, 11:06.
struct GapFixTests {
    let tr = QuickAddParser(calendar: calendar, preferredLanguage: .turkish, slashDateDayFirst: true)
    let en = QuickAddParser(calendar: calendar, preferredLanguage: .english, slashDateDayFirst: false)

    /// `nil` for day, minute, end means "not understood"; `rule` defaults to a one-off.
    func check(_ text: String, title: String, day: Date? = nil, minute: Int? = nil, end: Int? = nil,
               rule: RepeatRule = .none, english: Bool = false, sourceLocation: SourceLocation = #_sourceLocation) {
        let entry = (english ? en : tr).parse(text, now: now)
        #expect(entry.title == title, "\(text) title", sourceLocation: sourceLocation)
        #expect(entry.rule == rule, "\(text) rule", sourceLocation: sourceLocation)
        if rule == .none || day != nil { #expect(entry.day == day, "\(text) day", sourceLocation: sourceLocation) }
        #expect(entry.minute == minute, "\(text) minute", sourceLocation: sourceLocation)
        #expect(entry.endMinute == end, "\(text) end", sourceLocation: sourceLocation)
    }

    func weekly(_ days: [Int], interval: Int = 1) -> RepeatRule {
        RepeatRule(kind: .weekly, weekdayMask: days.reduce(0) { $0 | Weekday.bit($1) }, weekInterval: interval)
    }

    // MARK: A. Plural weekdays

    @Test func pluralWeekdaysRepeatWeekly() {
        check("salıları ingilizce", title: "İngilizce", rule: weekly([2]))
        check("pazartesileri", title: "", rule: weekly([1]))
        check("pazarları 10da", title: "", minute: 10 * 60, rule: weekly([7]))
        check("hafta sonları kahvaltı", title: "Kahvaltı", rule: RepeatRule(kind: .weekly, weekdayMask: Weekday.weekendMask))
        check("cumartesi günleri halı saha", title: "Halı saha", rule: weekly([6]))
        check("pazar günleri", title: "", rule: weekly([7]))
        check("salı günleri 9da ders", title: "Ders", minute: 9 * 60, rule: weekly([2]))
        check("mondays standup", title: "Standup", rule: weekly([1]), english: true)
        check("on mondays gym", title: "Gym", rule: weekly([1]), english: true)
        check("weekends sleep in", title: "Sleep in", rule: RepeatRule(kind: .weekly, weekdayMask: Weekday.weekendMask), english: true)
        check("mondays and wednesdays gym", title: "Gym", rule: weekly([1, 3]), english: true)
        check("salıları ve cumaları spor", title: "Spor", rule: weekly([2, 5]))
    }

    @Test func pluralWeekdayNeedsReason() {
        // "pazarlar" are markets; "tues" is a singular name.
        check("pazarları gez", title: "Pazarları gez")
        check("pazar günü pazar alışverişi", title: "Pazar alışverişi", day: date(2026, 10, 11))
        check("tues meeting", title: "Meeting", day: date(2026, 10, 13), english: true)
    }

    @Test func weekdaysSideBySide() {
        check("pazartesi çarşamba cuma spor", title: "Spor", rule: weekly([1, 3, 5]))
        check("her pazartesi çarşamba cuma spor", title: "Spor", rule: weekly([1, 3, 5]))
        // Two names are not enough: the first is a date, the second stays.
        check("pazartesi çarşamba spor", title: "Çarşamba spor", day: date(2026, 10, 12))
    }

    @Test func everyOtherWeekday() {
        check("every other monday", title: "", rule: weekly([1], interval: 2), english: true)
        check("every second tuesday", title: "", rule: weekly([2], interval: 2), english: true)
        check("bi-weekly meeting", title: "Meeting", rule: weekly([], interval: 2), english: true)
        check("biweekly meeting", title: "Meeting", rule: weekly([], interval: 2), english: true)
    }

    // MARK: B. hergün

    @Test func joinedEveryDay() {
        check("hergün spor", title: "Spor", rule: .daily)
        check("hergun spor", title: "Spor", rule: .daily)
    }

    // MARK: C. Endings stuck to a time

    @Test func endingsOnClockTimes() {
        check("21:30da film", title: "Film", day: date(2026, 10, 9), minute: 21 * 60 + 30)
        check("9:30da toplantı", title: "Toplantı", day: date(2026, 10, 10), minute: 9 * 60 + 30)
        check("21.30da film", title: "Film", day: date(2026, 10, 9), minute: 21 * 60 + 30)
        check("14e randevu", title: "Randevu", day: date(2026, 10, 9), minute: 14 * 60)
        check("yarın saat 9a toplantı", title: "Toplantı", day: date(2026, 10, 10), minute: 9 * 60)
        check("cuma 9a toplantı", title: "Toplantı", day: date(2026, 10, 16), minute: 9 * 60)
        check("yarın 14:00 da toplantı", title: "Toplantı", day: date(2026, 10, 10), minute: 14 * 60)
    }

    @Test func directionEndingNeedsLateHour() {
        check("10a sınıfı ödev", title: "10a sınıfı ödev")
        check("3'e böl", title: "3'e böl")
        check("5'e kadar rapor", title: "5'e kadar rapor")
        check("yarın 10'a kadar rapor", title: "Rapor", day: date(2026, 10, 10), minute: 10 * 60)
    }

    // MARK: D. Clock words

    @Test func turkishClockWords() {
        check("dokuza çeyrek var", title: "", day: date(2026, 10, 10), minute: 8 * 60 + 45)
        check("beşe 10 var", title: "", day: date(2026, 10, 9), minute: 16 * 60 + 50)
        check("altıya on kala", title: "", day: date(2026, 10, 9), minute: 17 * 60 + 50)
        check("bire çeyrek var", title: "", day: date(2026, 10, 9), minute: 12 * 60 + 45)
        check("10u çeyrek geçe", title: "", day: date(2026, 10, 10), minute: 10 * 60 + 15)
        check("onu çeyrek geçe", title: "", day: date(2026, 10, 10), minute: 10 * 60 + 15)
        check("dokuzu çeyrek geçe", title: "", day: date(2026, 10, 10), minute: 9 * 60 + 15)
        check("10u 5 geçe", title: "", day: date(2026, 10, 10), minute: 10 * 60 + 5)
        check("9 u 15 geçe", title: "", day: date(2026, 10, 10), minute: 9 * 60 + 15)
        check("yarın dokuza çeyrek var toplantı", title: "Toplantı", day: date(2026, 10, 10), minute: 8 * 60 + 45)
    }

    @Test func englishClockWords() {
        check("quarter past 9", title: "", day: date(2026, 10, 10), minute: 9 * 60 + 15, english: true)
        check("quarter to 10", title: "", day: date(2026, 10, 10), minute: 9 * 60 + 45, english: true)
        check("half past 7", title: "", day: date(2026, 10, 10), minute: 7 * 60 + 30, english: true)
        check("call quarter past 3 pm", title: "Call", day: date(2026, 10, 9), minute: 15 * 60 + 15, english: true)
    }

    // MARK: E. Parts of the day

    @Test func noonAndMidnight() {
        check("öğlen", title: "", day: date(2026, 10, 9), minute: 12 * 60)
        check("öğleyin toplantı", title: "Toplantı", day: date(2026, 10, 9), minute: 12 * 60)
        check("öğle yemeği", title: "Öğle yemeği")
        check("gece yarısı", title: "", day: date(2026, 10, 10), minute: 0)
        check("midnight", title: "", day: date(2026, 10, 10), minute: 0, english: true)
        check("at midnight", title: "", day: date(2026, 10, 10), minute: 0, english: true)
        check("sabaha karşı 5te", title: "", day: date(2026, 10, 10), minute: 5 * 60)
    }

    @Test func possessiveDayParts() {
        check("cuma akşamı", title: "", day: date(2026, 10, 16), minute: 19 * 60)
        check("cuma gecesi", title: "", day: date(2026, 10, 16))
        check("cumartesi sabahı", title: "", day: date(2026, 10, 10), minute: 9 * 60)
        check("cuma akşamı 8de", title: "", day: date(2026, 10, 16), minute: 20 * 60)
    }

    @Test func mealWordHintsTheHour() {
        check("akşam yemeği 8de", title: "Akşam yemeği", day: date(2026, 10, 9), minute: 20 * 60)
        check("öğle yemeği 1de", title: "Öğle yemeği", day: date(2026, 10, 9), minute: 13 * 60)
        // A bare number is a count, not an hour.
        check("akşam yemeği 4 kişi", title: "Akşam yemeği 4 kişi")
    }

    // MARK: F. Words left in the title

    @Test func nextWeekWords() {
        check("önümüzdeki salı toplantı", title: "Toplantı", day: date(2026, 10, 13))
        check("önümüzdeki hafta salı", title: "", day: date(2026, 10, 13))
        check("önümüzdeki pazartesi 10da", title: "", day: date(2026, 10, 12), minute: 10 * 60)
        check("gelecek hafta cuma", title: "", day: date(2026, 10, 16))
        check("önümüzdeki hafta", title: "", day: date(2026, 10, 16))
        check("önümüzdeki hafta sonu", title: "", day: date(2026, 10, 17))
        check("next week tuesday", title: "", day: date(2026, 10, 13), english: true)
        check("tuesday next week", title: "", day: date(2026, 10, 13), english: true)
    }

    @Test func hedgesAndDeadlines() {
        check("saat 2 gibi ara", title: "Ara", day: date(2026, 10, 9), minute: 14 * 60)
        check("2ye doğru", title: "", day: date(2026, 10, 9), minute: 14 * 60)
        check("around 3pm call", title: "Call", day: date(2026, 10, 9), minute: 15 * 60, english: true)
        check("en geç yarın rapor", title: "Rapor", day: date(2026, 10, 10))
        check("en geç cuma", title: "", day: date(2026, 10, 16))
    }

    // MARK: G. Start bounds

    @Test func startBounds() {
        check("pazartesiden itibaren her gün spor", title: "Spor", day: date(2026, 10, 12), rule: .daily)
        check("yarından itibaren her gün", title: "", day: date(2026, 10, 10), rule: .daily)
        check("1 aralıktan itibaren diyet", title: "Diyet", day: date(2026, 12, 1))
        check("starting monday gym", title: "Gym", day: date(2026, 10, 12), english: true)
        check("from monday every day run", title: "Run", day: date(2026, 10, 12), rule: .daily, english: true)
        // "from" is a start only with a repeat.
        check("mail from monday", title: "Mail from", day: date(2026, 10, 12), english: true)
    }

    // MARK: H. Dates

    @Test func monthAndDay() {
        check("kasımın 15i sınav", title: "Sınav", day: date(2026, 11, 15))
        check("kasımın 15inde", title: "", day: date(2026, 11, 15))
        check("mayısın 5inde", title: "", day: date(2027, 5, 5))
        check("mayıs ayının 5i", title: "", day: date(2027, 5, 5))
        check("mayıs 5", title: "", day: date(2027, 5, 5))
        check("kasım 15 sınav", title: "Sınav", day: date(2026, 11, 15))
        check("mart 3 hafta tatil", title: "Mart 3 hafta tatil")
        check("kasımda 15 kişi", title: "Kasımda 15 kişi")
        check("15th of november", title: "", day: date(2026, 11, 15), english: true)
        check("exam on the 15th", title: "Exam", day: date(2026, 10, 15), english: true)
        check("the 3rd floor", title: "The 3rd floor", english: true)
        check("on the 15th", title: "", day: date(2026, 10, 15), english: true)
        check("3rd floor meeting", title: "3rd floor meeting", english: true)
    }

    @Test func endOfPeriod() {
        check("ay sonu rapor", title: "Rapor", day: date(2026, 10, 31))
        check("ayın sonunda", title: "", day: date(2026, 10, 31))
        check("ay sonuna kadar", title: "", day: date(2026, 10, 31))
        check("yıl sonu", title: "", day: date(2026, 12, 31))
        check("yıl sonuna kadar", title: "", day: date(2026, 12, 31))
        // The week ends on Sunday here, for both languages.
        check("hafta sonuna kadar", title: "", day: date(2026, 10, 11))
        check("end of month", title: "", day: date(2026, 10, 31), english: true)
        check("end of week", title: "", day: date(2026, 10, 11), english: true)
        check("end of year", title: "", day: date(2026, 12, 31), english: true)
        check("by end of month", title: "", day: date(2026, 10, 31), english: true)
        check("bu hafta içinde rapor", title: "Rapor", day: date(2026, 10, 11))
    }

    @Test func withinAndNamedDays() {
        check("10 gün içinde", title: "", day: date(2026, 10, 19))
        check("2 gün içinde", title: "", day: date(2026, 10, 11))
        check("bir hafta içinde", title: "", day: date(2026, 10, 16))
        check("bir ay içinde", title: "", day: date(2026, 11, 9))
        // The weekday of the week that starts two weeks from now's week: Tuesday 20 October.
        check("2 hafta sonra salı", title: "", day: date(2026, 10, 20))
        check("yılbaşında", title: "", day: date(2027, 1, 1))
        // A bare holiday name is a noun.
        check("yılbaşı hediyesi al", title: "Yılbaşı hediyesi al", day: nil)
        check("yılbaşı gecesi", title: "", day: date(2026, 12, 31))
        check("new year's eve", title: "", day: date(2026, 12, 31), english: true)
        check("on christmas", title: "", day: date(2026, 12, 25), english: true)
        check("christmas gifts", title: "Christmas gifts", day: nil, english: true)
        check("within 3 days", title: "", day: date(2026, 10, 12), english: true)
    }

    // MARK: I. Lengths and ranges

    @Test func durationIsTheEnd() {
        check("yarın 14:00 2 saat toplantı", title: "Toplantı", day: date(2026, 10, 10), minute: 14 * 60, end: 16 * 60)
        check("yarın 14:00 da 2 saatlik", title: "", day: date(2026, 10, 10), minute: 14 * 60, end: 16 * 60)
        check("meeting 2pm for 2 hours", title: "Meeting", day: date(2026, 10, 9), minute: 14 * 60, end: 16 * 60, english: true)
        check("45 dk toplantı 14:00", title: "Toplantı", day: date(2026, 10, 9), minute: 14 * 60, end: 14 * 60 + 45)
        check("14:00 45 dakikalık toplantı", title: "Toplantı", day: date(2026, 10, 9), minute: 14 * 60, end: 14 * 60 + 45)
    }

    @Test func durationNeedsAStart() {
        check("2 saat ders çalış", title: "2 saat ders çalış")
        check("45 dakikalık toplantı", title: "45 dakikalık toplantı")
        // Past midnight there is no end, and the words stay.
        check("22:00 3 saat nöbet", title: "3 saat nöbet", day: date(2026, 10, 9), minute: 22 * 60)
    }

    @Test func rangesWithFromAndTo() {
        check("yarın 2 den 4 e toplantı", title: "Toplantı", day: date(2026, 10, 10), minute: 14 * 60, end: 16 * 60)
        check("2 den 4 e kadar", title: "", day: date(2026, 10, 9), minute: 14 * 60, end: 16 * 60)
        check("14:00'den 16:00'ya toplantı", title: "Toplantı", day: date(2026, 10, 9), minute: 14 * 60, end: 16 * 60)
        check("meeting from 2 to 4", title: "Meeting", day: date(2026, 10, 9), minute: 14 * 60, end: 16 * 60, english: true)
        check("meeting 2-4pm", title: "Meeting", day: date(2026, 10, 9), minute: 14 * 60, end: 16 * 60, english: true)
        check("meeting 11-1pm", title: "Meeting", day: date(2026, 10, 10), minute: 11 * 60, end: 13 * 60, english: true)
    }

    // MARK: J and K. Monthly

    @Test func monthlyOnADay() {
        let monthly = RepeatRule(kind: .monthly)
        check("on the 15th of every month rent", title: "Rent", day: date(2026, 10, 15), rule: monthly, english: true)
        check("the 1st of every month", title: "", day: date(2026, 11, 1), rule: monthly, english: true)
        check("monthly rent on the 1st", title: "Rent", day: date(2026, 11, 1), rule: monthly, english: true)
        check("her ayın ilk günü kira", title: "Kira", day: date(2026, 11, 1), rule: monthly)
    }
}
