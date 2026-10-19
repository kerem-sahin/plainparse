import Foundation

public enum ParserLanguage: Sendable {
    case turkish
    case english

    /// The first of the user's preferred languages that the parser knows, else English.
    public static var deviceDefault: ParserLanguage {
        let code = Locale.preferredLanguages.first?.prefix(2).lowercased() ?? "en"
        return code == "tr" ? .turkish : .english
    }
}

/// A part of the day ("akşam", "morning") that hints at a time and shifts bare hours that follow it.
enum DayPart: Sendable {
    case morning, noon, afternoon, evening, night
}

struct DayPartWord: Sendable {
    var phrases: [[String]]
    var kind: DayPart
    /// Minute of the day used when no explicit time is given; nil when the word only shifts a following hour.
    var defaultMinute: Int?
}

/// The words the quick-add parser listens for in one language. All entries are already folded
/// (lowercase, no Turkish letters) because tokens are folded before they are compared.
struct Vocabulary: Sendable {
    var language: ParserLanguage
    var capitalizationLocale: Locale

    var every: Set<String>
    var dayWord: Set<String>
    var weekWord: Set<String>
    var monthWord: Set<String>
    /// Words between "every month" and the day of the month ("on the 1st").
    var monthDayFillers: Set<String>
    /// Endings that make a number a day of the month ("1'i", "2'sinde").
    var monthDayEndings: Set<String>
    /// Phrases that mean "Monday to Friday" on their own ("hafta ici", "weekdays").
    var weekdaysPhrases: [[String]]
    var weekendPhrases: [[String]]
    /// "weekend" as a one-off date (the coming Saturday). Plural forms stay repeat-only.
    var weekendDatePhrases: [[String]]
    /// Phrases that repeat without "every" ("daily", "weekly", "monthly").
    var dailyAlone: [[String]]
    var weeklyAlone: [[String]]
    var monthlyAlone: [[String]]

    var todayWords: Set<String>
    var tomorrowWords: Set<String>
    var dayAfterTomorrow: [[String]]
    /// Words that push a weekday into next week ("haftaya", "next").
    var nextPrefixes: Set<String>
    var nextAloneMeansWeek: Bool
    /// "bu", "this": a no-op word in front of a weekday, weekend or day part.
    var thisPrefixes: Set<String>
    /// Count before the unit ("in 3 days") or after it ("3 gün sonra").
    var relativeBefore: Set<String>
    var relativeAfter: Set<String>
    var relativeUnits: [String: Calendar.Component]

    var weekdayNames: [(iso: Int, names: [String])]
    var weekdaySuffixes: Set<String>
    /// Weekday names that are also ordinary nouns ("pazar" is Sunday and market): they only count
    /// in the exact form and with a cue (followed by a marker or a time, or after "bu"/"haftaya"/"her").
    var ambiguousWeekdayNames: Set<String>
    /// Words that follow a weekday and belong to it ("günü").
    var weekdayMarkers: Set<String>
    var monthNames: [[String]]
    var monthSuffixes: Set<String>
    var monthFirstAllowed: Bool
    var ordinalSuffixes: Set<String>
    var conjunctions: Set<String>
    var deadlineSuffixWords: Set<String>
    var deadlinePrefixWords: Set<String>
    var timePrefixWords: Set<String>
    /// Endings allowed after an apostrophe on a bare hour ("18'de").
    var locativeSuffixes: Set<String>
    var dayParts: [DayPartWord]
    /// Words after a day-part word that make it part of a noun ("akşam yemeği").
    var dayPartBlockers: Set<String>
    /// Words that ask for an alarm instead of a notification, longest first ("alarm kur" before "alarm").
    var alarmPhrases: [[String]]
    /// Hours written as words: "sekiz", "eight".
    var hourWords: [String: Int]
    /// The first word of a two-word hour and the largest second word it takes: "on iki" (12), "yirmi üç" (23).
    var compoundHourTens: [String: (value: Int, maxUnit: Int)]
    /// Endings on a written hour that make it a time ("sekizde", "sekize").
    var hourWordSuffixes: [String]
    /// Written hours whose stem changes with the ending ("dört" → "dörde").
    var irregularHourForms: [String: Int]
    /// Written hours that are everyday words too ("birde", "onda", "ikide"): only a time after "saat" or a day part.
    var cueOnlyHourWords: Set<String>
    /// "buçuk", "buçukta": half past.
    var halfHourWords: Set<String>
    /// The half-past words that carry a time ending ("buçukta"): enough on their own to make a time.
    /// A bare "buçuk" is not ("iki buçuk kilo").
    var halfHourEndings: Set<String>
    /// Minutes written after a written hour: "eight thirty", "seven o'clock".
    var minuteWords: [String: Int]
    var usesMeridiem: Bool
    var slashDateDayFirst: Bool

