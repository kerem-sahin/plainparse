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
        /// "her sabah": the part of the day is the time of a daily task, so it leaves the title even with no hour.
        var everyDayPart = false

        /// "pazartesi ve perşembe", "Mon, Wed and Fri": the weekdays of a chain starting at `start`.
        func weekdayChain(from start: Int) -> (mask: Int, last: Int, count: Int)? {
            guard free(start), let first = Self.weekday(of: tokens[start].folded, v, cued: true) else { return nil }
            var mask = Weekday.bit(first)
            var last = start
            var count = 1
            var j = start + 1
            while free(j) {
                let previousEndsWithComma = tokens[j - 1].raw.hasSuffix(",")
                if v.conjunctions.contains(tokens[j].folded), free(j + 1),
                   let day = Self.weekday(of: tokens[j + 1].folded, v, cued: true) {
                    mask |= Weekday.bit(day)
                    last = j + 1
                    j += 2
                    count += 1
                } else if previousEndsWithComma, let day = Self.weekday(of: tokens[j].folded, v, cued: true) {
                    mask |= Weekday.bit(day)
                    last = j
                    j += 1
                    count += 1
                } else {
                    break
                }
            }
            if free(last + 1), v.weekdayMarkers.contains(tokens[last + 1].folded) {
                last += 1
            }
            return (mask, last, count)
        }

        /// The start of a monthly series named by its day: "her ayın 1'i", "every month on the 1st". The series
        /// starts on the next such day (today when it is today).
        var monthlyStart: Date?
        func monthDay(after index: Int) -> (day: Int, last: Int)? {
            var j = index
            while free(j), v.monthDayFillers.contains(tokens[j].folded) { j += 1 }
            guard free(j), let number = Self.dayOfMonth(tokens[j].folded, v) else { return nil }
            return (number, j)
        }
        func nextDate(withDay number: Int) -> Date? {
            for offset in 0...62 {
                guard let candidate = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
                let length = calendar.range(of: .day, in: .month, for: candidate)?.count ?? 31
                if calendar.component(.day, from: candidate) == min(number, length) { return candidate }
            }
            return nil
        }

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
                // "her sabah", "every evening": every day, at that part of the day. Only "her" is the
                // repeat; the part of the day is read below as the time. ("her akşam yemeği" is a noun.)
                if v.dayParts.contains(where: { entry in
                    guard let length = phrase(entry.phrases, at: next) else { return false }
                    return !(free(next + length) && v.dayPartBlockers.contains(tokens[next + length].folded))
                }) {
                    if rule.kind != .weekly { rule = .daily }
                    consume(i...i, as: .repeating)
                    everyDayPart = true
                    i = next
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
                    var last = next
                    if let named = monthDay(after: next + 1) {
                        monthlyStart = nextDate(withDay: named.day)
                        last = named.last
                    }
                    consume(i...last, as: .repeating)
                    i = last + 1
                    continue
                }
                if let chain = weekdayChain(from: next) {
                    rule = RepeatRule(kind: .weekly, weekdayMask: chain.mask)
                    consume(i...chain.last, as: .repeating)
                    i = chain.last + 1
                    continue
                }
            }
            // "pazartesi ve perşembe spor": two or more weekdays joined together mean every one of them.
            // (A single weekday stays a one-off date.)
            if !v.every.contains(word), let chain = weekdayChain(from: i), chain.count >= 2 {
                rule = RepeatRule(kind: .weekly, weekdayMask: chain.mask)
                consume(i...chain.last, as: .repeating)
                i = chain.last + 1
                continue
            }
            i += 1
        }

        // A day-part word ("akşam", "morning") is found first: it hints at a time, and a bare hour that
        // follows it ("akşam 8") is read in its light. Nothing is consumed yet.
        struct FoundDayPart {
            var start: Int
            var end: Int
            var kind: DayPart
            var defaultMinute: Int?
            /// "bu akşam", "this evening": the part of today, never tomorrow.
            var isThis: Bool
        }
        var dayPart: FoundDayPart?
        search: for index in tokens.indices where free(index) {
            for entry in v.dayParts {
                guard let length = phrase(entry.phrases, at: index) else { continue }
                let end = index + length - 1
                if free(end + 1), v.dayPartBlockers.contains(tokens[end + 1].folded) { continue }
                var start = index
                if free(index - 1), v.thisPrefixes.contains(tokens[index - 1].folded) { start = index - 1 }
                dayPart = FoundDayPart(start: start, end: end, kind: entry.kind, defaultMinute: entry.defaultMinute, isThis: start != index)
                break search
            }
        }

        /// Whether a time (or day part) begins at `index`; used as a cue for ambiguous weekday names.
        func startsTime(_ index: Int) -> Bool {
            guard free(index) else { return false }
            let word = tokens[index].folded
            if v.timePrefixWords.contains(word) { return true }
            if Self.clockParts(word, v) != nil { return true }
            if let hour = Self.bareHour(word, v), hour.locative { return true }
            if let dayPart, dayPart.start == index || dayPart.end == index { return true }
            return false
        }

        func weekendSaturday(next: Bool) -> Date? {
            if next { return dayInNextWeek(6, from: today) }
            return Weekday.iso(of: today, calendar: calendar) == 6 ? today : nextDay(6, after: today)
        }

        /// "3 gün sonra", "in 3 days": the date and how many tokens it takes.
        func relativeDate(at index: Int) -> (length: Int, date: Date)? {
            var number: Int?
            var unitIndex = index
            if v.relativeBefore.contains(tokens[index].folded), free(index + 1), free(index + 2) {
                number = Self.smallNumber(tokens[index + 1].folded)
                unitIndex = index + 2
            } else if free(index + 1), free(index + 2), v.relativeAfter.contains(tokens[index + 2].folded) {
                number = Self.smallNumber(tokens[index].folded)
                unitIndex = index + 1
            }
            guard let number, let unit = v.relativeUnits[tokens[unitIndex].folded],
                  let date = calendar.date(byAdding: unit, value: number, to: today)
            else { return nil }
            return (3, date)
        }

        // The first date phrase wins.
        var day: Date?

        /// Dotted pairs ("15.10") are dates only when nothing else in the line is a date, so
        /// `allowShortDotted` is off on the first pass.
        func scanDates(allowShortDotted: Bool) {
            var i = 0
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
                } else if let length = phrase(v.weekendDatePhrases, at: i) {
                    day = weekendSaturday(next: false)
                    consumeDate(i...(i + length - 1))
                } else if v.nextPrefixes.contains(word) {
                    if free(i + 1), let weekday = Self.weekday(of: tokens[i + 1].folded, v, cued: true) {
                        day = dayInNextWeek(weekday, from: today)
                        consumeDate(i...(i + 1))
                    } else if let length = phrase(v.weekendDatePhrases, at: i + 1) {
                        day = weekendSaturday(next: true)
                        consumeDate(i...(i + length))
                    } else if free(i + 1), v.weekWord.contains(tokens[i + 1].folded) {
                        day = calendar.date(byAdding: .day, value: 7, to: today)
                        consumeDate(i...(i + 1))
                    } else if v.nextAloneMeansWeek {
                        day = calendar.date(byAdding: .day, value: 7, to: today)
                        consumeDate(i...i)
                    }
                } else if v.thisPrefixes.contains(word) {
                    if free(i + 1), let weekday = Self.weekday(of: tokens[i + 1].folded, v, cued: true) {
                        day = nextDay(weekday, after: today)
                        var last = i + 1
                        if free(last + 1), v.weekdayMarkers.contains(tokens[last + 1].folded) { last += 1 }
                        consumeDate(i...last)
                    } else if let length = phrase(v.weekendDatePhrases, at: i + 1) {
                        day = weekendSaturday(next: false)
                        consumeDate(i...(i + length))
                    }
                } else if let weekday = Self.weekday(of: word, v, cued: startsTime(i + 1)
                            || (free(i + 1) && v.weekdayMarkers.contains(tokens[i + 1].folded))) {
                    day = nextDay(weekday, after: today)
                    var last = i
                    if free(i + 1), v.weekdayMarkers.contains(tokens[i + 1].folded) { last = i + 1 }
                    consumeDate(i...last)
                } else if let (length, date) = relativeDate(at: i) {
                    day = date
                    consumeDate(i...(i + length - 1))
                } else if let number = Self.dayNumber(word, v), free(i + 1),
                          let month = Self.month(of: tokens[i + 1].folded, v) {
                    let year = free(i + 2) ? Self.year(tokens[i + 2].folded) : nil
                    if let date = makeDate(day: number, month: month, year: year, today: today) {
                        day = date
                        consumeDate(i...(i + (year == nil ? 1 : 2)))
                    }
                } else if v.monthFirstAllowed, let month = Self.month(of: word, v), free(i + 1),
                          let number = Self.dayNumber(tokens[i + 1].folded, v) {
                    let year = free(i + 2) ? Self.year(tokens[i + 2].folded) : nil
                    if let date = makeDate(day: number, month: month, year: year, today: today) {
                        day = date
                        consumeDate(i...(i + (year == nil ? 1 : 2)))
                    }
                } else if let date = numericDate(word, separator: "/", dayFirst: v.slashDateDayFirst, today: today) {
                    day = date
                    consumeDate(i...i)
                } else if let date = numericDate(word, separator: ".", dayFirst: v.slashDateDayFirst, today: today, fullOnly: !allowShortDotted),
                          // "15.10" the day after 15 October is a time ("15:10"), not a date a year away.
                          !(allowShortDotted && word.split(separator: ".").count == 2
                            && Self.clockParts(word, v) != nil
                            && (calendar.dateComponents([.day], from: today, to: date).day ?? 0) > 60),
                          !(free(i - 1) && v.timePrefixWords.contains(tokens[i - 1].folded)),
                          !(v.usesMeridiem && free(i + 1) && Self.meridiem(tokens[i + 1].folded) != nil),
                          !(dayPart.map { $0.end + 1 == i } ?? false) {
                    day = date
                    consumeDate(i...i)
                }
                i += 1
            }
        }
        scanDates(allowShortDotted: false)
        if day == nil, v.slashDateDayFirst { scanDates(allowShortDotted: true) }

        // Times. A bare hour needs a reason: "saat"/"at" in front, a locative ending ("18'de"),
        // a following am/pm, or a day part in front ("akşam 8").
        var minute: Int?

        func timeCandidate(at j: Int, prefixed: Bool, part: DayPart?) -> (end: Int, minute: Int)? {
            guard free(j) else { return nil }
            let token = tokens[j].folded
            let hour: Int
            let minutes: Int
            var meridiemValue: Bool?
            var leadingZero = false
            if let clock = Self.clockParts(token, v) {
                hour = clock.hour
                minutes = clock.minute
                meridiemValue = clock.pm
                leadingZero = clock.leadingZero
            } else if let bare = Self.bareHour(token, v) {
                let followedByMeridiem = v.usesMeridiem && free(j + 1) && Self.meridiem(tokens[j + 1].folded) != nil
                let allowed = prefixed || bare.locative
                    || (!bare.hasSuffix && (part != nil || followedByMeridiem))
                guard allowed else { return nil }
                hour = bare.hour
                minutes = 0
                leadingZero = bare.leadingZero
            } else {
                return nil
            }

            if let meridiemValue {
                return (j, Self.twentyFourHour(hour, minute: minutes, meridiem: meridiemValue))
            }
            if v.usesMeridiem, free(j + 1), (1...12).contains(hour), let spoken = Self.meridiem(tokens[j + 1].folded) {
                return (j + 1, Self.twentyFourHour(hour, minute: minutes, meridiem: spoken))
            }
            var adjusted = hour
            if (1...12).contains(hour), let part {
                adjusted = Self.hour(hour, in: part)
            } else if prefixed, (1...6).contains(hour), !leadingZero {
                adjusted = hour + 12
            }
            return (j, adjusted * 60 + minutes)
        }

        i = 0
        while i < tokens.count, minute == nil {
            guard free(i) else { i += 1; continue }
            let adjacentPart = dayPart.flatMap { $0.end + 1 == i ? $0.kind : nil }
            let prefixed = v.timePrefixWords.contains(tokens[i].folded) && free(i + 1)
            if let found = timeCandidate(at: prefixed ? i + 1 : i, prefixed: prefixed, part: adjacentPart) {
                minute = found.minute
                var lower = i
                if adjacentPart != nil, let dayPart, (dayPart.start...dayPart.end).allSatisfy({ free($0) }) {
                    lower = dayPart.start
                }
                consume(lower...found.end, as: .time)
            }
            i += 1
        }

        var minuteFromDayPart = false
        if let dayPart, (dayPart.start...dayPart.end).allSatisfy({ free($0) }),
           minute != nil || dayPart.defaultMinute != nil || everyDayPart || dayPart.isThis {
            var lower = dayPart.start
            if free(lower - 1), v.timePrefixWords.contains(tokens[lower - 1].folded) { lower -= 1 }
            consume(lower...dayPart.end, as: .time)
        }
        if minute == nil, let fallback = dayPart?.defaultMinute {
            minute = fallback
            minuteFromDayPart = true
        }

        // "cumaya kadar", "18:00'a kadar": the deadline word belongs to the date or time.
        for index in tokens.indices where index > 0 && v.deadlineSuffixWords.contains(tokens[index].folded) && free(index) {
            let previousEnd = tokens[index - 1].range.upperBound
            if let match = highlights.firstIndex(where: { ($0.kind == .date || $0.kind == .time) && $0.range.upperBound == previousEnd }) {
                used.insert(index)
                highlights[match].range = highlights[match].range.lowerBound..<tokens[index].range.upperBound
            }
        }

        if day == nil, rule.kind == .monthly, let monthlyStart {
            day = monthlyStart
        }
        if day == nil {
            let nowMinute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
            if rule.isRepeating {
                day = today
            } else if let dayPart, dayPart.isThis {
                // "bu akşam" at 21:00 is still this evening.
                day = today
            } else if let dayPart, minuteFromDayPart, dayPart.kind == .evening || dayPart.kind == .night,
                      nowMinute < Self.endMinute(of: dayPart.kind) {
                // "akşam annemi ara" while it is still evening: today, not tomorrow. (A morning that has
                // passed still means tomorrow morning.)
                day = today
            } else if let minute {
                day = minute > nowMinute ? today : calendar.date(byAdding: .day, value: 1, to: today)
            }
        }

        let listID = matchList(tokens: tokens, used: used, lists: lists, highlights: &highlights)

        let title = tokens.enumerated()
            .filter { !used.contains($0.offset) }
            .map(\.element.raw)
            .joined(separator: " ")

        // Turkish casing ("istanbul" becomes "İstanbul") only for text that is Turkish: this
        // vocabulary recognised something, or the title itself carries Turkish letters or endings.
        let recognisedTurkish = v.language == .turkish && highlights.contains { $0.kind != .list }
        let casing = recognisedTurkish || Self.looksTurkish(title) ? TurkishText.locale : Locale(identifier: "en_US")

        return ParsedEntry(
            title: Self.capitalizedFirst(title, locale: casing),
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

    private static let turkishLetters: Set<Character> = Set("çğıöşüâîûÇĞİÖŞÜÂÎÛ")
    private static let turkishCaseEndings: Set<String> = [
        "a", "e", "ya", "ye", "da", "de", "ta", "te", "dan", "den", "tan", "ten", "i", "u", "yi", "yu",
        "in", "un", "nin", "nun", "la", "le", "yla", "yle", "ki", "nda", "nde", "inda", "inde",
    ]

    /// Turkish letters, or an apostrophe followed by a Turkish case ending ("İstanbul'a").
    private static func looksTurkish(_ title: String) -> Bool {
        if title.contains(where: { turkishLetters.contains($0) }) { return true }
        return title.split(separator: " ").contains { word in
            guard let apostrophe = word.firstIndex(where: { $0 == "'" || $0 == "’" }) else { return false }
            let ending = TurkishText.fold(String(word[word.index(after: apostrophe)...]).trimmingCharacters(in: .punctuationCharacters))
            return turkishCaseEndings.contains(ending)
        }
    }

    // MARK: Words

    private static func matches(_ token: String, _ name: String, suffixes: Set<String>) -> Bool {
        if token == name { return true }
        guard token.hasPrefix(name) else { return false }
        return suffixes.contains(String(token.dropFirst(name.count)))
    }

    private static func weekday(of token: String, _ v: Vocabulary, cued: Bool) -> Int? {
        v.weekdayNames.first { entry in
            entry.names.contains { name in
                if v.ambiguousWeekdayNames.contains(name) { return cued && token == name }
                return matches(token, name, suffixes: v.weekdaySuffixes)
            }
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

    /// When a part of the day is over, for "akşam" typed late in the evening.
    private static func endMinute(of part: DayPart) -> Int {
        switch part {
        case .morning: 12 * 60
        case .noon: 15 * 60
        case .afternoon: 18 * 60
        case .evening, .night: 24 * 60
        }
    }

    /// "1'i", "2'sinde", "15'inde", "1st", "1": a day of the month.
    private static func dayOfMonth(_ token: String, _ v: Vocabulary) -> Int? {
        if let number = dayNumber(token, v) { return number }
        let digits = String(token.prefix(while: \.isASCIIDigit))
        guard !digits.isEmpty, digits.count <= 2, let value = Int(digits), (1...31).contains(value) else { return nil }
        var rest = String(token.dropFirst(digits.count))
        if rest.hasPrefix("'") || rest.hasPrefix("’") { rest.removeFirst() }
        return v.monthDayEndings.contains(rest) ? value : nil
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

    /// A year written out in full ("2028").
    private static func year(_ token: String) -> Int? {
        guard token.count == 4, token.allSatisfy(\.isASCIIDigit), let value = Int(token), (2000...2199).contains(value)
        else { return nil }
        return value
    }

    /// "3", "30": a count in front of a unit.
    private static func smallNumber(_ token: String) -> Int? {
        guard !token.isEmpty, token.count <= 3, token.allSatisfy(\.isASCIIDigit), let value = Int(token), value >= 1
        else { return nil }
        return value
    }

    private struct ClockParts {
        var hour: Int
        var minute: Int
        /// `true` for PM, `false` for AM, nil when the token carries no am/pm.
        var pm: Bool?
        var leadingZero: Bool
    }

    /// "18:00", "18.30", "18:00'de", and in English "6pm", "6:30pm". With am/pm the hour is 1-12.
    private static func clockParts(_ token: String, _ v: Vocabulary) -> ClockParts? {
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
            return ClockParts(hour: hour, minute: minute, pm: meridiemValue, leadingZero: false)
        }

        guard parts.count == 2, parts[1].count == 2,
              parts[0].count <= 2, parts[0].allSatisfy(\.isASCIIDigit), parts[1].allSatisfy(\.isASCIIDigit),
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute)
        else { return nil }
        return ClockParts(hour: hour, minute: minute, pm: nil, leadingZero: parts[0].count == 2 && parts[0].hasPrefix("0"))
    }

    /// "18", "18'de": an hour with no minutes. `locative` is true for the Turkish "'de/'da/'te/'ta" ending.
    private static func bareHour(_ token: String, _ v: Vocabulary) -> (hour: Int, leadingZero: Bool, hasSuffix: Bool, locative: Bool)? {
        let apostrophe = token.firstIndex(where: { $0 == "'" || $0 == "’" })
        var base = apostrophe.map { String(token[..<$0]) } ?? token
        var suffix = apostrophe.map { String(token[token.index(after: $0)...]) }
        // People often leave the apostrophe out: "8de", "18de".
        if apostrophe == nil {
            let digits = String(token.prefix(while: \.isASCIIDigit))
            let rest = String(token.dropFirst(digits.count))
            if !digits.isEmpty, v.locativeSuffixes.contains(rest) { base = digits; suffix = rest }
        }
        guard !base.isEmpty, base.count <= 2, base.allSatisfy(\.isASCIIDigit),
              let hour = Int(base), (0...23).contains(hour)
        else { return nil }
        let locative = suffix.map { v.locativeSuffixes.contains($0) } ?? false
        return (hour, base.count == 2 && base.hasPrefix("0"), suffix != nil, locative)
    }

    /// A 1-12 hour written after a day part: "akşam 8" is 20:00, "sabah 9" stays 09:00, "gece 11" is 23:00.
    private static func hour(_ hour: Int, in part: DayPart) -> Int {
        switch part {
        case .morning:
            hour
        case .noon:
            (1...5).contains(hour) ? hour + 12 : hour
        case .afternoon, .evening:
            (1...11).contains(hour) ? hour + 12 : hour
        case .night:
            (6...11).contains(hour) ? hour + 12 : (hour == 12 ? 0 : hour)
        }
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
        // The next valid occurrence: 29 February waits for the next leap year.
        for offset in 0...8 {
            if let candidate = build(currentYear + offset), candidate >= today { return candidate }
        }
        return nil
    }

    /// "15/10", "15/10/2026" (or "10/15" when the language writes the month first) and the dotted
    /// "20.11.2026" / "20.11.26". A dotted pair without a year ("15.10") is only read as a date in
    /// day-first languages and only with a two-digit month, so "3.5 litre" stays a number;
    /// `fullOnly` leaves such pairs for the time reading.
    private func numericDate(_ token: String, separator: Character, dayFirst: Bool, today: Date, fullOnly: Bool = false) -> Date? {
        let parts = token.split(separator: separator, omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCIIDigit) }),
              let first = Int(parts[0]), let second = Int(parts[1])
        else { return nil }
        if separator == ".", parts.count == 2 {
            guard !fullOnly, dayFirst, parts[0].count <= 2, parts[1].count == 2 else { return nil }
        }
        if separator == ".", parts.count == 3, parts[2].count != 2, parts[2].count != 4 { return nil }
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
