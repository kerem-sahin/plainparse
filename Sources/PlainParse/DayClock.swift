import Foundation

/// Something that sits at a time of day: a fixed-schedule slot (class, training, shift) or a timed task.
public struct TimedItem: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable { case fixed, task, event }

    public let id: UUID
    public let title: String
    public let kind: Kind
    public let startMinute: Int
    public let endMinute: Int?
    public let listID: UUID?
    public let place: String

    public init(id: UUID, title: String, kind: Kind, startMinute: Int, endMinute: Int? = nil, listID: UUID? = nil, place: String = "") {
        self.id = id
        self.title = title
        self.kind = kind
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.listID = listID
        self.place = place
    }
}

public enum NextUp: Equatable, Sendable {
    case ongoing(TimedItem, minutesLeft: Int)
    case upcoming(TimedItem, minutesUntil: Int)
    case none
}

public enum DayClock {
    /// What is happening now, or what comes next today.
    public static func next(in items: [TimedItem], nowMinute: Int) -> NextUp {
        let sorted = items.sorted { $0.startMinute < $1.startMinute }
        if let running = sorted.first(where: { item in
            guard let end = item.endMinute else { return false }
            return item.startMinute <= nowMinute && nowMinute < end
        }), let end = running.endMinute {
            return .ongoing(running, minutesLeft: end - nowMinute)
        }
        if let coming = sorted.first(where: { $0.startMinute > nowMinute }) {
            return .upcoming(coming, minutesUntil: coming.startMinute - nowMinute)
        }
        return .none
    }

    /// Free stretches between busy items: weekly fixed blocks and calendar events (back-to-back and overlapping merge).
    public static func gaps(between items: [TimedItem], minLength: Int = 20) -> [Range<Int>] {
        let blocks = items
            .filter { $0.kind == .fixed || $0.kind == .event }
            .compactMap { item in item.endMinute.map { item.startMinute..<$0 } }
            .sorted { $0.lowerBound < $1.lowerBound }
        guard var current = blocks.first else { return [] }
        var gaps: [Range<Int>] = []
        for block in blocks.dropFirst() {
            if block.lowerBound <= current.upperBound {
                current = current.lowerBound..<max(current.upperBound, block.upperBound)
            } else {
                if block.lowerBound - current.upperBound >= minLength {
                    gaps.append(current.upperBound..<block.lowerBound)
                }
                current = block
            }
        }
        return gaps
    }
}
