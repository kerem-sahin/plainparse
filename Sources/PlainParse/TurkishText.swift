import Foundation

public enum TurkishText {
    public static let locale = Locale(identifier: "tr_TR")

    /// Lowercases with Turkish rules and strips Turkish letters to ASCII, so "Şubat", "SUBAT" and "subat" match.
    public static func fold(_ text: String) -> String {
        let lower = text.precomposedStringWithCanonicalMapping.lowercased(with: locale)
        var folded = ""
        folded.reserveCapacity(lower.count)
        for character in lower {
            switch character {
            case "ı": folded.append("i")
            case "ş": folded.append("s")
            case "ç": folded.append("c")
            case "ğ": folded.append("g")
            case "ö": folded.append("o")
            case "ü": folded.append("u")
            case "â": folded.append("a")
            case "î": folded.append("i")
            case "û": folded.append("u")
            default: folded.append(character)
            }
        }
        return folded
    }

    /// Uppercases the first letter with Turkish rules ("istanbul" becomes "İstanbul").
    public static func capitalizedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return String(first).uppercased(with: locale) + text.dropFirst()
    }
}
