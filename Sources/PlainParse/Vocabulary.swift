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
    /// "cuma akşamı": the possessive form is a part of the day only right after a weekday, "yarın" or "bugün".
    var needsDayBefore: Bool = false
}

/// A named day with a fixed date ("yılbaşı", "christmas").
struct FixedDay: Sendable {
    var phrases: [[String]]
    var month: Int
    var day: Int
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
    /// "her yıl", "every year": the year word after "every", and the phrases that repeat yearly on their own
    /// ("yılda bir", "yearly"). The date that follows is the day it repeats on.
    var yearWord: Set<String>
    var yearlyAlone: [[String]]

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
    /// "10 dakika sonra", "in 2 hours": a time counted from now, in minutes per unit.
    var relativeTimeUnits: [String: Int]
    /// "13:00 - 15:00", "3 ile 5 arası": the word between the two ends of a time range, and the word after it.
    /// Only the start is kept; a task has one time.
    var rangeJoiners: Set<String>
    var rangeEnders: Set<String>
    /// "2 haftada bir", "every 2 weeks": the week word after the count, the forms that need no "her"/"every"
    /// in front ("haftada"; a bare "2 hafta" is a length), and the word that may close the phrase ("bir").
    var intervalWeekWords: Set<String>
    var intervalCuedWords: Set<String>
    var intervalTail: Set<String>
    var everyOtherWeekPhrases: [[String]]
    /// A month on its own ("Haziran'da", "in June") is its first day. The word that may follow it ("ayında"),
    /// the word that must come before it in English ("in": "may" and "march" are verbs too).
    var monthAloneFollowers: Set<String>
    var monthAlonePrefixes: Set<String>
    var nextMonthPhrases: [[String]]
    var usesMeridiem: Bool
    var slashDateDayFirst: Bool

