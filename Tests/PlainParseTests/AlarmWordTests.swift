import Foundation
import Testing
@testable import PlainParse

/// "alarm" in the bar: an alarm instead of a notification, only with a time. Now: Friday 9 October 2026, 11:06.
struct AlarmWordTests {
    let tr = QuickAddParser(calendar: calendar, preferredLanguage: .turkish, slashDateDayFirst: true)
    let en = QuickAddParser(calendar: calendar, preferredLanguage: .english, slashDateDayFirst: false)

    @Test func alarmNextToATime() {
        let entry = tr.parse("yarın 7:00 alarm koşu", now: now)
        #expect(entry.alarm)
        #expect(entry.minute == 7 * 60)
        #expect(entry.title == "Koşu")
        #expect(entry.highlights.contains { $0.kind == .alarm })
    }

    @Test func alarmAtEitherEnd() {
        let first = tr.parse("alarm diş randevusu 15:00", now: now)
        #expect(first.alarm)
        #expect(first.title == "Diş randevusu")
        let last = tr.parse("diş randevusu 15:00 alarmlı", now: now)
        #expect(last.alarm)
        #expect(last.title == "Diş randevusu")
        #expect(tr.parse("kalk 7'de alarm kur", now: now).title == "Kalk")
    }

    @Test func alarmWithARepeat() {
        let entry = tr.parse("her sabah 7de alarm vitamin", now: now)
        #expect(entry.alarm)
        #expect(entry.rule == .daily)
        #expect(entry.minute == 7 * 60)
        #expect(entry.title == "Vitamin")
    }

    @Test func noTimeNoAlarm() {
        let entry = tr.parse("alarm saati al", now: now)
        #expect(!entry.alarm)
        #expect(entry.title == "Alarm saati al")
    }

    @Test func alarmInTheMiddleOfASentenceIsATitle() {
        let entry = tr.parse("yeni alarm saati 18:00 bak", now: now)
        #expect(!entry.alarm)
        #expect(entry.title.contains("alarm"))
    }

    @Test func english() {
        let entry = en.parse("wake up at 7 am with an alarm", now: now)
        #expect(entry.alarm)
        #expect(entry.minute == 7 * 60)
        #expect(entry.title == "Wake up")
        #expect(en.parse("alarm dentist 3pm", now: now).alarm)
        #expect(!en.parse("buy an alarm clock", now: now).alarm)
    }

    @Test func plainTimeIsNotAnAlarm() {
        #expect(!tr.parse("yarın 7:00 koşu", now: now).alarm)
    }
}
