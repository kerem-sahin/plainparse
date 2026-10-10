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

/// The words the quick-add parser listens for in one language. All entries are already folded
/// (lowercase, no Turkish letters) because tokens are folded before they are compared.
struct Vocabulary: Sendable {
    var language: ParserLanguage
    var capitalizationLocale: Locale

    var every: Set<String>
    var dayWord: Set<String>
    var weekWord: Set<String>
    var monthWord: Set<String>
    /// Phrases that mean "Monday to Friday" on their own ("hafta ici", "weekdays").
    var weekdaysPhrases: [[String]]
    var weekendPhrases: [[String]]
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

    var weekdayNames: [(iso: Int, names: [String])]
    var weekdaySuffixes: Set<String>
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
    var usesMeridiem: Bool
    var slashDateDayFirst: Bool

    static let turkish = Vocabulary(
        language: .turkish,
        capitalizationLocale: TurkishText.locale,
        every: ["her"],
        dayWord: ["gun"],
        weekWord: ["hafta"],
        monthWord: ["ay"],
        weekdaysPhrases: [["hafta", "ici"]],
        weekendPhrases: [["hafta", "sonu"]],
        dailyAlone: [],
        weeklyAlone: [],
        monthlyAlone: [],
        todayWords: ["bugun"],
        tomorrowWords: ["yarin"],
        dayAfterTomorrow: [["obur", "gun"], ["obur", "gunu"]],
        nextPrefixes: ["haftaya"],
        nextAloneMeansWeek: true,
        weekdayNames: [
            (1, ["pazartesi"]), (2, ["sali"]), (3, ["carsamba"]), (4, ["persembe"]),
            (5, ["cuma"]), (6, ["cumartesi"]), (7, ["pazar"]),
        ],
        weekdaySuffixes: ["ya", "ye", "a", "e", "dan", "den", "ki"],
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
            weekdaysPhrases: [["weekdays"], ["weekday"]],
            weekendPhrases: [["weekends"], ["weekend"]],
            dailyAlone: [["daily"]],
            weeklyAlone: [["weekly"]],
            monthlyAlone: [["monthly"]],
            todayWords: ["today", "tonight"],
            tomorrowWords: ["tomorrow", "tmrw", "tmr"],
            dayAfterTomorrow: [["day", "after", "tomorrow"]],
            nextPrefixes: ["next"],
            nextAloneMeansWeek: false,
            weekdayNames: [
                (1, ["monday"]), (2, ["tuesday", "tue", "tues"]), (3, ["wednesday", "wed"]),
                (4, ["thursday", "thu", "thur", "thurs"]), (5, ["friday", "fri"]),
                (6, ["saturday"]), (7, ["sunday"]),
            ],
            weekdaySuffixes: [],
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