    static let turkish = Vocabulary(
        language: .turkish,
        capitalizationLocale: TurkishText.locale,
        every: ["her"],
        dayWord: ["gun"],
        weekWord: ["hafta"],
        monthWord: ["ay", "ayin"],
        monthDayFillers: [],
        monthDayEndings: [
            "i", "ı", "u", "ü", "si", "sı", "su", "sü", "yi", "yı",
            "inde", "ında", "unda", "ünde", "sinde", "sında", "sunda", "sünde",
            "inda", "unde", "sinda", "sunde",
        ],
        weekdaysPhrases: [["hafta", "ici"]],
        weekendPhrases: [["hafta", "sonu"], ["haftasonu"]],
        weekendDatePhrases: [["hafta", "sonu"], ["haftasonu"]],
        dailyAlone: [],
        weeklyAlone: [],
        monthlyAlone: [],
        todayWords: ["bugun"],
        tomorrowWords: ["yarin"],
        dayAfterTomorrow: [["obur", "gun"], ["obur", "gunu"]],
        nextPrefixes: ["haftaya"],
        nextAloneMeansWeek: true,
        thisPrefixes: ["bu", "gelecek"],
        relativeBefore: [],
        relativeAfter: ["sonra"],
        relativeUnits: ["gun": .day, "hafta": .weekOfYear, "ay": .month],
        weekdayNames: [
            (1, ["pazartesi"]), (2, ["sali"]), (3, ["carsamba"]), (4, ["persembe"]),
            (5, ["cuma"]), (6, ["cumartesi"]), (7, ["pazar"]),
        ],
        weekdaySuffixes: ["ya", "ye", "a", "e", "dan", "den", "ki"],
        ambiguousWeekdayNames: ["pazar"],
        weekdayMarkers: ["gunu", "gunleri", "gunler"],
        monthNames: [
            ["ocak"], ["subat"], ["mart"], ["nisan"], ["mayis"], ["haziran"],
            ["temmuz"], ["agustos"], ["eylul"], ["ekim"], ["kasim"], ["aralik"],
        ],
        monthSuffixes: ["de", "da", "te", "ta", "e", "a", "den", "dan"],
        monthFirstAllowed: false,
        ordinalSuffixes: [],
        conjunctions: ["ve"],
        deadlineSuffixWords: ["kadar"],
        deadlinePrefixWords: [],
        timePrefixWords: ["saat"],
        locativeSuffixes: ["de", "da", "te", "ta"],
        dayParts: [
            DayPartWord(phrases: [["sabah"]], kind: .morning, defaultMinute: 9 * 60),
            DayPartWord(phrases: [["ogle"], ["oglen"]], kind: .noon, defaultMinute: 12 * 60),
            DayPartWord(phrases: [["aksam"]], kind: .evening, defaultMinute: 19 * 60),
            DayPartWord(phrases: [["gece"]], kind: .night, defaultMinute: nil),
        ],
        dayPartBlockers: [
            "yemegi", "yemek", "yemekleri", "kahvaltisi", "namazi", "ezani", "rutini",
            "haberleri", "ogunu", "vardiyasi", "nobeti",
        ],
        alarmPhrases: [["alarm", "kur"], ["alarmli"], ["alarmla"], ["alarm"]],
        hourWords: [
            "bir": 1, "iki": 2, "uc": 3, "dort": 4, "bes": 5, "alti": 6, "yedi": 7, "sekiz": 8, "dokuz": 9,
            "on": 10, "yirmi": 20,
        ],
        compoundHourTens: ["on": (10, 9), "yirmi": (20, 3)],
        hourWordSuffixes: ["de", "da", "te", "ta", "ye", "ya", "e", "a"],
        irregularHourForms: ["dorde": 4],
        cueOnlyHourWords: ["bir", "iki", "on"],
        halfHourWords: ["bucuk", "bucukta", "bucukda", "bucuga"],
        halfHourEndings: ["bucukta", "bucukda", "bucuga"],
        minuteWords: [:],
        usesMeridiem: false,
        slashDateDayFirst: true
    )

