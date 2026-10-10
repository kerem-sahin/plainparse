import Foundation

public struct ListRef: Sendable, Equatable {
    public let id: UUID
    public let name: String

    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}

/// A recognised piece of the typed text, as character offsets into the original string.
public struct Highlight: Sendable, Equatable {
    public enum Kind: Sendable { case date, time, repeating, list }

    public var kind: Kind
    public var range: Range<Int>

    public init(kind: Kind, range: Range<Int>) {
        self.kind = kind
        self.range = range
    }
}

public struct ParsedEntry: Sendable, Equatable {
    public var title: String
    public var day: Date?
    public var minute: Int?
    public var rule: RepeatRule
    public var listID: UUID?
    public var highlights: [Highlight]
}

/// Turns one line such as "Cuma fizyoloji ödevi 18:00" or "friday math homework 6pm" into a task.
/// It tries the user's language first and the other one only if that understands more.
/// Weekday names always mean the next such day after today; saying "today" is explicit.
public struct QuickAddParser: Sendable {
    public var calendar: Calendar
    private let vocabularies: [Vocabulary]

    public init(calendar: Calendar = .current, preferredLanguage: ParserLanguage = .deviceDefault, slashDateDayFirst: Bool? = nil) {
        self.calendar = calendar
        let dayFirst = slashDateDayFirst ?? Vocabulary.localeWritesDayFirst(calendar.locale ?? .current)
        let turkish = Vocabulary.turkish
        let english = Vocabulary.english(slashDateDayFirst: dayFirst)
        self.vocabularies = preferredLanguage == .turkish ? [turkish, english] : [english, turkish]
    }

    private struct Token {
        var raw: String
        var folded: String
        var range: Range<Int>
    }

    public func parse(_ text: String, now: Date, lists: [ListRef] = []) -> ParsedEntry {
        var best: (entry: ParsedEntry, coverage: Int)?
        for vocabulary in vocabularies {
            let entry = parse(text, now: now, lists: lists, vocabulary: vocabulary)
            let coverage = entry.highlights
                .filter { $0.kind != .list }
                .reduce(0) { $0 + $1.range.count }
            if best == nil || coverage > best!.coverage {
                best = (entry, coverage)
            }
        }
        return best?.entry ?? parse(text, now: now, lists: lists, vocabulary: .turkish)
    }

    // MARK: One language

