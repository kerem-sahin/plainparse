import Foundation

/// ISO weekday numbers: 1 = Monday ... 7 = Sunday. These numbers are stored in the
/// database (fixed slots, repeat masks), so they never change.
public enum Weekday {
    public static let weekdaysMask = 0b0011111
    public static let weekendMask = 0b1100000

    public static func iso(of date: Date, calendar: Calendar) -> Int {
        let sundayFirst = calendar.component(.weekday, from: date)
        return (sundayFirst + 5) % 7 + 1
    }

    public static func bit(_ iso: Int) -> Int {
        1 << (iso - 1)
    }

    public static func mask(_ mask: Int, contains iso: Int) -> Bool {
        mask & bit(iso) != 0
    }

    public static func isos(in mask: Int) -> [Int] {
        (1...7).filter { Weekday.mask(mask, contains: $0) }
    }
}