    static func english(slashDateDayFirst: Bool) -> Vocabulary {
        Vocabulary(
            language: .english,
            capitalizationLocale: Locale(identifier: "en_US"),
            every: ["every", "each"],
            dayWord: ["day"],
            weekWord: ["week"],
            monthWord: ["month"],
            monthDayFillers: ["on", "the"],
            monthDayEndings: [],
            weekdaysPhrases: [["weekdays"], ["weekday"]],
            weekendPhrases: [["weekends"], ["weekend"]],
            weekendDatePhrases: [["weekend"]],
            dailyAlone: [["daily"]],
            weeklyAlone: [["weekly"]],
            monthlyAlone: [["monthly"]],
            todayWords: ["today", "tonight"],
            tomorrowWords: ["tomorrow", "tmrw", "tmr"],
            dayAfterTomorrow: [["day", "after", "tomorrow"]],
            nextPrefixes: ["next"],
            nextAloneMeansWeek: false,
            thisPrefixes: ["this"],
            relativeBefore: ["in"],
            relativeAfter: [],
            relativeUnits: [
                "day": .day, "days": .day, "week": .weekOfYear, "weeks": .weekOfYear,
                "month": .month, "months": .month,
            ],
            weekdayNames: [
                (1, ["monday"]), (2, ["tuesday", "tue", "tues"]), (3, ["wednesday", "wed"]),
                (4, ["thursday", "thu", "thur", "thurs"]), (5, ["friday", "fri"]),
                (6, ["saturday"]), (7, ["sunday"]),
            ],
            weekdaySuffixes: [],
            ambiguousWeekdayNames: [],
            weekdayMarkers: [],
            monthNames: [
                ["january", "jan"], ["february", "feb"], ["march"], ["april", "apr"], ["may"], ["june"],
                ["july"], ["august", "aug"], ["september", "sep", "sept"], ["october", "oct"],
                ["november", "nov"], ["december", "dec"],
            ],
            monthSuffixes: [],
            monthFirstAllowed: true,
            ordinalSuffixes: ["st", "nd", "rd", "th"],
            conjunctions: ["and"],
            deadlineSuffixWords: [],
            deadlinePrefixWords: ["by", "until", "before", "on"],
            timePrefixWords: ["at"],
            locativeSuffixes: [],
            dayParts: [
                DayPartWord(phrases: [["morning"]], kind: .morning, defaultMinute: 9 * 60),
                DayPartWord(phrases: [["noon"]], kind: .noon, defaultMinute: 12 * 60),
                DayPartWord(phrases: [["afternoon"]], kind: .afternoon, defaultMinute: 15 * 60),
                DayPartWord(phrases: [["evening"]], kind: .evening, defaultMinute: 18 * 60),
                DayPartWord(phrases: [["tonight"]], kind: .evening, defaultMinute: 20 * 60),
                DayPartWord(phrases: [["midnight"]], kind: .night, defaultMinute: 0),
            ],
            dayPartBlockers: ["routine", "news"],
            alarmPhrases: [["with", "an", "alarm"], ["with", "alarm"], ["set", "an", "alarm"], ["set", "alarm"], ["alarm"]],
            hourWords: [
                "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
                "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
            ],
            compoundHourTens: [:],
            hourWordSuffixes: [],
            irregularHourForms: [:],
            // Every English hour word is an everyday number: it is a time only with "at", am/pm or minutes.
            cueOnlyHourWords: ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"],
            halfHourWords: [],
            halfHourEndings: [],
            minuteWords: ["fifteen": 15, "thirty": 30, "forty-five": 45, "o'clock": 0, "oclock": 0],
            usesMeridiem: true,
            slashDateDayFirst: slashDateDayFirst
        )
    }

    /// Whether the user's region writes the day before the month in numeric dates (15/10 and not 10/15).
    static func localeWritesDayFirst(_ locale: Locale) -> Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "Md", options: 0, locale: locale) ?? "Md"
        guard let day = format.firstIndex(of: "d"), let month = format.firstIndex(of: "M") else { return false }
        return day < month
    }
}