    private func parse(_ text: String, now: Date, lists: [ListRef], vocabulary v: Vocabulary) -> ParsedEntry {
        let tokens = Self.tokenize(text)
        var used = Set<Int>()
        var highlights: [Highlight] = []

        func consume(_ indices: ClosedRange<Int>, as kind: Highlight.Kind) {
            for index in indices { used.insert(index) }
            let lower = tokens[indices.lowerBound].range.lowerBound
            let upper = tokens[indices.upperBound].range.upperBound
            highlights.append(Highlight(kind: kind, range: lower..<upper))
        }
        func free(_ index: Int) -> Bool {
            index >= 0 && index < tokens.count && !used.contains(index)
        }
        func folded(_ index: Int) -> String? {
            free(index) ? tokens[index].folded : nil
        }
        /// Length of the first phrase in `phrases` that starts at `index`, if any.
        func phrase(_ phrases: [[String]], at index: Int) -> Int? {
            phrases.first { words in
                words.indices.allSatisfy { free(index + $0) && tokens[index + $0].folded == words[$0] }
            }?.count
        }

        let today = calendar.startOfDay(for: now)
        var rule = RepeatRule.none

        // Repeat phrases first: their weekday names must not be read as one-off dates.
        var i = 0
        while i < tokens.count {
            guard free(i) else { i += 1; continue }
            let word = tokens[i].folded

            if let length = phrase(v.weekdaysPhrases, at: i) {
                rule = RepeatRule(kind: .weekly, weekdayMask: Weekday.weekdaysMask)
                consume(i...(i + length - 1), as: .repeating)
                i += length
                continue
            }
            if let length = phrase(v.dailyAlone, at: i) {
                if rule.kind != .weekly { rule = .daily }
                consume(i...(i + length - 1), as: .repeating)
                i += length
                continue
            }
            if let length = phrase(v.weeklyAlone, at: i) {
                rule = RepeatRule(kind: .weekly)
                consume(i...(i + length - 1), as: .repeating)
                i += length
                continue
            }
            if let length = phrase(v.monthlyAlone, at: i) {
                rule = RepeatRule(kind: .monthly)
                consume(i...(i + length - 1), as: .repeating)
                i += length
                continue
            }

            if v.every.contains(word), free(i + 1) {
                let next = i + 1
                if let length = phrase(v.weekdaysPhrases, at: next) {
                    rule = RepeatRule(kind: .weekly, weekdayMask: Weekday.weekdaysMask)
                    consume(i...(next + length - 1), as: .repeating)
                    i = next + length
                    continue
                }
                if let length = phrase(v.weekendPhrases, at: next) {
                    rule = RepeatRule(kind: .weekly, weekdayMask: Weekday.weekendMask)
                    consume(i...(next + length - 1), as: .repeating)
                    i = next + length
                    continue
                }
                if v.dayWord.contains(tokens[next].folded) {
                    if rule.kind != .weekly { rule = .daily }
                    consume(i...next, as: .repeating)
                    i = next + 1
                    continue
                }
                if v.weekWord.contains(tokens[next].folded) {
                    rule = RepeatRule(kind: .weekly)
                    consume(i...next, as: .repeating)
                    i = next + 1
                    continue
                }
                if v.monthWord.contains(tokens[next].folded) {
                    rule = RepeatRule(kind: .monthly)
                    consume(i...next, as: .repeating)
                    i = next + 1
                    continue
                }
                if let first = Self.weekday(of: tokens[next].folded, v) {
                    var mask = Weekday.bit(first)
                    var last = next
                    var j = next + 1
                    while free(j) {
                        let previousEndsWithComma = tokens[j - 1].raw.hasSuffix(",")
                        if v.conjunctions.contains(tokens[j].folded), free(j + 1),
                           let day = Self.weekday(of: tokens[j + 1].folded, v) {
                            mask |= Weekday.bit(day)
                            last = j + 1
                            j += 2
                        } else if previousEndsWithComma, let day = Self.weekday(of: tokens[j].folded, v) {
                            mask |= Weekday.bit(day)
                            last = j
                            j += 1
                        } else {
                            break
                        }
                    }
                    if free(last + 1), v.weekdayMarkers.contains(tokens[last + 1].folded) {
                        last += 1
                    }
                    rule = RepeatRule(kind: .weekly, weekdayMask: mask)
                    consume(i...last, as: .repeating)
                    i = last + 1
                    continue
                }
            }
            i += 1
        }

        // The first date phrase wins.
        var day: Date?
        i = 0
        while i < tokens.count, day == nil {
            guard free(i) else { i += 1; continue }
            let word = tokens[i].folded

            /// Marks the date and a "by"/"until" word right before it.
            func consumeDate(_ range: ClosedRange<Int>) {
                var lower = range.lowerBound
                if free(lower - 1), v.deadlinePrefixWords.contains(tokens[lower - 1].folded) { lower -= 1 }
                consume(lower...range.upperBound, as: .date)
            }

            if v.todayWords.contains(word) {
                day = today
                consumeDate(i...i)
            } else if v.tomorrowWords.contains(word) {
                day = calendar.date(byAdding: .day, value: 1, to: today)
                consumeDate(i...i)
            } else if let length = phrase(v.dayAfterTomorrow, at: i) {
                day = calendar.date(byAdding: .day, value: 2, to: today)
                consumeDate(i...(i + length - 1))
            } else if v.nextPrefixes.contains(word) {
                if free(i + 1), let weekday = Self.weekday(of: tokens[i + 1].folded, v) {
                    day = dayInNextWeek(weekday, from: today)
                    consumeDate(i...(i + 1))
                } else if free(i + 1), v.weekWord.contains(tokens[i + 1].folded) {
                    day = calendar.date(byAdding: .day, value: 7, to: today)
                    consumeDate(i...(i + 1))
                } else if v.nextAloneMeansWeek {
                    day = calendar.date(byAdding: .day, value: 7, to: today)
                    consumeDate(i...i)
                }
            } else if let weekday = Self.weekday(of: word, v) {
                day = nextDay(weekday, after: today)
                var last = i
                if free(i + 1), v.weekdayMarkers.contains(tokens[i + 1].folded) { last = i + 1 }
                consumeDate(i...last)
            } else if let number = Self.dayNumber(word, v), free(i + 1),
                      let month = Self.month(of: tokens[i + 1].folded, v),
                      let date = makeDate(day: number, month: month, year: nil, today: today) {
                day = date
                consumeDate(i...(i + 1))
            } else if v.monthFirstAllowed, let month = Self.month(of: word, v), free(i + 1),
                      let number = Self.dayNumber(tokens[i + 1].folded, v),
                      let date = makeDate(day: number, month: month, year: nil, today: today) {
                day = date
                consumeDate(i...(i + 1))
            } else if let date = slashDate(word, dayFirst: v.slashDateDayFirst, today: today) {
                day = date
                consumeDate(i...i)
            }
            i += 1
        }

        var minute: Int?
        i = 0
        while i < tokens.count, minute == nil {
            guard free(i) else { i += 1; continue }
            let word = tokens[i].folded

            /// Marks the time and an "at"/"saat" word right before it.
            func consumeTime(_ range: ClosedRange<Int>) {
                var lower = range.lowerBound
                if free(lower - 1), v.timePrefixWords.contains(tokens[lower - 1].folded) { lower -= 1 }
                consume(lower...range.upperBound, as: .time)
            }

            let spokenMinute: Int? = {
                guard v.timePrefixWords.contains(word), free(i + 1) else { return nil }
                if let clock = Self.clock(tokens[i + 1].folded, v) { return clock }
                return Self.hourOnly(tokens[i + 1].folded).map { $0 * 60 }
            }()
            if let spokenMinute {
                minute = spokenMinute
                consume(i...(i + 1), as: .time)
            } else if let value = Self.clock(word, v) {
                minute = value
                consumeTime(i...i)
            } else if v.usesMeridiem, free(i + 1), let hour = Int(word), (1...12).contains(hour),
                      let meridiem = Self.meridiem(tokens[i + 1].folded) {
                minute = Self.twentyFourHour(hour, minute: 0, meridiem: meridiem)
                consumeTime(i...(i + 1))
            }
            i += 1
        }

        // "cumaya kadar", "18:00'a kadar": the deadline word belongs to the date or time.
        for index in tokens.indices where index > 0 && v.deadlineSuffixWords.contains(tokens[index].folded) && free(index) {
            let previousEnd = tokens[index - 1].range.upperBound
            if let match = highlights.firstIndex(where: { ($0.kind == .date || $0.kind == .time) && $0.range.upperBound == previousEnd }) {
                used.insert(index)
                highlights[match].range = highlights[match].range.lowerBound..<tokens[index].range.upperBound
            }
        }

        if day == nil {
            if rule.isRepeating {
                day = today
            } else if let minute {
                let nowMinute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
                day = minute > nowMinute ? today : calendar.date(byAdding: .day, value: 1, to: today)
            }
        }

        let listID = matchList(tokens: tokens, used: used, lists: lists, highlights: &highlights)

        let title = tokens.enumerated()
            .filter { !used.contains($0.offset) }
            .map(\.element.raw)
            .joined(separator: " ")

        return ParsedEntry(
            title: Self.capitalizedFirst(title, locale: v.capitalizationLocale),
            day: day,
            minute: minute,
            rule: rule,
            listID: listID,
            highlights: highlights.sorted { $0.range.lowerBound < $1.range.lowerBound }
        )
    }

