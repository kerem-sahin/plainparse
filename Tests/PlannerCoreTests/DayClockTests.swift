import Foundation
import Testing
@testable import PlannerCore

struct DayClockTests {
    let morningClass = TimedItem(id: UUID(), title: "A", kind: .fixed, startMinute: 8 * 60 + 30, endMinute: 10 * 60 + 10)
    let afternoonClass = TimedItem(id: UUID(), title: "B", kind: .fixed, startMinute: 13 * 60 + 20, endMinute: 15 * 60)
    let evening = TimedItem(id: UUID(), title: "Ödev", kind: .task, startMinute: 18 * 60)

    var items: [TimedItem] { [afternoonClass, evening, morningClass] }

    @Test func upcomingBetweenClasses() {
        let next = DayClock.next(in: items, nowMinute: 11 * 60 + 6)
        #expect(next == .upcoming(afternoonClass, minutesUntil: 134))
    }

    @Test func ongoingClass() {
        let next = DayClock.next(in: items, nowMinute: 9 * 60)
        #expect(next == .ongoing(morningClass, minutesLeft: 70))
    }

    @Test func endOfAClassIsNotOngoing() {
        let next = DayClock.next(in: items, nowMinute: 10 * 60 + 10)
        #expect(next == .upcoming(afternoonClass, minutesUntil: 190))
    }

    @Test func timedTaskIsNextAfterTheClasses() {
        let next = DayClock.next(in: items, nowMinute: 16 * 60)
        #expect(next == .upcoming(evening, minutesUntil: 120))
    }

    @Test func nothingLeftToday() {
        #expect(DayClock.next(in: items, nowMinute: 19 * 60) == .none)
        #expect(DayClock.next(in: [], nowMinute: 9 * 60) == .none)
    }

    @Test func gapsOnlyBetweenFixedItems() {
        #expect(DayClock.gaps(between: items) == [(10 * 60 + 10)..<(13 * 60 + 20)])
    }

    @Test func backToBackItemsLeaveNoGap() {
        let first = TimedItem(id: UUID(), title: "1", kind: .fixed, startMinute: 600, endMinute: 645)
        let second = TimedItem(id: UUID(), title: "2", kind: .fixed, startMinute: 645, endMinute: 690)
        #expect(DayClock.gaps(between: [first, second]).isEmpty)
    }

    @Test func shortBreaksAreNotGaps() {
        let first = TimedItem(id: UUID(), title: "1", kind: .fixed, startMinute: 600, endMinute: 645)
        let second = TimedItem(id: UUID(), title: "2", kind: .fixed, startMinute: 655, endMinute: 700)
        #expect(DayClock.gaps(between: [first, second]).isEmpty)
    }
}
