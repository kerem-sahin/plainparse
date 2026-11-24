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
    public enum Kind: Sendable { case date, time, repeating, list, alarm }

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
    /// "7:00 alarm", "alarmlı": ring as an alarm, not a quiet notification. Only with a time.
    public var alarm: Bool = false
    /// Far end of a time range ("13:00-15:00", "3 ile 5 arası"), minutes from midnight, same day and after `minute`.
    public var endMinute: Int?
    /// "cumaya kadar her gün", "for 3 days": the last day of a repeating series (start of day, never before `day`).
    public var repeatEnd: Date?
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
        /// "cumaya kadar her gün", "every day until friday": the last day of the repeat.
        var repeatEnd: Date?
        /// "3 gün boyunca", "for a week": how long the series runs, counted from its first day.
        var span: (unit: Calendar.Component, count: Int)?
        /// Second pass over the dates, looking only for the end of a repeat once its start is known.
        var endOnlyPass = false
        /// Set while the date being read is a bare month ("until december"): as an end it means the month before.
        var bareMonthDate = false
        /// Set while the date being read is a weekday name ("cumaya kadar", "by friday"), with its ISO number.
        var weekdayDate: Int?

        /// "pazartesi ve perşembe", "Mon, Wed and Fri": the weekdays of a chain starting at `start`.
        func weekdayChain(from start: Int, loose: Bool = false) -> (mask: Int, last: Int, count: Int, looseJoins: Int)? {
            guard free(start), let first = Self.weekday(of: tokens[start].folded, v, cued: true) else { return nil }
            var mask = Weekday.bit(first)
            var last = start
            var count = 1
            var looseJoins = 0
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
                } else if loose, let day = Self.weekday(of: tokens[j].folded, v, cued: false) {
                    // "pazartesi çarşamba cuma": names side by side (never "pazar", which is a noun too).
                    mask |= Weekday.bit(day)
                    last = j
                    j += 1
                    count += 1
                    looseJoins += 1
                } else {
                    break
                }
            }
            if free(last + 1), v.weekdayMarkers.contains(tokens[last + 1].folded) {
                last += 1
            }
            return (mask, last, count, looseJoins)
        }

        /// The start of a monthly series named by its day: "her ayın 1'i", "every month on the 1st". The series
        /// starts on the next such day (today when it is today).
        var monthlyStart: Date?
        func monthDay(after index: Int) -> (day: Int, last: Int)? {
            var j = index
            while free(j), v.monthDayFillers.contains(tokens[j].folded) { j += 1 }
            if let length = phrase(v.firstDayPhrases, at: j) { return (1, j + length - 1) }
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

        /// "2 haftada bir", "her iki haftada bir", "every 2 weeks", "every other week": a weekly repeat that skips
        /// weeks. A bare "2 hafta" is a length of time ("2 hafta tatil", "2 hafta sonra"), not a repeat.
        func weekInterval(at index: Int) -> (weeks: Int, last: Int)? {
            if let length = phrase(v.everyOtherWeekPhrases, at: index) { return (2, index + length - 1) }
            var j = index
            if free(j), v.every.contains(tokens[j].folded) { j += 1 }
            if let length = phrase(v.everyOtherWeekPhrases, at: j) { return (2, j + length - 1) }
            return countInterval(at: index, words: v.intervalWeekWords, cued: v.intervalCuedWords, range: 2...RepeatRule.maxWeekInterval)
                .map { ($0.count, $0.last) }
        }

        /// "2 günde bir", "her 3 ayda bir", "every 2 days": a count, its unit word and the closing "bir". Without
        /// "her"/"every" only the `cued` unit forms count (a bare "2 gün" is a length of time).
        func countInterval(at index: Int, words: Set<String>, cued: Set<String>, range: ClosedRange<Int>) -> (count: Int, last: Int)? {
            var j = index
            if free(j), v.every.contains(tokens[j].folded) { j += 1 }
            guard free(j), free(j + 1), words.contains(tokens[j + 1].folded),
                  let count = Self.smallNumber(tokens[j].folded) ?? v.hourWords[tokens[j].folded],
                  range.contains(count)
            else { return nil }
            var last = j + 1
            if free(last + 1), v.intervalTail.contains(tokens[last + 1].folded) { last += 1 }
            // Without "her" the closing "bir" is needed too: "3 günde bitir" is a length, not a repeat.
            guard j > index || (cued.contains(tokens[j + 1].folded) && last > j + 1) else { return nil }
            return (count, last)
        }

        /// The first day from today on that `rule` falls on, for a series that starts at its first occurrence.
        func firstOccurrence(of rule: RepeatRule) -> Date? {
            (0...62).lazy
                .compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
                .first { rule.occurs(on: $0, startingFrom: today, calendar: calendar) }
        }

        /// The first day from `start` on that the current rule falls on (the start itself for a rule with no repeat).
        func firstOccurrence(from start: Date) -> Date {
            let first = calendar.startOfDay(for: start)
            return (0...400).lazy
                .compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
                .first { rule.occurs(on: $0, startingFrom: first, calendar: calendar) } ?? first
        }

        /// "ilk pazartesi", "second tuesday", "son günü", "last day": a position in the month.
        func monthPosition(at j: Int) -> (rule: RepeatRule, last: Int)? {
            guard free(j), let ordinal = v.ordinalValues[tokens[j].folded] else { return nil }
            if free(j + 1), let day = Self.positionWeekday(tokens[j + 1].folded, v) {
                return (.monthly(ordinal: ordinal, weekday: day), j + 1)
            }
            if ordinal == RepeatRule.lastOrdinal, let length = phrase(v.lastDayPhrases, at: j) {
                return (.lastDayOfMonth, j + length - 1)
            }
            return nil
        }

        /// "salıları", "mondays": a plural weekday name. The ambiguous "pazarları" (markets) needs a time right after it.
        func pluralWeekday(at index: Int) -> Int? {
            guard free(index), !v.pluralWeekdaySuffixes.isEmpty else { return nil }
            let token = tokens[index].folded
            guard !v.weekdayNames.contains(where: { $0.names.contains(token) }) else { return nil }
            for entry in v.weekdayNames {
                for name in entry.names where token.hasPrefix(name) {
                    guard v.pluralWeekdaySuffixes.contains(String(token.dropFirst(name.count))) else { continue }
                    if v.ambiguousWeekdayNames.contains(name) {
                        guard free(index + 1) else { continue }
                        let next = tokens[index + 1].folded
                        guard v.timePrefixWords.contains(next) || Self.clockParts(next, v) != nil
                                || Self.bareHour(next, v)?.locative == true
                        else { continue }
                    }
                    return entry.iso
                }
            }
            return nil
        }

        // Repeat phrases first: their weekday names must not be read as one-off dates.
        var i = 0
        while i < tokens.count {
            guard free(i) else { i += 1; continue }
            let word = tokens[i].folded

            if let interval = weekInterval(at: i) {
                // "2 haftada bir pazartesi": the weekdays may follow.
                var last = interval.last
                var mask = 0
                if let chain = weekdayChain(from: last + 1) {
                    mask = chain.mask
                    last = chain.last
                }
                rule = RepeatRule(kind: .weekly, weekdayMask: mask, weekInterval: interval.weeks)
                consume(i...last, as: .repeating)
                i = last + 1
                continue
            }

            if let found = countInterval(at: i, words: v.intervalDayWords, cued: v.intervalDayCuedWords, range: 2...RepeatRule.maxInterval(for: .daily)) {
                rule = RepeatRule(kind: .daily, interval: found.count)
                consume(i...found.last, as: .repeating)
                i = found.last + 1
                continue
            }
            if let found = countInterval(at: i, words: v.intervalMonthWords, cued: v.intervalMonthCuedWords, range: 2...12) {
                // Twelve months is a year.
                rule = found.count == 12 ? RepeatRule(kind: .yearly) : RepeatRule(kind: .monthly, interval: found.count)
                consume(i...found.last, as: .repeating)
                i = found.last + 1
                continue
            }
            if let length = phrase(v.everyOtherDayPhrases, at: i) {
                rule = RepeatRule(kind: .daily, interval: 2)
                consume(i...(i + length - 1), as: .repeating)
                i += length
                continue
            }
            if let length = phrase(v.everyOtherMonthPhrases, at: i) {
                rule = RepeatRule(kind: .monthly, interval: 2)
                consume(i...(i + length - 1), as: .repeating)
                i += length
                continue
            }
            if let length = phrase(v.quarterlyPhrases, at: i) {
                rule = RepeatRule(kind: .monthly, interval: 3)
                consume(i...(i + length - 1), as: .repeating)
                i += length
                continue
            }

            // "first monday of every month", "every 2nd tuesday of the month", "every last friday", "last day of
            // every month": by position in the month. A bare "every second tuesday" is every other week (below).
            do {
                let hasEvery = v.every.contains(word)
                if let position = monthPosition(at: hasEvery ? i + 1 : i) {
                    let tailEvery = phrase(v.monthTailEveryPhrases, at: position.last + 1)
                    let tailThe = phrase(v.monthTailThePhrases, at: position.last + 1)
                    let isDay = position.rule.isLastDayOfMonth
                    let repeats = tailEvery != nil || (hasEvery && (tailThe != nil || (!isDay && position.rule.ordinal != 2)))
                    if repeats {
                        let last = position.last + (tailEvery ?? tailThe ?? 0)
                        var first = i
                        while free(first - 1), v.monthDayFillers.contains(tokens[first - 1].folded) { first -= 1 }
                        rule = position.rule
                        monthlyStart = firstOccurrence(of: rule)
                        consume(first...last, as: .repeating)
                        i = last + 1
                        continue
                    }
                }
            }

            // "every other monday", "every second tuesday": every second week on that day.
            if let length = phrase(v.everyOtherPhrases, at: i), let chain = weekdayChain(from: i + length) {
                rule = RepeatRule(kind: .weekly, weekdayMask: chain.mask, weekInterval: 2)
                consume(i...chain.last, as: .repeating)
                i = chain.last + 1
                continue
            }

            // "hafta sonları", "on weekends": the weekend, every week.
            if let length = phrase(v.weekendPluralPhrases, at: i) {
                let lower = free(i - 1) && v.pluralPrefixWords.contains(tokens[i - 1].folded) ? i - 1 : i
                rule = RepeatRule(kind: .weekly, weekdayMask: Weekday.weekendMask)
                consume(lower...(i + length - 1), as: .repeating)
                i += length
                continue
            }
            // "salıları", "on mondays": a plural weekday is every such weekday.
            if let day = pluralWeekday(at: i) {
                let lower = free(i - 1) && v.pluralPrefixWords.contains(tokens[i - 1].folded) ? i - 1 : i
                var mask = Weekday.bit(day)
                var last = i
                // "mondays and wednesdays", "mondays, fridays".
                while true {
                    if free(last + 1), v.conjunctions.contains(tokens[last + 1].folded), let next = pluralWeekday(at: last + 2) {
                        mask |= Weekday.bit(next)
                        last += 2
                    } else if tokens[last].raw.hasSuffix(","), let next = pluralWeekday(at: last + 1) {
                        mask |= Weekday.bit(next)
                        last += 1
                    } else {
                        break
                    }
                }
                rule = RepeatRule(kind: .weekly, weekdayMask: mask)
                consume(lower...last, as: .repeating)
                i = last + 1
                continue
            }

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
                // "monthly rent on the 1st": the day may follow later in the line.
                for j in (i + length)..<max(i + length, tokens.count) where free(j) && v.monthDayFillers.contains(tokens[j].folded) {
                    if let named = monthDay(after: j), tokens[named.last].folded.last?.isASCIIDigit == false, let start = nextDate(withDay: named.day) {
                        monthlyStart = start
                        consume(j...named.last, as: .repeating)
                        break
                    }
                }
                i += length
                continue
            }
            if let length = phrase(v.yearlyAlone, at: i) {
                rule = RepeatRule(kind: .yearly)
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
                    // "her hafta pazar": the weekday after it is the repeat's day, not a one-off date.
                    if let chain = weekdayChain(from: next + 1) {
                        rule = RepeatRule(kind: .weekly, weekdayMask: chain.mask)
                        // "her hafta cumaya kadar": a weekly deadline, "kadar" goes with the weekday.
                        var last = chain.last
                        if free(last + 1), v.deadlineSuffixWords.contains(tokens[last + 1].folded) { last += 1 }
                        consume(i...last, as: .repeating)
                        i = last + 1
                        continue
                    }
                    rule = RepeatRule(kind: .weekly)
                    consume(i...next, as: .repeating)
                    i = next + 1
                    continue
                }
                if v.yearWord.contains(tokens[next].folded) {
                    // "her sene 11 kasımda": the date after it is read below as the first occurrence.
                    rule = RepeatRule(kind: .yearly)
                    consume(i...next, as: .repeating)
                    i = next + 1
                    continue
                }
                // "her 11 kasım", "every November 11": a day of a named month repeats every year. Only "her" is
                // the repeat; the date is read below.
                if Self.dayNumber(tokens[next].folded, v) != nil, free(next + 1),
                   Self.month(of: tokens[next + 1].folded, v) != nil {
                    rule = RepeatRule(kind: .yearly)
                    consume(i...i, as: .repeating)
                    i = next
                    continue
                }
                if v.monthFirstAllowed, Self.month(of: tokens[next].folded, v) != nil, free(next + 1),
                   Self.dayNumber(tokens[next + 1].folded, v) != nil {
                    rule = RepeatRule(kind: .yearly)
                    consume(i...i, as: .repeating)
                    i = next
                    continue
                }
                if v.monthWord.contains(tokens[next].folded) {
                    let named = monthDay(after: next + 1)
                    // "her ayın ilk pazartesi", "her ayın son günü", "her ay sonu": by position in the month.
                    if named == nil {
                        var found: (rule: RepeatRule, last: Int)?
                        if let position = monthPosition(at: next + 1) {
                            found = position
                        } else if free(next + 1), v.monthEndWords.contains(tokens[next + 1].folded) {
                            found = (.lastDayOfMonth, next + 1)
                        }
                        if let found {
                            rule = found.rule
                            monthlyStart = firstOccurrence(of: rule)
                            consume(i...found.last, as: .repeating)
                            i = found.last + 1
                            continue
                        }
                    }
                    // "the 15th of every month", "the first day of every month": the day comes before.
                    var first = i
                    if free(i - 1), v.dayMonthFillers.contains(tokens[i - 1].folded), free(i - 2) {
                        if let number = Self.dayOfMonth(tokens[i - 2].folded, v), let start = nextDate(withDay: number) {
                            monthlyStart = start
                            first = i - 2
                            while free(first - 1), v.monthDayFillers.contains(tokens[first - 1].folded) { first -= 1 }
                        } else if free(i - 3), v.ordinalValues[tokens[i - 3].folded] != nil {
                            if tokens[i - 3].folded == "first", v.dayWord.contains(tokens[i - 2].folded), let start = nextDate(withDay: 1) {
                                monthlyStart = start
                                first = i - 3
                            } else {
                                i = next + 1
                                continue
                            }
                        }
                    }
                    rule = RepeatRule(kind: .monthly)
                    var last = next
                    if let named {
                        monthlyStart = nextDate(withDay: named.day)
                        last = named.last
                    }
                    consume(min(first, i)...last, as: .repeating)
                    i = last + 1
                    continue
                }
                if let chain = weekdayChain(from: next, loose: true) {
                    rule = RepeatRule(kind: .weekly, weekdayMask: chain.mask)
                    consume(i...chain.last, as: .repeating)
                    i = chain.last + 1
                    continue
                }
            }
            // "pazartesi ve perşembe spor": two or more weekdays joined together mean every one of them.
            // (A single weekday stays a one-off date.)
            // The same for a plural marker ("salı günleri"); names side by side need three ("pazartesi çarşamba cuma").
            if !v.every.contains(word), let chain = weekdayChain(from: i, loose: true),
               (chain.count >= 2 && (chain.looseJoins == 0 || chain.count >= 3))
                || (chain.count >= 1 && v.pluralWeekdayMarkers.contains(tokens[chain.last].folded)) {
                rule = RepeatRule(kind: .weekly, weekdayMask: chain.mask)
                consume(i...chain.last, as: .repeating)
                i = chain.last + 1
                continue
            }
            i += 1
        }

        // "3 gün boyunca", "bir hafta boyunca", "for 2 weeks": a length of time. Without a repeat it means every day.
        if !v.spanAfterWords.isEmpty || !v.spanBeforeWords.isEmpty {
            func spanLimit(_ unit: Calendar.Component) -> Int { unit == .day ? 366 : unit == .weekOfYear ? 52 : 24 }
            for index in tokens.indices where free(index) && span == nil {
                let numberAt: Int
                if v.spanBeforeWords.contains(tokens[index].folded) { numberAt = index + 1 } else if v.spanAfterWords.isEmpty { continue } else { numberAt = index }
                guard free(numberAt), free(numberAt + 1), let unit = v.relativeUnits[tokens[numberAt + 1].folded],
                      let count = Self.smallNumber(tokens[numberAt].folded) ?? v.hourWords[tokens[numberAt].folded]
                        ?? (v.spanArticleWords.contains(tokens[numberAt].folded) ? 1 : nil),
                      (1...spanLimit(unit)).contains(count)
                else { continue }
                // "buy gift for a week": without a repeat word an English span means daily only at the start of the line.
                if !rule.isRepeating, v.spanBeforeWords.contains(tokens[index].folded), (0..<index).contains(where: { free($0) }) { continue }
                let last: Int
                if numberAt > index {
                    last = numberAt + 1
                } else if free(numberAt + 2), v.spanAfterWords.contains(tokens[numberAt + 2].folded) {
                    last = numberAt + 2
                } else {
                    continue
                }
                span = (unit, count)
                if !rule.isRepeating { rule = .daily }
                consume(index...last, as: .repeating)
            }
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
            /// "cuma akşamı": the word belongs to the day before it, so it leaves the title even with no hour.
            var possessive: Bool
        }
        var dayPart: FoundDayPart?
        /// "akşam yemeği": not a time, but it still says which part of the day a following hour is in.
        var mealPart: (kind: DayPart, blocker: Int)?
        search: for index in tokens.indices where free(index) {
            for entry in v.dayParts {
                guard let length = phrase(entry.phrases, at: index) else { continue }
                let end = index + length - 1
                if entry.needsDayBefore {
                    guard free(index - 1) else { continue }
                    let previous = tokens[index - 1].folded
                    guard Self.weekday(of: previous, v, cued: true) != nil || v.todayWords.contains(previous)
                            || v.tomorrowWords.contains(previous)
                    else { continue }
                }
                if free(end + 1), v.dayPartBlockers.contains(tokens[end + 1].folded) {
                    if mealPart == nil, v.mealWords.contains(tokens[end + 1].folded) { mealPart = (entry.kind, end + 1) }
                    continue
                }
                var start = index
                if free(index - 1), v.thisPrefixes.contains(tokens[index - 1].folded) { start = index - 1 }
                dayPart = FoundDayPart(start: start, end: end, kind: entry.kind, defaultMinute: entry.defaultMinute, isThis: start != index,
                                       possessive: entry.needsDayBefore)
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
            var counted = false
            var unitIndex = index
            if v.relativeBefore.contains(tokens[index].folded), free(index + 1), free(index + 2) {
                number = Self.smallNumber(tokens[index + 1].folded) ?? v.hourWords[tokens[index + 1].folded]
                unitIndex = index + 2
            } else if free(index + 1), free(index + 2), v.relativeAfter.contains(tokens[index + 2].folded) {
                // "2 gün sonra", and in words: "iki gün sonra".
                number = Self.smallNumber(tokens[index].folded) ?? v.hourWords[tokens[index].folded]
                unitIndex = index + 1
                counted = true
            }
            guard let number, let unit = v.relativeUnits[tokens[unitIndex].folded],
                  let date = calendar.date(byAdding: unit, value: number, to: today)
            else { return nil }
            // "2 hafta sonra salı": that weekday of the week two weeks from now (weeks start on Monday).
            if counted, unit == .weekOfYear, free(index + 3), let weekday = Self.weekday(of: tokens[index + 3].folded, v, cued: true),
               let monday = calendar.date(byAdding: .day, value: 1 - Weekday.iso(of: date, calendar: calendar), to: date),
               let target = calendar.date(byAdding: .day, value: weekday - 1, to: monday) {
                return (4, target)
            }
            return (3, date)
        }

        // The first date phrase wins.
        var day: Date?

        /// "Haziran'da tatil planı", "haziran ayında", "in June": the first of that month (today if it is this
        /// month). The month has to be marked as a name: an apostrophe, "ayında" after it, or "in" before it,
        /// so "ocakta yemek var" (on the stove) and "may" stay words.
        func monthAlone(at index: Int) -> (first: Date, range: ClosedRange<Int>)? {
            guard free(index) else { return nil }
            let folded = tokens[index].folded
            let apostrophe = folded.firstIndex { $0 == "'" || $0 == "’" }
            let base = apostrophe.map { String(folded[..<$0]) } ?? folded
            guard let month = v.monthNames.firstIndex(where: { $0.contains(base) }).map({ $0 + 1 }) else { return nil }
            var range = index...index
            if apostrophe != nil {
                // "Haziran'da": a name.
            } else if free(index + 1), v.monthAloneFollowers.contains(tokens[index + 1].folded) {
                range = index...(index + 1)
            } else if free(index - 1), v.monthAlonePrefixes.contains(tokens[index - 1].folded) {
                range = (index - 1)...index
            } else {
                return nil
            }
            let thisMonth = calendar.component(.month, from: today)
            if month == thisMonth { return (today, range) }
            var parts = calendar.dateComponents([.year], from: today)
            parts.year = (parts.year ?? 0) + (month < thisMonth ? 1 : 0)
            parts.month = month
            parts.day = 1
            guard let first = calendar.date(from: parts) else { return nil }
            return (first, range)
        }

        /// The index of the month name after a day number: "15 kasım", "15th of november".
        func monthSlot(after index: Int) -> Int? {
            var at = index + 1
            if free(at), v.dayMonthFillers.contains(tokens[at].folded) { at += 1 }
            guard free(at), Self.month(of: tokens[at].folded, v) != nil else { return nil }
            return at
        }

        /// Month first, then its day: "kasımın 15'i", "mayıs ayının 5'i", and a bare "mayıs 5".
        func monthFirstDate(at index: Int) -> (date: Date, last: Int)? {
            guard free(index) else { return nil }
            let token = tokens[index].folded
            let apostrophe = token.firstIndex { $0 == "'" || $0 == "’" }
            let base = apostrophe.map { String(token[..<$0]) } ?? token
            let ending = apostrophe.map { String(token[token.index(after: $0)...]) }
            var found: (month: Int, genitive: Bool)?
            for (offset, names) in v.monthNames.enumerated() {
                for name in names {
                    if base == name, ending == nil || v.monthGenitiveSuffixes.contains(ending ?? "") {
                        found = (offset + 1, ending != nil)
                    } else if ending == nil, base.hasPrefix(name), v.monthGenitiveSuffixes.contains(String(base.dropFirst(name.count))) {
                        found = (offset + 1, true)
                    }
                }
            }
            guard let found else { return nil }
            var dayAt = index + 1
            if !found.genitive {
                if free(dayAt), v.monthGenitiveFillers.contains(tokens[dayAt].folded) {
                    dayAt += 1
                } else {
                    // A bare month followed by a plain number: not when the number counts something ("mart 3 hafta").
                    guard v.monthFirstBareNumber, free(dayAt), Self.dayNumber(tokens[dayAt].folded, v) != nil,
                          !(free(dayAt + 1) && v.numberNounBlockers.contains(tokens[dayAt + 1].folded))
                    else { return nil }
                }
            }
            guard free(dayAt), let number = Self.dayOfMonth(tokens[dayAt].folded, v),
                  let date = makeDate(day: number, month: found.month, year: nil, today: today)
            else { return nil }
            return (date, dayAt)
        }

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
                    var upper = range.upperBound
                    // "cumaya kadar", "until friday" with a repeat: the date is the end of the series, not its start.
                    if rule.isRepeating, repeatEnd == nil, let found = day {
                        let before = free(lower - 1) && v.untilPrefixWords.contains(tokens[lower - 1].folded)
                        let after = free(upper + 1) && v.deadlineSuffixWords.contains(tokens[upper + 1].folded)
                        // "her hafta cumaya kadar", "every week by friday": a weekly deadline, so it repeats on that weekday.
                        let byWord = free(lower - 1) && v.deadlinePrefixWords.contains(tokens[lower - 1].folded)
                            && !v.untilPrefixWords.contains(tokens[lower - 1].folded) && tokens[lower - 1].folded != "on"
                        if rule.kind == .weekly, rule.weekdayMask == 0, let weekdayDate, after || byWord {
                            if byWord { lower -= 1 }
                            if after { upper += 1 }
                            consume(lower...upper, as: .repeating)
                            rule.weekdayMask = Weekday.bit(weekdayDate)
                            day = nil
                            return
                        }
                        if before || after {
                            if before { lower -= 1 }
                            if after { upper += 1 }
                            consume(lower...upper, as: .date)
                            repeatEnd = bareMonthDate ? calendar.date(byAdding: .day, value: -1, to: found) : found
                            day = nil
                            return
                        }
                    }
                    if endOnlyPass {
                        day = nil
                        return
                    }
                    if free(lower - 1), v.deadlinePrefixWords.contains(tokens[lower - 1].folded) {
                        lower -= 1
                    } else if let words = v.deadlinePrefixPhrases.first(where: { words in
                        words.indices.allSatisfy { free(lower - words.count + $0) && tokens[lower - words.count + $0].folded == words[$0] }
                    }) {
                        lower -= words.count
                    }
                    // "starting monday", "pazartesiden itibaren": the start of a repeat is its first day.
                    // ("from" is a start only with a repeat: "mail from friday" is not.)
                    while free(lower - 1), v.startBoundPrefixWords.contains(tokens[lower - 1].folded),
                          tokens[lower - 1].folded != "from" || rule.isRepeating {
                        lower -= 1
                    }
                    if free(upper + 1), v.startBoundSuffixWords.contains(tokens[upper + 1].folded) { upper += 1 }
                    consume(lower...upper, as: .date)
                }
                /// "the 15th", "on the 15th": the words in front of an English ordinal belong to it.
                func withLead(_ range: ClosedRange<Int>) -> ClosedRange<Int> {
                    var lower = range.lowerBound
                    while free(lower - 1), v.monthDayFillers.contains(tokens[lower - 1].folded) { lower -= 1 }
                    return lower...range.upperBound
                }

                if let length = phrase(v.weekEndPhrases, at: i), !(free(i - 1) && v.every.contains(tokens[i - 1].folded)),
                   let sunday = calendar.date(byAdding: .day, value: 7 - Weekday.iso(of: today, calendar: calendar), to: today) {
                    // "hafta sonuna kadar", "bu hafta içinde", "end of week": by the end of this week (Sunday).
                    day = sunday
                    consumeDate(i...(i + length - 1))
                } else if let length = phrase(v.monthEndPhrases, at: i), !(free(i - 1) && v.every.contains(tokens[i - 1].folded)),
                          let count = calendar.range(of: .day, in: .month, for: today)?.count,
                          let date = makeDate(day: count, month: calendar.component(.month, from: today), year: calendar.component(.year, from: today), today: today) {
                    day = date
                    consumeDate(i...(i + length - 1))
                } else if let length = phrase(v.yearEndPhrases, at: i), let date = makeDate(day: 31, month: 12, year: nil, today: today) {
                    day = date
                    consumeDate(i...(i + length - 1))
                } else if let fixed = v.fixedDays.first(where: { phrase($0.phrases, at: i) != nil }),
                          let length = phrase(fixed.phrases, at: i),
                          let date = makeDate(day: fixed.day, month: fixed.month, year: nil, today: today) {
                    day = date
                    consumeDate(i...(i + length - 1))
                } else if let length = phrase(v.nextWeekPhrases, at: i) {
                    // "önümüzdeki hafta salı", "next week tuesday": that day of next week. Alone it is a week from today.
                    let after = i + length
                    if let weekendLength = phrase(v.weekendDatePhrases, at: after - 1) {
                        // "önümüzdeki hafta sonu": the weekend of next week.
                        day = weekendSaturday(next: true)
                        consumeDate(i...(after - 1 + weekendLength - 1))
                    } else if free(after), let weekday = Self.weekday(of: tokens[after].folded, v, cued: true) {
                        day = dayInNextWeek(weekday, from: today)
                        var last = after
                        if free(last + 1), v.weekdayMarkers.contains(tokens[last + 1].folded) { last += 1 }
                        consumeDate(i...last)
                    } else if let weekendLength = phrase(v.weekendDatePhrases, at: after) {
                        day = weekendSaturday(next: true)
                        consumeDate(i...(after + weekendLength - 1))
                    } else {
                        day = calendar.date(byAdding: .day, value: 7, to: today)
                        consumeDate(i...(i + length - 1))
                    }
                } else if v.todayWords.contains(word) {
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
                } else if let length = phrase(v.nextMonthPhrases, at: i),
                          let next = calendar.date(byAdding: .month, value: 1, to: today),
                          let first = calendar.dateInterval(of: .month, for: next)?.start {
                    // "gelecek ay vize": the first of next month, to be moved once the day is known.
                    day = first
                    consumeDate(i...(i + length - 1))
                } else if rule.isRepeating, repeatEnd == nil, (free(i - 1) && v.untilPrefixWords.contains(tokens[i - 1].folded))
                            || (free(i + 1) && v.deadlineSuffixWords.contains(tokens[i + 1].folded)),
                          let monthNumber = Self.month(of: word, v),
                          !(free(i + 1) && Self.dayNumber(tokens[i + 1].folded, v) != nil) {
                    // "every month until december", "her ay aralığa kadar": a bare month ends the series the month before.
                    var parts = calendar.dateComponents([.year], from: today)
                    parts.year = (parts.year ?? 0) + (monthNumber < calendar.component(.month, from: today) ? 1 : 0)
                    parts.month = monthNumber
                    parts.day = 1
                    if let first = calendar.date(from: parts) {
                        day = first
                        bareMonthDate = true
                        consumeDate(i...i)
                        bareMonthDate = false
                    }
                } else if let month = monthAlone(at: i) {
                    day = month.first
                    bareMonthDate = true
                    consumeDate(month.range)
                    bareMonthDate = false
                } else if v.monthWord.contains(word), let named = monthDay(after: i + 1), let next = nextDate(withDay: named.day) {
                    // "ayın 15'i kira": the coming 15th, once ("her ayın 15'i" is the monthly repeat, read above).
                    day = next
                    consumeDate(i...named.last)
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
                    // "tuesday next week".
                    var nextWeek = false
                    if let length = phrase(v.nextWeekPhrases, at: last + 1) {
                        day = dayInNextWeek(weekday, from: today)
                        last += length
                        nextWeek = true
                    }
                    weekdayDate = nextWeek ? nil : weekday
                    consumeDate(i...last)
                    weekdayDate = nil
                } else if let (length, date) = relativeDate(at: i) {
                    day = date
                    consumeDate(i...(i + length - 1))
                } else if let found = monthFirstDate(at: i) {
                    // "kasımın 15'i", "mayıs ayının 5'i", "mayıs 5".
                    day = found.date
                    consumeDate(i...found.last)
                } else if let number = Self.dayNumber(word, v), let monthAt = monthSlot(after: i),
                          let month = Self.month(of: tokens[monthAt].folded, v) {
                    // "15 kasım", "15th of november".
                    let year = free(monthAt + 1) ? Self.year(tokens[monthAt + 1].folded) : nil
                    if let date = makeDate(day: number, month: month, year: year, today: today) {
                        day = date
                        consumeDate(withLead(i...(monthAt + (year == nil ? 0 : 1))))
                    }
                } else if !v.ordinalSuffixes.isEmpty, free(i - 1), v.monthDayFillers.contains(tokens[i - 1].folded),
                          withLead(i...i).map({ tokens[$0].folded }).contains("on"),
                          let number = Self.dayNumber(word, v), word.last?.isASCIIDigit == false,
                          let next = nextDate(withDay: number) {
                    // "on the 15th": the coming 15th. A bare "the 3rd" is usually a thing ("the 3rd floor").
                    day = next
                    consumeDate(withLead(i...i))
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
        if rule.isRepeating, repeatEnd == nil, let start = day {
            // "pazartesiden itibaren cumaya kadar her gün": the start came first, the end is still to be found.
            endOnlyPass = true
            day = nil
            scanDates(allowShortDotted: false)
            endOnlyPass = false
            day = start
        }

        // Times. A bare hour needs a reason: "saat"/"at" in front, a locative ending ("18'de"),
        // a following am/pm, or a day part in front ("akşam 8").
        var minute: Int?
        /// The far-end token of the range found by the last `timeCandidate` call, if any.
        var lastFar: String?
        /// True when the last start found was moved from a 12-hour reading ("saat 3" → 15:00, "akşam 8").
        var lastStartShifted = false
        var endMinute: Int?

        /// "sekizde", "on ikide", "dokuz buçukta", "eight thirty": an hour in words, with the index of its last
        /// token. `cued` is false for a bare number word ("sekiz", "eight") or an everyday word ("birde", "onda"),
        /// which are a time only after "saat"/"at", a day part or am/pm.
        func writtenHour(at j: Int) -> (hour: Int, minute: Int, last: Int, cued: Bool)? {
            guard free(j) else { return nil }
            func read(_ word: String) -> (value: Int, base: String, suffixed: Bool)? {
                let plain = Self.withoutSuffix(word)
                if let value = v.hourWords[plain] { return (value, plain, plain != word) }
                if let value = v.irregularHourForms[word] { return (value, word, true) }
                for suffix in v.hourWordSuffixes where plain.hasSuffix(suffix) {
                    let base = String(plain.dropLast(suffix.count))
                    if let value = v.hourWords[base] { return (value, base, true) }
                }
                return nil
            }
            var hour: Int
            var last = j
            var cued: Bool
            if let tens = v.compoundHourTens[tokens[j].folded], free(j + 1),
               let unit = read(tokens[j + 1].folded), unit.value <= tens.maxUnit {
                // "on iki", "on ikide": a two-word hour is not an everyday phrase, an ending is enough.
                hour = tens.value + unit.value
                last = j + 1
                cued = unit.suffixed
            } else if let single = read(tokens[j].folded) {
                hour = single.value
                cued = single.suffixed && !v.cueOnlyHourWords.contains(single.base)
            } else {
                return nil
            }
            guard (0...23).contains(hour) else { return nil }
            var minute = 0
            if free(last + 1), v.halfHourWords.contains(tokens[last + 1].folded) {
                minute = 30
                last += 1
                if v.halfHourEndings.contains(tokens[last].folded) { cued = true }
            } else if free(last + 1), let written = v.minuteWords[tokens[last + 1].folded] {
                minute = written
                last += 1
                cued = true
            }
            return (hour, minute, last, cued)
        }

        /// The far end of a time range after the time ending at `end`: "- 15:00", "ile 5 arası", "to 5".
        /// A bare number as the far end needs "arası" after it ("ile 15 kişi" is not a range).
        /// "from 2 to 4": a range opened by a word of its own needs no "arası" after a bare far end.
        var rangeCued = false
        func rangeTail(after end: Int) -> (last: Int, far: String)? {
            // "20:00 21:30 toplantı": two clock times side by side are a range with the dash left out.
            if free(end + 1), Self.clockParts(tokens[end].folded, v) != nil, Self.clockParts(tokens[end + 1].folded, v) != nil {
                return (end + 1, tokens[end + 1].folded)
            }
            guard free(end + 1), v.rangeJoiners.contains(tokens[end + 1].folded), free(end + 2) else { return nil }
            let far = tokens[end + 2].folded
            let hasEnder = free(end + 3) && v.rangeEnders.contains(tokens[end + 3].folded)
            if Self.clockParts(far, v) != nil { return (hasEnder ? end + 3 : end + 2, far) }
            let bare = Self.bareHour(far, v) != nil || v.hourWords[far] != nil
            guard bare, hasEnder || rangeCued else { return nil }
            return (hasEnder ? end + 3 : end + 2, far)
        }

        /// An hour 1-12 read the way a spoken hour is: after a day part ("akşam"), or "3" meaning 15:00.
        func spokenHour(_ hour: Int, part: DayPart?) -> Int {
            if (1...12).contains(hour), let part { return Self.hour(hour, in: part) }
            return (1...6).contains(hour) ? hour + 12 : hour
        }

        /// An hour with an ending that is not "de/da": "dokuza", "9'a", "dokuzu", "9 u". `last` is its final token.
        func endedHour(at j: Int, endings: Set<String>, irregular: [String: Int]) -> (hour: Int, last: Int)? {
            guard free(j) else { return nil }
            func read(_ word: String) -> Int? {
                if let value = irregular[word] { return value }
                let plain = Self.withoutSuffix(word)
                for ending in endings.sorted(by: { $0.count > $1.count }) where plain.hasSuffix(ending) {
                    if let value = v.hourWords[String(plain.dropLast(ending.count))] { return value }
                }
                return nil
            }
            let word = tokens[j].folded
            let digits = String(word.prefix(while: \.isASCIIDigit))
            if !digits.isEmpty, digits.count <= 2, let hour = Int(digits), (0...23).contains(hour) {
                var rest = String(word.dropFirst(digits.count))
                if rest.hasPrefix("'") || rest.hasPrefix("’") { rest.removeFirst() }
                if endings.contains(rest) { return (hour, j) }
                if rest.isEmpty, free(j + 1), endings.contains(tokens[j + 1].folded) { return (hour, j + 1) }
                return nil
            }
            if let tens = v.compoundHourTens[word], free(j + 1), let unit = read(tokens[j + 1].folded), unit <= tens.maxUnit {
                return (tens.value + unit, j + 1)
            }
            if let value = read(word), (0...23).contains(value) { return (value, j) }
            return nil
        }

        /// "çeyrek", "10", "on": minutes in front of "var"/"geçe".
        func clockAmount(at j: Int) -> Int? {
            guard free(j) else { return nil }
            let word = tokens[j].folded
            if v.quarterWords.contains(word) { return 15 }
            if let number = Self.smallNumber(word), number <= 59 { return number }
            if let written = v.hourWords[word], [5, 10, 20].contains(written) { return written }
            return nil
        }

        /// Turkish "dokuza çeyrek var" (08:45), "beşe 10 var", "onu çeyrek geçe" (10:15), "9 u 15 geçe"; English
        /// "quarter past 9", "quarter to 10", "half past 7". The hour is read like any spoken hour.
        func clockWords(at j: Int, part: DayPart?) -> (last: Int, minute: Int, shifted: Bool)? {
            guard free(j) else { return nil }
            func result(_ hour: Int, _ offset: Int, last: Int, spoken: Bool = true) -> (last: Int, minute: Int, shifted: Bool)? {
                let adjusted = spoken ? spokenHour(hour, part: part) : hour
                let total = adjusted * 60 + offset
                guard (0..<(24 * 60)).contains(total) else { return nil }
                return (last, total, adjusted != hour)
            }
            if v.language == .english {
                guard v.quarterWords.contains(tokens[j].folded) || tokens[j].folded == "half", free(j + 1), free(j + 2) else { return nil }
                let amount = tokens[j].folded == "half" ? 30 : 15
                let word = tokens[j + 1].folded
                let isPast = v.plusClockWords.contains(word)
                guard isPast || (amount == 15 && v.minusClockWords.contains(word)) else { return nil }
                let hourWord = tokens[j + 2].folded
                guard let hour = Self.bareHour(hourWord, v).flatMap({ $0.hasSuffix ? nil : $0.hour }) ?? v.hourWords[hourWord],
                      (1...12).contains(hour)
                else { return nil }
                let offset = isPast ? amount : -amount
                if free(j + 3), let pm = Self.meridiem(tokens[j + 3].folded) {
                    return result(Self.twentyFourHour(hour, minute: 0, meridiem: pm) / 60, offset, last: j + 3, spoken: false)
                }
                return result(hour, offset, last: j + 2)
            }
            // Turkish: "dokuza çeyrek var".
            if let hour = endedHour(at: j, endings: v.dativeSuffixes, irregular: v.irregularHourForms),
               let amount = clockAmount(at: hour.last + 1), free(hour.last + 2), v.minusClockWords.contains(tokens[hour.last + 2].folded) {
                return result(hour.hour, -amount, last: hour.last + 2)
            }
            // Turkish: "dokuzu çeyrek geçe".
            if let hour = endedHour(at: j, endings: v.accusativeEndings, irregular: v.irregularAccusativeHourForms),
               let amount = clockAmount(at: hour.last + 1), free(hour.last + 2), v.plusClockWords.contains(tokens[hour.last + 2].folded) {
                return result(hour.hour, amount, last: hour.last + 2)
            }
            return nil
        }

        /// Turkish "2'den 4'e", "2 den 4 e", "14:00'den 16:00'ya": a range of hours, with the start and far ends as
        /// plain numbers and the index of its last token.
        func ablativeRange(at j: Int) -> (start: String, far: String, last: Int)? {
            guard !v.ablativeSuffixes.isEmpty, free(j) else { return nil }
            func isNumber(_ text: String) -> Bool {
                !text.isEmpty && text.allSatisfy { $0.isASCIIDigit || $0 == ":" || $0 == "." }
            }
            func strip(_ token: String, endings: Set<String>) -> String? {
                for ending in endings.sorted(by: { $0.count > $1.count }) where token.hasSuffix(ending) {
                    var base = String(token.dropLast(ending.count))
                    if base.hasSuffix("'") || base.hasSuffix("’") { base.removeLast() }
                    if isNumber(base) { return base }
                }
                return nil
            }
            func isHour(_ text: String) -> Bool {
                if Self.clockParts(text, v) != nil { return true }
                return text.count <= 2 && text.allSatisfy(\.isASCIIDigit) && (Int(text).map { (0...23).contains($0) } ?? false)
            }
            var start: String
            var next: Int
            if let base = strip(tokens[j].folded, endings: v.ablativeSuffixes) {
                start = base
                next = j + 1
            } else if isNumber(tokens[j].folded), free(j + 1), v.ablativeSuffixes.contains(tokens[j + 1].folded) {
                start = tokens[j].folded
                next = j + 2
            } else {
                return nil
            }
            guard free(next) else { return nil }
            var far: String
            var last: Int
            if let base = strip(tokens[next].folded, endings: v.dativeSuffixes) {
                far = base
                last = next
            } else if isNumber(tokens[next].folded), free(next + 1), v.dativeSuffixes.contains(tokens[next + 1].folded) {
                far = tokens[next].folded
                last = next + 1
            } else {
                return nil
            }
            guard isHour(start), isHour(far) else { return nil }
            if free(last + 1), v.rangeEnders.contains(tokens[last + 1].folded) { last += 1 }
            return (start, far, last)
        }

        func timeCandidate(at j: Int, prefixed: Bool, part: DayPart?) -> (end: Int, minute: Int)? {
            lastFar = nil
            guard let found = timeStart(at: j, prefixed: prefixed, part: part) else { return nil }
            if lastFar == nil, let tail = rangeTail(after: found.end) {
                lastFar = tail.far
                return (tail.last, found.minute)
            }
            return (found.end, found.minute)
        }

        func timeStart(at j: Int, prefixed: Bool, part: DayPart?) -> (end: Int, minute: Int)? {
            guard free(j) else { return nil }
            if let words = clockWords(at: j, part: part) {
                lastStartShifted = words.shifted
                return (words.last, words.minute)
            }
            // "13:00-15:00" written as one word: the start is the time. Two bare numbers ("3-5") are a range only
            // with "arası" after them, so a dashed date or a score is left alone.
            var token = tokens[j].folded
            var rangeEnd: Int?
            /// "2-4pm": the am/pm at the far end is the start's too.
            var startMeridiem: Bool?
            if let range = ablativeRange(at: j) {
                token = range.start
                lastFar = range.far
                rangeEnd = range.last
            } else if let dash = token.firstIndex(where: { $0 == "-" || $0 == "–" }) {
                let head = String(token[..<dash])
                let tail = String(token[token.index(after: dash)...])
                let clockRange = Self.clockParts(head, v) != nil && Self.clockParts(tail, v) != nil
                let bareRange = Self.bareHour(head, v) != nil && Self.bareHour(tail, v) != nil
                    && free(j + 1) && v.rangeEnders.contains(tokens[j + 1].folded)
                var meridiemRange = false
                if v.usesMeridiem, let headHour = Self.bareHour(head, v), !headHour.hasSuffix, (1...12).contains(headHour.hour),
                   let far = Self.clockParts(tail, v), let pm = far.pm {
                    meridiemRange = true
                    startMeridiem = pm ? !(headHour.hour > far.hour && headHour.hour != 12) : false
                }
                guard clockRange || bareRange || meridiemRange else { return nil }
                token = head
                lastFar = tail
                // "13:00-15:00 arası": the "arası" after a clock range belongs to it too.
                let enderFollows = free(j + 1) && v.rangeEnders.contains(tokens[j + 1].folded)
                rangeEnd = bareRange || (enderFollows && !meridiemRange) ? j + 1 : j
            }
            let hour: Int
            var minutes: Int
            var last = j
            var meridiemValue: Bool?
            var leadingZero = false
            /// Said the way an hour is spoken ("3'te", "üçte", "üç buçukta"), not read off a clock ("3:00").
            var spoken = false
            if let clock = Self.clockParts(token, v) {
                hour = clock.hour
                minutes = clock.minute
                meridiemValue = clock.pm
                leadingZero = clock.leadingZero
                // "14:00 da": the ending typed as a word of its own.
                if rangeEnd == nil, free(j + 1), v.locativeSuffixes.contains(tokens[j + 1].folded) { last = j + 1 }
            } else if let bare = Self.bareHour(token, v) {
                // "8 buçukta", "saat 8 buçuk": half past. With its ending ("buçukta") it also makes the 8 an hour;
                // a bare "buçuk" does not ("2 buçuk kilo").
                let half = rangeEnd == nil && !bare.hasSuffix && free(j + 1) && v.halfHourWords.contains(tokens[j + 1].folded)
                let halfWithEnding = half && v.halfHourEndings.contains(tokens[j + 1].folded)
                // "18 de", "6 da": the ending typed as a word of its own.
                let spacedEnding = rangeEnd == nil && !bare.hasSuffix && !half && free(j + 1)
                    && v.locativeSuffixes.contains(tokens[j + 1].folded)
                let followedByMeridiem = v.usesMeridiem && free(j + 1) && Self.meridiem(tokens[j + 1].folded) != nil
                // "3 ile 5 arası ders": the range itself says these are hours.
                let startsRange = rangeEnd == nil && !bare.hasSuffix && !v.rangeEnders.isEmpty && rangeTail(after: j) != nil
                if startsRange { rangeEnd = j }
                // "14e", "9a", "2ye doğru": the direction ending makes it an hour only for a late hour, a day part or a
                // hedge after it ("3'e böl" and "10a sınıfı" are not times).
                let hedgeFollows = free(j + 1) && v.timeHedgeWords.contains(tokens[j + 1].folded)
                let dativeHour = bare.dative && (bare.hour >= 7 || part != nil || hedgeFollows)
                    && !(free(j + 1) && v.dativeHourBlockers.contains(tokens[j + 1].folded))
                let allowed = prefixed || bare.locative || halfWithEnding || spacedEnding || rangeEnd != nil || dativeHour
                    || (!bare.hasSuffix && (part != nil || followedByMeridiem))
                guard allowed else { return nil }
                hour = bare.hour
                minutes = half ? 30 : 0
                if half || spacedEnding { last = j + 1 }
                leadingZero = bare.leadingZero
                spoken = bare.locative || halfWithEnding || spacedEnding || rangeEnd != nil || dativeHour
            } else if let written = writtenHour(at: j) {
                let followedByMeridiem = v.usesMeridiem && free(written.last + 1) && Self.meridiem(tokens[written.last + 1].folded) != nil
                guard written.cued || prefixed || part != nil || followedByMeridiem else { return nil }
                hour = written.hour
                minutes = written.minute
                last = written.last
                spoken = true
            } else {
                return nil
            }

            if meridiemValue == nil, let startMeridiem, (1...12).contains(hour) { meridiemValue = startMeridiem }
            if let meridiemValue {
                lastStartShifted = meridiemValue
                return (last, Self.twentyFourHour(hour, minute: minutes, meridiem: meridiemValue))
            }
            if v.usesMeridiem, free(last + 1), (1...12).contains(hour), let spoken = Self.meridiem(tokens[last + 1].folded) {
                lastStartShifted = spoken
                return (last + 1, Self.twentyFourHour(hour, minute: minutes, meridiem: spoken))
            }
            last = max(last, rangeEnd ?? last)
            lastStartShifted = false
            var adjusted = hour
            if (1...12).contains(hour), let part {
                adjusted = Self.hour(hour, in: part)
            } else if prefixed || spoken, (1...6).contains(hour), !leadingZero {
                // "saat 3", "3'te", "üçte": nobody plans a meeting for three at night; that is "gece 3".
                adjusted = hour + 12
            }
            lastStartShifted = adjusted != hour
            return (last, adjusted * 60 + minutes)
        }

        // "10 dakika sonra çayı kapat", "1 saat sonra", "in 20 minutes": a time counted from now. The day
        // follows below (past midnight it is tomorrow).
        for index in tokens.indices where minute == nil && free(index) && free(index + 1) && free(index + 2) {
            var count: Int?
            var unitIndex = index + 1
            if v.relativeBefore.contains(tokens[index].folded) {
                count = Self.smallNumber(tokens[index + 1].folded) ?? v.hourWords[tokens[index + 1].folded]
                unitIndex = index + 2
            } else if v.relativeAfter.contains(tokens[index + 2].folded) {
                count = Self.smallNumber(tokens[index].folded) ?? v.hourWords[tokens[index].folded]
            }
            guard let count, let perUnit = v.relativeTimeUnits[tokens[unitIndex].folded],
                  let target = calendar.date(byAdding: .minute, value: count * perUnit, to: now)
            else { continue }
            minute = calendar.component(.hour, from: target) * 60 + calendar.component(.minute, from: target)
            consume(index...(index + 2), as: .time)
        }

        var scannedTime = false
        i = 0
        while i < tokens.count, minute == nil {
            guard free(i) else { i += 1; continue }
            var adjacentPart = dayPart.flatMap { $0.end + 1 == i ? $0.kind : nil }
            let prefixed = v.timePrefixWords.contains(tokens[i].folded) && free(i + 1)
            // "from 2 to 4": the word that opens a range of hours, only when a far end follows.
            let opener = !prefixed && v.rangeStartWords.contains(tokens[i].folded) && free(i + 1)
            let target = prefixed || opener ? i + 1 : i
            var fromMeal = false
            if adjacentPart == nil, let mealPart, mealPart.blocker + 1 == i,
               prefixed || Self.bareHour(tokens[target].folded, v)?.locative == true || writtenHour(at: target)?.cued == true {
                adjacentPart = mealPart.kind
                fromMeal = true
            }
            rangeCued = opener
            let candidate = timeCandidate(at: target, prefixed: prefixed || opener, part: adjacentPart)
            rangeCued = false
            if let found = candidate, !opener || lastFar != nil {
                minute = found.minute
                scannedTime = true
                if let far = lastFar { endMinute = Self.rangeEnd(far, start: found.minute, startShifted: lastStartShifted, v) }
                var lower = i
                if adjacentPart != nil, !fromMeal, let dayPart, (dayPart.start...dayPart.end).allSatisfy({ free($0) }) {
                    lower = dayPart.start
                }
                // "saat 2 gibi", "around 3pm": a hedge around the time is not part of the title.
                var upper = found.end
                if free(upper + 1), v.timeHedgeWords.contains(tokens[upper + 1].folded) { upper += 1 }
                if free(lower - 1), v.timeHedgePrefixWords.contains(tokens[lower - 1].folded) { lower -= 1 }
                consume(lower...upper, as: .time)
            }
            i += 1
        }

        // "yarın 14:00 2 saat toplantı", "2pm for 2 hours": a length of time after a stated start is the end.
        // Without a start it stays in the title, and so does one that would run past midnight.
        if scannedTime, endMinute == nil, let start = minute {
            for index in tokens.indices where free(index) {
                var at = index
                if v.durationPrefixWords.contains(tokens[index].folded), free(index + 1) { at = index + 1 }
                guard free(at), free(at + 1),
                      let count = Self.smallNumber(tokens[at].folded) ?? v.hourWords[tokens[at].folded],
                      let perUnit = v.durationUnits[tokens[at + 1].folded]
                else { continue }
                let end = start + count * perUnit
                guard end <= 24 * 60 else { continue }
                endMinute = end
                consume(index...(at + 1), as: .time)
                break
            }
        }

        var minuteFromDayPart = false
        if let dayPart, (dayPart.start...dayPart.end).allSatisfy({ free($0) }),
           minute != nil || dayPart.defaultMinute != nil || everyDayPart || dayPart.isThis || dayPart.possessive {
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
                      nowMinute < Self.endMinute(of: dayPart.kind), minute != 0 {
                // "akşam annemi ara" while it is still evening: today, not tomorrow. (A morning that has
                // passed still means tomorrow morning.)
                day = today
            } else if let minute {
                day = minute > nowMinute ? today : calendar.date(byAdding: .day, value: 1, to: today)
            }
        }

        // The end of the series: a date named with "until", or a length counted from the first day.
        if !rule.isRepeating {
            repeatEnd = nil
        } else if repeatEnd == nil, let span, let start = day {
            // A span counts from the first occurrence: "every monday for 3 weeks" starts on the coming Monday.
            let first = firstOccurrence(from: start)
            let amount = span.unit == .weekOfYear ? span.count * 7 : span.count
            let unit: Calendar.Component = span.unit == .weekOfYear ? .day : span.unit
            repeatEnd = calendar.date(byAdding: unit, value: amount, to: first).flatMap { calendar.date(byAdding: .day, value: -1, to: $0) }
        }
        if let end = repeatEnd {
            // An end before the first occurrence would leave a series that never shows: it is dropped.
            repeatEnd = day.map { calendar.startOfDay(for: end) >= firstOccurrence(from: $0) } == true ? calendar.startOfDay(for: end) : nil
        }

        // "alarm" only means something with a time; without one it stays part of the title ("alarm saati al").
        // It has to sit at either end of the line or next to what was understood, so a word in the middle
        // of a sentence is left alone.
        var alarm = false
        var alarmWords: ClosedRange<Int>?
        if minute != nil {
            func touchesUnderstood(_ index: Int) -> Bool {
                guard index >= 0, index < tokens.count else { return false }
                return used.contains(index)
            }
            var index = 0
            while index < tokens.count, !alarm {
                if let length = phrase(v.alarmPhrases, at: index) {
                    let last = index + length - 1
                    if index == 0 || last == tokens.count - 1 || touchesUnderstood(index - 1) || touchesUnderstood(last + 1) {
                        consume(index...last, as: .alarm)
                        alarm = true
                        alarmWords = index...last
                    }
                }
                index += 1
            }
        }

        let listID = matchList(tokens: tokens, used: used, lists: lists, highlights: &highlights)

        var title = tokens.enumerated()
            .filter { !used.contains($0.offset) }
            .map(\.element.raw)
            .joined(separator: " ")
        // "hafta içi 7:30 alarm": nothing else was said, so the alarm is the task. Its name is the word itself,
        // otherwise there would be nothing to add.
        if title.isEmpty, let alarmWords {
            title = alarmWords.map { tokens[$0].raw }.joined(separator: " ")
        }

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
            highlights: highlights.sorted { $0.range.lowerBound < $1.range.lowerBound },
            alarm: alarm,
            endMinute: minute == nil ? nil : endMinute,
            repeatEnd: repeatEnd
        )
    }

    // MARK: Tokens

    /// Dashes a keyboard may put between two times ("20:00—21:30", a minus sign): read as "–".
    private static let otherDashes: Set<Character> = ["—", "−", "‒", "―"]

    private static func tokenize(_ text: String) -> [Token] {
        let characters = Array(text).map { otherDashes.contains($0) ? "–" : $0 }
        let trimSet = CharacterSet(charactersIn: ",;:!?()\"“”.")
        var tokens: [Token] = []
        var start = 0
        while start < characters.count {
            if characters[start].isWhitespace { start += 1; continue }
            var end = start
            while end < characters.count, !characters[end].isWhitespace { end += 1 }
            // "20:00 -21:30", "20:00- 21:30": a dash stuck to one side of a word is a word of its own.
            var pieces = [start..<end]
            if end - start > 1, characters[start] == "-" || characters[start] == "–" {
                pieces = [start..<(start + 1), (start + 1)..<end]
            } else if end - start > 1, characters[end - 1] == "-" || characters[end - 1] == "–" {
                pieces = [start..<(end - 1), (end - 1)..<end]
            }
            for piece in pieces {
                let raw = String(characters[piece])
                let core = raw.trimmingCharacters(in: trimSet)
                tokens.append(Token(raw: raw, folded: TurkishText.fold(core), range: piece))
            }
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

    /// A weekday after an ordinal: "pazartesi", and in Turkish the possessive "pazartesisi", "cuması".
    private static func positionWeekday(_ token: String, _ v: Vocabulary) -> Int? {
        if let day = weekday(of: token, v, cued: true) { return day }
        for suffix in v.possessiveWeekdaySuffixes where token.hasSuffix(suffix) {
            if let day = weekday(of: String(token.dropLast(suffix.count)), v, cued: true) { return day }
        }
        return nil
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

    /// Minute of a range's far end. am/pm, a 24-hour value and a leading zero ("09:00") are literal. A 12-hour
    /// value that would not be after the start is read 12 hours later, but only when the start itself was a
    /// 12-hour reading ("saat 3 ile 5 arası", "11 ile 1 arası"): "20:00-09:00" is a night shift, not 20–21.
    /// nil unless strictly after `start` within the day (night shifts get no end).
    private static func rangeEnd(_ far: String, start: Int, startShifted: Bool, _ v: Vocabulary) -> Int? {
        let followsStart = startShifted || start < 12 * 60
        var end: Int
        if let clock = clockParts(far, v) {
            if let pm = clock.pm {
                end = twentyFourHour(clock.hour, minute: clock.minute, meridiem: pm)
            } else {
                end = clock.hour * 60 + clock.minute
                // "3:00 ile 5:00 arası" after a start read as 15:00: a 12-hour clock end follows the start.
                if end <= start, clock.hour < 12, !clock.leadingZero, followsStart { end += 12 * 60 }
            }
        } else if let bare = bareHour(far, v), !bare.leadingZero || bare.hour * 60 > start {
            end = bare.hour * 60
            if end <= start, followsStart { end += 12 * 60 }
        } else if let hour = v.hourWords[far] {
            end = hour * 60
            if end <= start, followsStart { end += 12 * 60 }
        } else {
            return nil
        }
        return end > start && end <= 24 * 60 ? end : nil
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
        // "21:30da": the ending stuck to the clock.
        if !v.clockEndings.isEmpty {
            let digits = String(base.prefix(while: { $0.isASCIIDigit || $0 == ":" || $0 == "." }))
            if !digits.isEmpty, v.clockEndings.contains(String(base.dropFirst(digits.count))) { base = digits }
        }
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
    private static func bareHour(_ token: String, _ v: Vocabulary) -> (hour: Int, leadingZero: Bool, hasSuffix: Bool, locative: Bool, dative: Bool)? {
        let apostrophe = token.firstIndex(where: { $0 == "'" || $0 == "’" })
        var base = apostrophe.map { String(token[..<$0]) } ?? token
        var suffix = apostrophe.map { String(token[token.index(after: $0)...]) }
        // People often leave the apostrophe out: "8de", "18de".
        if apostrophe == nil {
            let digits = String(token.prefix(while: \.isASCIIDigit))
            let rest = String(token.dropFirst(digits.count))
            if !digits.isEmpty, v.locativeSuffixes.contains(rest) || v.dativeSuffixes.contains(rest) { base = digits; suffix = rest }
        }
        guard !base.isEmpty, base.count <= 2, base.allSatisfy(\.isASCIIDigit),
              let hour = Int(base), (0...23).contains(hour)
        else { return nil }
        let locative = suffix.map { v.locativeSuffixes.contains($0) } ?? false
        let dative = suffix.map { v.dativeSuffixes.contains($0) } ?? false
        return (hour, base.count == 2 && base.hasPrefix("0"), suffix != nil, locative, dative)
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

    /// Words that name what kind of course or list it is, not which one: "Tıbbi Görüntüleme Giriş" is not
    /// what "KPSS giriş belgesi" is about. In a name of several words they never match on their own.
    private static let genericListWords: Set<String> = [
        "giris", "girisi", "temel", "temelleri", "genel", "ileri", "ders", "dersi", "dersleri",
        "uygulama", "uygulamalari", "uygulamali", "proje", "projesi", "bilgi", "bilgisi", "bilgileri",
        "kurs", "kursu", "seminer", "semineri", "notlar", "notlari", "lab", "laboratuvar", "laboratuvari",
        "isleri", "yonetim", "yonetimi", "sistem", "sistemleri", "ve", "ile", "icin",
        "intro", "introduction", "to", "the", "and", "of", "basic", "basics", "general", "advanced",
        "project", "notes", "course", "class", "lab", "applied", "principles", "fundamentals",
    ]

    private func matchList(tokens: [Token], used: Set<Int>, lists: [ListRef], highlights: inout [Highlight]) -> UUID? {
        var best: (score: Int, listID: UUID, tokens: ClosedRange<Int>)?
        for list in lists {
            let allWords = TurkishText.fold(list.name)
                .split(separator: " ")
                .map(String.init)
            // The whole name, word for word ("ev işleri"); the last word may carry an ending ("tıbbi görüntülemeye").
            if allWords.count > 1, tokens.count >= allWords.count {
                for start in 0...(tokens.count - allWords.count) {
                    let run = start...(start + allWords.count - 1)
                    guard !run.contains(where: used.contains) else { continue }
                    let matches = zip(run, allWords).allSatisfy { index, listWord in
                        let word = tokens[index].folded
                        return word == listWord || (index == run.upperBound && listWord.count >= 4 && word.hasPrefix(listWord))
                    }
                    let score = 100 + allWords.joined().count
                    if matches, score > (best?.score ?? 0) {
                        best = (score, list.id, run)
                    }
                }
            }
            let words = allWords
                .filter { $0.count >= 3 }
                .filter { allWords.count == 1 || !Self.genericListWords.contains($0) }
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
                        best = (score, list.id, index...index)
                    }
                }
            }
        }
        guard let best else { return nil }
        let range = tokens[best.tokens.lowerBound].range.lowerBound..<tokens[best.tokens.upperBound].range.upperBound
        highlights.append(Highlight(kind: .list, range: range))
        return best.listID
    }
}

private extension Character {
    var isASCIIDigit: Bool { self >= "0" && self <= "9" }
}