    // MARK: Tokens

    private static func tokenize(_ text: String) -> [Token] {
        let characters = Array(text)
        let trimSet = CharacterSet(charactersIn: ",;:!?()\"“”.")
        var tokens: [Token] = []
        var start = 0
        while start < characters.count {
            if characters[start].isWhitespace { start += 1; continue }
            var end = start
            while end < characters.count, !characters[end].isWhitespace { end += 1 }
            let raw = String(characters[start..<end])
            let core = raw.trimmingCharacters(in: trimSet)
            tokens.append(Token(raw: raw, folded: TurkishText.fold(core), range: start..<end))
            start = end
        }
        return tokens
    }

    private static func capitalizedFirst(_ text: String, locale: Locale) -> String {
        guard let first = text.first else { return text }
        return String(first).uppercased(with: locale) + text.dropFirst()
    }

    // MARK: Words

    private static func matches(_ token: String, _ name: String, suffixes: Set<String>) -> Bool {
        if token == name { return true }
        guard token.hasPrefix(name) else { return false }
        return suffixes.contains(String(token.dropFirst(name.count)))
    }

    private static func weekday(of token: String, _ v: Vocabulary) -> Int? {
        v.weekdayNames.first { entry in
            entry.names.contains { matches(token, $0, suffixes: v.weekdaySuffixes) }
        }?.iso
    }

    private static func month(of token: String, _ v: Vocabulary) -> Int? {
        v.monthNames.firstIndex { names in
            names.contains { matches(token, $0, suffixes: v.monthSuffixes) }
        }.map { $0 + 1 }
    }

    /// "15", or "15th" in English.
    private static func dayNumber(_ token: String, _ v: Vocabulary) -> Int? {
        var digits = token
        for suffix in v.ordinalSuffixes where digits.hasSuffix(suffix) {
            digits = String(digits.dropLast(suffix.count))
            break
        }
        guard !digits.isEmpty, digits.count <= 2, digits.allSatisfy(\.isASCIIDigit), let value = Int(digits), (1...31).contains(value)
        else { return nil }
        return value
    }

    private static func withoutSuffix(_ token: String) -> String {
        token.split(whereSeparator: { $0 == "'" || $0 == "’" }).first.map(String.init) ?? token
    }

    private static func meridiem(_ token: String) -> Bool? {
        switch token {
        case "am", "a.m": false
        case "pm", "p.m": true
        default: nil
        }
    }

