import Foundation
import Testing
@testable import PlannerCore

struct ExportBundleTests {
    private func sample() -> ExportBundle {
        let list = ExportList(
            id: "L1", name: "Okul", color: "mavi", sortOrder: 0,
            slots: [ExportSlot(weekday: 1, startMinute: 540, endMinute: 630, place: "A-101")]
        )
        let task = ExportTask(
            id: "T1", title: "Rapor, \"son\" hâli", notes: "satır 1\nsatır 2", day: "2026-10-16", reminderMinute: 18 * 60 + 5,
            done: false, completedAt: nil, repeatKind: "weekly", repeatWeekdays: [1, 3], listID: "L1",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000), completions: [ExportCompletion(day: "2026-10-12", skipped: false)]
        )
        return ExportBundle(exportedAt: Date(timeIntervalSince1970: 1_800_000_100), lists: [list], tasks: [task])
    }

    @Test func jsonRoundTrips() throws {
        let bundle = sample()
        let decoded = try ExportBundle.decode(json: bundle.json())
        #expect(decoded == bundle)
    }

    @Test func jsonKeepsTurkishLettersReadable() throws {
        let text = String(decoding: try sample().json(), as: UTF8.self)
        #expect(text.contains("hâli"))
        #expect(text.contains("\"version\" : 1"))
    }

    @Test func csvQuotesCommasQuotesAndNewlines() {
        let csv = sample().csv()
        #expect(csv.hasPrefix("title,list,day,time,repeat,done,notes\r\n"))
        #expect(csv.contains("\"Rapor, \"\"son\"\" hâli\""))
        #expect(csv.contains("\"satır 1\nsatır 2\""))
        #expect(csv.contains(",Okul,2026-10-16,18:05,weekly:1,3,no,") == false) // the repeat field holds a comma, so it must be quoted
        #expect(csv.contains("\"weekly:1,3\""))
    }

    @Test func csvOfNothingIsJustTheHeader() {
        let empty = ExportBundle(exportedAt: .now, lists: [], tasks: [])
        #expect(empty.csv() == "title,list,day,time,repeat,done,notes\r\n")
    }

    @Test func dayStringIsZeroPaddedAndZoneIndependentForTheGivenCalendar() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Pacific/Auckland")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 3, day: 5))!
        #expect(ExportBundle.dayString(day, calendar: calendar) == "2026-03-05")
    }
}
