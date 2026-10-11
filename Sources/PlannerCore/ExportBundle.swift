import Foundation

/// Everything a person has written down, in a plain format they can keep: JSON for a full backup,
/// CSV for opening the tasks in a spreadsheet. Days are written as "yyyy-MM-dd" so they read the same anywhere.
public struct ExportBundle: Codable, Equatable, Sendable {
    public var app: String
    public var version: Int
    public var exportedAt: Date
    public var lists: [ExportList]
    public var tasks: [ExportTask]

    public init(app: String = "Plainday", version: Int = 1, exportedAt: Date, lists: [ExportList], tasks: [ExportTask]) {
        self.app = app
        self.version = version
        self.exportedAt = exportedAt
        self.lists = lists
        self.tasks = tasks
    }
}

public struct ExportList: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var color: String
    public var sortOrder: Int
    public var slots: [ExportSlot]

    public init(id: String, name: String, color: String, sortOrder: Int, slots: [ExportSlot]) {
        self.id = id
        self.name = name
        self.color = color
        self.sortOrder = sortOrder
        self.slots = slots
    }
}

public struct ExportSlot: Codable, Equatable, Sendable {
    /// ISO weekday, 1 = Monday ... 7 = Sunday.
    public var weekday: Int
    public var startMinute: Int
    public var endMinute: Int
    public var place: String

    public init(weekday: Int, startMinute: Int, endMinute: Int, place: String) {
        self.weekday = weekday
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.place = place
    }
}

public struct ExportCompletion: Codable, Equatable, Sendable {
    public var day: String
    public var skipped: Bool

    public init(day: String, skipped: Bool) {
        self.day = day
        self.skipped = skipped
    }
}

public struct ExportStep: Codable, Equatable, Sendable {
    public var title: String
    public var done: Bool
    /// Ticked days of a repeating task's step, as "yyyy-MM-dd".
    public var doneDays: [String]

    public init(title: String, done: Bool, doneDays: [String]) {
        self.title = title
        self.done = done
        self.doneDays = doneDays
    }
}

public struct ExportTask: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var notes: String
    /// "yyyy-MM-dd", or nil for a task with no day.
    public var day: String?
    public var reminderMinute: Int?
    public var done: Bool
    public var completedAt: Date?
    public var repeatKind: String
    public var repeatWeekdays: [Int]
    public var listID: String?
    public var createdAt: Date
    public var completions: [ExportCompletion]
    /// Steps of the task, in order (absent in backups made before steps existed).
    public var steps: [ExportStep]?

    public init(
        id: String, title: String, notes: String, day: String?, reminderMinute: Int?, done: Bool,
        completedAt: Date?, repeatKind: String, repeatWeekdays: [Int], listID: String?,
        createdAt: Date, completions: [ExportCompletion], steps: [ExportStep]? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.day = day
        self.reminderMinute = reminderMinute
        self.done = done
        self.completedAt = completedAt
        self.repeatKind = repeatKind
        self.repeatWeekdays = repeatWeekdays
        self.listID = listID
        self.createdAt = createdAt
        self.completions = completions
        self.steps = steps
    }
}

public extension ExportBundle {
    /// "2026-10-16" for a calendar day, in that calendar's own time zone.
    static func dayString(_ day: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    static func decode(json: Data) throws -> ExportBundle {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ExportBundle.self, from: json)
    }

    /// One line per task, comma separated, fields quoted when they need it (RFC 4180).
    func csv() -> String {
        let names = Dictionary(lists.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        var rows = [["title", "list", "day", "time", "repeat", "done", "notes"]]
        // Steps go into the notes column as lines, so a spreadsheet keeps one row per task.
        for task in tasks {
            let time = task.reminderMinute.map { String(format: "%02d:%02d", $0 / 60, $0 % 60) } ?? ""
            var repeating = task.repeatKind == "none" ? "" : task.repeatKind
            if !task.repeatWeekdays.isEmpty { repeating += ":" + task.repeatWeekdays.map(String.init).joined(separator: ",") }
            rows.append([
                task.title,
                task.listID.flatMap { names[$0] } ?? "",
                task.day ?? "",
                time,
                repeating,
                task.done ? "yes" : "no",
                ([task.notes] + (task.steps ?? []).map { ($0.done ? "[x] " : "[ ] ") + $0.title })
                    .filter { !$0.isEmpty }.joined(separator: "\n"),
            ])
        }
        return rows.map { $0.map(Self.csvField).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    private static func csvField(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