    /// `true` means PM.
    private static func twentyFourHour(_ hour: Int, minute: Int, meridiem isPM: Bool) -> Int {
        let base = hour % 12 + (isPM ? 12 : 0)
        return base * 60 + minute
    }

    /// "18:00", "18.30", "18:00'de", and in English "6pm", "6:30pm".
    private static func clock(_ token: String, _ v: Vocabulary) -> Int? {
        var base = withoutSuffix(token)
        var meridiemValue: Bool?
        if v.usesMeridiem {
            for suffix in ["am", "pm", "a.m", "p.m"] where base.hasSuffix(suffix) {
                meridiemValue = meridiem(suffix)
                base = String(base.dropLast(suffix.count))
                break
            }
        }

        let parts = base.split(omittingEmptySubsequences: false, whereSeparator: { $0 == ":" || $0 == "." })
        if let meridiemValue {
            guard (1...2).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.count <= 2 && $0.allSatisfy(\.isASCIIDigit) }),
                  let hour = Int(parts[0]), (1...12).contains(hour)
            else { return nil }
            let minute = parts.count == 2 ? (Int(parts[1]) ?? 0) : 0
            guard (0...59).contains(minute) else { return nil }
            return twentyFourHour(hour, minute: minute, meridiem: meridiemValue)
        }

        guard parts.count == 2, parts[1].count == 2,
              parts[0].count <= 2, parts[0].allSatisfy(\.isASCIIDigit), parts[1].allSatisfy(\.isASCIIDigit),
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute)
        else { return nil }
        return hour * 60 + minute
    }

    /// "18", "18'de"
    private static func hourOnly(_ token: String) -> Int? {
        let base = withoutSuffix(token)
        guard !base.isEmpty, base.count <= 2, base.allSatisfy(\.isASCIIDigit),
              let hour = Int(base), (0...23).contains(hour)
        else { return nil }
        return hour
    }

    // MARK: Dates

    private func nextDay(_ iso: Int, after today: Date) -> Date? {
        (1...7)
            .compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
            .first { Weekday.iso(of: $0, calendar: calendar) == iso }
    }

    private func dayInNextWeek(_ iso: Int, from today: Date) -> Date? {
        let todayISO = Weekday.iso(of: today, calendar: calendar)
        guard let monday = calendar.date(byAdding: .day, value: 8 - todayISO, to: today) else { return nil }
        return calendar.date(byAdding: .day, value: iso - 1, to: monday)
    }

    private func makeDate(day: Int, month: Int, year: Int?, today: Date) -> Date? {
        let currentYear = calendar.component(.year, from: today)
        func build(_ year: Int) -> Date? {
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
                  calendar.component(.day, from: date) == day,
                  calendar.component(.month, from: date) == month
            else { return nil }
            return date
        }
        if let year { return build(year) }
        guard let candidate = build(currentYear) else { return nil }
        return candidate < today ? build(currentYear + 1) : candidate
    }

    /// "15/10" or "15/10/2026" (or "10/15" when the language writes the month first).
    private func slashDate(_ token: String, dayFirst: Bool, today: Date) -> Date? {
        let parts = token.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCIIDigit) }),
              let first = Int(parts[0]), let second = Int(parts[1])
        else { return nil }
        let day = dayFirst ? first : second
        let month = dayFirst ? second : first
        guard (1...31).contains(day), (1...12).contains(month) else { return nil }
        var year: Int?
        if parts.count == 3, let value = Int(parts[2]) {
            year = parts[2].count == 2 ? 2000 + value : value
        }
        return makeDate(day: day, month: month, year: year, today: today)
    }

    // MARK: Lists

    private func matchList(tokens: [Token], used: Set<Int>, lists: [ListRef], highlights: inout [Highlight]) -> UUID? {
        var best: (score: Int, listID: UUID, token: Int)?
        for list in lists {
            let words = TurkishText.fold(list.name)
                .split(separator: " ")
                .map(String.init)
                .filter { $0.count >= 3 }
            for (index, token) in tokens.enumerated() where !used.contains(index) {
                let word = token.folded
                guard word.count >= 3 else { continue }
                for listWord in words {
                    var score = 0
                    if word == listWord {
                        score = listWord.count + 10
                    } else if listWord.count >= 4, word.hasPrefix(listWord) {
                        score = listWord.count + 5
                    } else if word.count >= 4, listWord.hasPrefix(word) {
                        score = word.count
                    }
                    if score > (best?.score ?? 0) {
                        best = (score, list.id, index)
                    }
                }
            }
        }
        guard let best else { return nil }
        highlights.append(Highlight(kind: .list, range: tokens[best.token].range))
        return best.listID
    }
}

private extension Character {
    var isASCIIDigit: Bool { self >= "0" && self <= "9" }
}