    /// "salıları", "mondays": endings that make a weekday name a plural, which means every such weekday.
    var pluralWeekdaySuffixes: Set<String> = []
    /// "salı günleri": a marker after a weekday that makes it a repeat.
    var pluralWeekdayMarkers: Set<String> = []
    /// "hafta sonları", "weekends": the weekend as a repeat on its own.
    var weekendPluralPhrases: [[String]] = []
    /// Words in front of a plural weekday that belong to it ("on mondays").
    var pluralPrefixWords: Set<String> = []
    /// "every other", "every second": a weekly repeat that skips a week when a weekday follows.
    var everyOtherPhrases: [[String]] = []
    /// Endings that may stick to a clock time ("21:30da") or a bare hour.
    var clockEndings: Set<String> = []
    /// "9a", "14e": the direction ending, an hour only when something else says it is one.
    var dativeSuffixes: Set<String> = []
    /// Words after a bare hour with a direction ending that make it a name instead ("10a sınıfı").
    var dativeHourBlockers: Set<String> = []
    /// "2'den 4'e": the "from" ending of the start of a range.
    var ablativeSuffixes: Set<String> = []
    /// "gibi", "doğru" after a time, "around" before it: hedges that are not part of the title.
    var timeHedgeWords: Set<String> = []
    var timeHedgePrefixWords: Set<String> = []
    /// "çeyrek", "quarter"; and "dokuza çeyrek var", "quarter to 10".
    var quarterWords: Set<String> = []
    var minusClockWords: Set<String> = []
    var plusClockWords: Set<String> = []
    /// Endings on an hour that is the object of "geçe" ("dokuzu çeyrek geçe").
    var accusativeEndings: Set<String> = []
    var dayMonthFillers: Set<String> = []
    /// "kasımın 15'i": the endings of a month name followed by its day, and the words that may sit between.
    var monthGenitiveSuffixes: Set<String> = []
    var monthGenitiveFillers: Set<String> = []
    /// "mayıs 5": a bare month name followed by a bare number is a date.
    var monthFirstBareNumber: Bool = false
    /// Words after such a number that make it a count, not a day ("mart 3 hafta").
    var numberNounBlockers: Set<String> = []
    var nextWeekPhrases: [[String]] = []
    var deadlinePrefixPhrases: [[String]] = []
    var startBoundSuffixWords: Set<String> = []
    var startBoundPrefixWords: Set<String> = []
    var monthEndPhrases: [[String]] = []
    var yearEndPhrases: [[String]] = []
    var weekEndPhrases: [[String]] = []
    var fixedDays: [FixedDay] = []
    /// "her ayın ilk günü": the first day of the month.
    var firstDayPhrases: [[String]] = []
    /// "ilk", "second", "son", "last": a position in the month (1...4, last = 5).
    var ordinalValues: [String: Int] = [:]
    /// "son günü", "last day": the last day of the month, after an ordinal.
    var lastDayPhrases: [[String]] = []
    /// "her ay sonu", "her ayın sonu": the word that makes it the last day of the month.
    var monthEndWords: Set<String> = []
    /// "pazartesisi", "cuması": endings that make a weekday name possessive after an ordinal ("ayın ilk cuması").
    var possessiveWeekdaySuffixes: Set<String> = []
    /// "first monday of every month" always repeats; "of the month" repeats only after "every".
    var monthTailEveryPhrases: [[String]] = []
    var monthTailThePhrases: [[String]] = []
    /// "2 günde bir", "every 2 days", "3 ayda bir", "every 3 months": the unit word after the count, and the
    /// forms that need no "her"/"every" ("günde", "ayda"; a bare "2 gün" or "3 ay" is a length).
    var intervalDayWords: Set<String> = []
    var intervalDayCuedWords: Set<String> = []
    var intervalMonthWords: Set<String> = []
    var intervalMonthCuedWords: Set<String> = []
    var everyOtherDayPhrases: [[String]] = []
    var everyOtherMonthPhrases: [[String]] = []
    var quarterlyPhrases: [[String]] = []
    /// "2 saat", "45 dk", "for 2 hours": a length of time, in minutes per unit, and the word before it.
    var durationUnits: [String: Int] = [:]
    var durationPrefixWords: Set<String> = []
    /// "from 2 to 4": the word that opens a range of hours.
    var rangeStartWords: Set<String> = []
    /// "akşam yemeği 8'de": the meal after a day part still says which part of the day the hour is in.
    var mealWords: Set<String> = []
    var irregularAccusativeHourForms: [String: Int] = [:]
    /// "until friday": a word before a date that ends a repeat (Turkish uses the "kadar" after it).
    var untilPrefixWords: Set<String> = []
    /// "3 gün boyunca": the word after "count unit"; "for 3 days": the word before it; "for a week": "a".
    var spanAfterWords: Set<String> = []
    var spanBeforeWords: Set<String> = []
    var spanArticleWords: Set<String> = []

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
        weekdaysPhrases: [["hafta", "ici"], ["hafta", "icleri"]],
        weekendPhrases: [["hafta", "sonu"], ["haftasonu"]],
        weekendDatePhrases: [["hafta", "sonu"], ["haftasonu"]],
        dailyAlone: [["hergun"]],
        weeklyAlone: [],
        monthlyAlone: [["ayda", "bir"]],
        yearWord: ["yil", "sene"],
        // "yıllık" alone is left out: "yıllık izin" is a noun.
        yearlyAlone: [["yilda", "bir"], ["senede", "bir"]],
        todayWords: ["bugun", "bugunden"],
        tomorrowWords: ["yarin", "yarindan", "yarina"],
        dayAfterTomorrow: [["obur", "gun"], ["obur", "gunu"]],
        nextPrefixes: ["haftaya"],
        nextAloneMeansWeek: true,
        thisPrefixes: ["bu", "gelecek", "onumuzdeki"],
        relativeBefore: [],
        relativeAfter: ["sonra", "icinde"],
        relativeUnits: ["gun": .day, "hafta": .weekOfYear, "ay": .month],
        weekdayNames: [
            (1, ["pazartesi"]), (2, ["sali"]), (3, ["carsamba"]), (4, ["persembe"]),
            (5, ["cuma"]), (6, ["cumartesi"]), (7, ["pazar"]),
        ],
        weekdaySuffixes: ["ya", "ye", "a", "e", "dan", "den", "ki"],
        ambiguousWeekdayNames: ["pazar"],
        weekdayMarkers: ["gunu", "gunleri", "gunler"],
        monthNames: [
            ["ocak", "ocag"], ["subat"], ["mart"], ["nisan"], ["mayis"], ["haziran"],
            ["temmuz"], ["agustos"], ["eylul"], ["ekim"], ["kasim"], ["aralik", "aralig"],
        ],
        monthSuffixes: ["de", "da", "te", "ta", "e", "a", "den", "dan", "ten", "tan"],
        monthFirstAllowed: false,
        ordinalSuffixes: [],
        conjunctions: ["ve"],
        deadlineSuffixWords: ["kadar"],
        deadlinePrefixWords: [],
        timePrefixWords: ["saat"],
        locativeSuffixes: ["de", "da", "te", "ta"],
        dayParts: [
            DayPartWord(phrases: [["sabaha", "karsi"]], kind: .morning, defaultMinute: 5 * 60),
            DayPartWord(phrases: [["sabah"]], kind: .morning, defaultMinute: 9 * 60),
            DayPartWord(phrases: [["sabahi"]], kind: .morning, defaultMinute: 9 * 60, needsDayBefore: true),
            DayPartWord(phrases: [["ogleden", "sonra"], ["oglenden", "sonra"]], kind: .afternoon, defaultMinute: 15 * 60),
            DayPartWord(phrases: [["ogle"], ["oglen"], ["ogleyin"]], kind: .noon, defaultMinute: 12 * 60),
            DayPartWord(phrases: [["aksamustu"]], kind: .afternoon, defaultMinute: 17 * 60),
            DayPartWord(phrases: [["aksam"], ["aksama"]], kind: .evening, defaultMinute: 19 * 60),
            DayPartWord(phrases: [["aksami"]], kind: .evening, defaultMinute: 19 * 60, needsDayBefore: true),
            DayPartWord(phrases: [["gece", "yarisi"], ["gece", "yarisinda"]], kind: .night, defaultMinute: 0),
            DayPartWord(phrases: [["gece"]], kind: .night, defaultMinute: nil),
            DayPartWord(phrases: [["gecesi"]], kind: .night, defaultMinute: nil, needsDayBefore: true),
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
        relativeTimeUnits: ["dakika": 1, "dk": 1, "saat": 60],
        rangeJoiners: ["-", "–", "ile"],
        rangeEnders: ["arasi", "arasinda"],
        intervalWeekWords: ["hafta", "haftada"],
        intervalCuedWords: ["haftada"],
        intervalTail: ["bir"],
        everyOtherWeekPhrases: [["iki", "haftada", "bir"]],
        monthAloneFollowers: ["ayi", "ayinda"],
        monthAlonePrefixes: [],
        nextMonthPhrases: [["gelecek", "ay"], ["gelecek", "aya"], ["onumuzdeki", "ay"], ["onumuzdeki", "aya"], ["haftaya", "ay"]],
        usesMeridiem: false,
        slashDateDayFirst: true,
        pluralWeekdaySuffixes: ["lari", "leri"],
        pluralWeekdayMarkers: ["gunleri", "gunler"],
        weekendPluralPhrases: [["hafta", "sonlari"], ["haftasonlari"], ["hafta", "sonlarinda"]],
        clockEndings: ["de", "da", "te", "ta", "e", "a", "ye", "ya"],
        dativeSuffixes: ["e", "a", "ye", "ya"],
        dativeHourBlockers: ["sinifi", "sinif", "sube", "subesi"],
        ablativeSuffixes: ["den", "dan", "ten", "tan"],
        timeHedgeWords: ["gibi", "dogru", "civari", "civarinda"],
        quarterWords: ["ceyrek"],
        minusClockWords: ["var", "kala"],
        plusClockWords: ["gece"],
        accusativeEndings: ["i", "u", "yi", "yu"],
        monthGenitiveSuffixes: ["in", "un"],
        monthGenitiveFillers: ["ayinin", "ayin"],
        monthFirstBareNumber: true,
        numberNounBlockers: ["gun", "hafta", "ay", "saat", "dakika", "dk", "kez", "kisi", "adet", "tl", "lira", "kg", "yil"],
        nextWeekPhrases: [["onumuzdeki", "hafta"], ["gelecek", "hafta"]],
        deadlinePrefixPhrases: [["en", "gec"]],
        startBoundSuffixWords: ["itibaren", "baslayarak"],
        monthEndPhrases: [["ay", "sonu"], ["ay", "sonuna"], ["ay", "sonunda"], ["ayin", "sonu"], ["ayin", "sonuna"], ["ayin", "sonunda"], ["ayin", "son", "gunu"], ["ayin", "son", "gunune"], ["ayin", "son", "gununde"]],
        yearEndPhrases: [["yil", "sonu"], ["yil", "sonuna"], ["yil", "sonunda"], ["yilin", "sonu"], ["yilin", "sonuna"], ["yilin", "sonunda"]],
        weekEndPhrases: [["bu", "hafta", "icinde"], ["hafta", "sonuna"], ["haftanin", "sonuna"]],
        fixedDays: [
            FixedDay(phrases: [["yilbasi", "gecesi"], ["yilbasi", "aksami"]], month: 12, day: 31),
            // A bare "yılbaşı" is usually part of a noun ("yılbaşı hediyesi"): only the locative is a date.
            FixedDay(phrases: [["yilbasinda"]], month: 1, day: 1),
        ],
        firstDayPhrases: [["ilk", "gunu"]],
        ordinalValues: ["ilk": 1, "ikinci": 2, "ucuncu": 3, "dorduncu": 4, "son": 5],
        lastDayPhrases: [["son", "gunu"]],
        monthEndWords: ["sonu", "sonunda"],
        possessiveWeekdaySuffixes: ["si", "i"],
        intervalDayWords: ["gun", "gunde"],
        intervalDayCuedWords: ["gunde"],
        intervalMonthWords: ["ay", "ayda"],
        intervalMonthCuedWords: ["ayda"],
        everyOtherDayPhrases: [["gun", "asiri"], ["gunasiri"]],
        durationUnits: ["saat": 60, "saatlik": 60, "dakika": 1, "dk": 1, "dakikalik": 1, "dklik": 1],
        mealWords: ["yemegi", "yemek", "yemekleri", "kahvaltisi", "ogunu"],
        irregularAccusativeHourForms: ["dordu": 4],
        spanAfterWords: ["boyunca"]
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
            monthlyAlone: [["monthly"], ["once", "a", "month"]],
            yearWord: ["year"],
            yearlyAlone: [["yearly"], ["annually"]],
            todayWords: ["today", "tonight"],
            tomorrowWords: ["tomorrow", "tmrw", "tmr"],
            dayAfterTomorrow: [["day", "after", "tomorrow"]],
            nextPrefixes: ["next"],
            nextAloneMeansWeek: false,
            thisPrefixes: ["this"],
            relativeBefore: ["in", "within"],
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
            relativeTimeUnits: ["minute": 1, "minutes": 1, "min": 1, "mins": 1, "hour": 60, "hours": 60],
            rangeJoiners: ["-", "–", "to", "until"],
            rangeEnders: [],
            intervalWeekWords: ["weeks"],
            intervalCuedWords: [],
            intervalTail: [],
            everyOtherWeekPhrases: [["every", "other", "week"], ["biweekly"], ["bi-weekly"], ["fortnightly"], ["every", "fortnight"]],
            monthAloneFollowers: [],
            monthAlonePrefixes: ["in"],
            nextMonthPhrases: [["next", "month"]],
            usesMeridiem: true,
            slashDateDayFirst: slashDateDayFirst,
            pluralWeekdaySuffixes: ["s"],
            weekendPluralPhrases: [["weekends"]],
            pluralPrefixWords: ["on"],
            everyOtherPhrases: [["every", "other"], ["every", "second"], ["every", "2nd"]],
            timeHedgePrefixWords: ["around", "approximately"],
            quarterWords: ["quarter"],
            minusClockWords: ["to"],
            plusClockWords: ["past"],
            dayMonthFillers: ["of"],
            nextWeekPhrases: [["next", "week"]],
            startBoundPrefixWords: ["starting", "beginning", "from"],
            monthEndPhrases: [["end", "of", "month"], ["end", "of", "the", "month"], ["end", "of", "this", "month"], ["last", "day", "of", "the", "month"], ["last", "day", "of", "this", "month"]],
            yearEndPhrases: [["end", "of", "year"], ["end", "of", "the", "year"], ["end", "of", "this", "year"]],
            weekEndPhrases: [["end", "of", "week"], ["end", "of", "the", "week"], ["end", "of", "this", "week"]],
            fixedDays: [
                FixedDay(phrases: [["new", "year's", "eve"], ["new", "year’s", "eve"], ["new", "years", "eve"]], month: 12, day: 31),
                FixedDay(phrases: [["new", "year's", "day"], ["new", "year’s", "day"], ["new", "years", "day"]], month: 1, day: 1),
                FixedDay(phrases: [["christmas", "eve"]], month: 12, day: 24),
                // A bare "christmas" is usually a noun ("christmas gifts").
                FixedDay(phrases: [["christmas", "day"], ["on", "christmas"]], month: 12, day: 25),
            ],
            firstDayPhrases: [["first", "day"]],
            ordinalValues: ["first": 1, "1st": 1, "second": 2, "2nd": 2, "third": 3, "3rd": 3, "fourth": 4, "4th": 4, "last": 5],
            lastDayPhrases: [["last", "day"]],
            monthTailEveryPhrases: [["of", "every", "month"], ["of", "each", "month"], ["every", "month"]],
            monthTailThePhrases: [["of", "the", "month"]],
            intervalDayWords: ["days"],
            intervalMonthWords: ["months"],
            everyOtherDayPhrases: [["every", "other", "day"]],
            everyOtherMonthPhrases: [["every", "other", "month"]],
            quarterlyPhrases: [["every", "quarter"], ["quarterly"]],
            durationUnits: ["hour": 60, "hours": 60, "hr": 60, "hrs": 60, "minute": 1, "minutes": 1, "min": 1, "mins": 1],
            durationPrefixWords: ["for"],
            rangeStartWords: ["from"],
            untilPrefixWords: ["until", "till", "through", "thru"],
            spanBeforeWords: ["for"],
            spanArticleWords: ["a", "an"]
        )
    }

    /// Whether the user's region writes the day before the month in numeric dates (15/10 and not 10/15).
    static func localeWritesDayFirst(_ locale: Locale) -> Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "Md", options: 0, locale: locale) ?? "Md"
        guard let day = format.firstIndex(of: "d"), let month = format.firstIndex(of: "M") else { return false }
        return day < month
    }
}
