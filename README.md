# PlainParse

**Turn one plain sentence into a task, in Turkish or English.**

PlainParse reads a line like `Cuma fizyoloji ödevi 18:00` or `friday math homework 6pm` and works out the title, the day, the time, the repeat rule, the list and whether it should ring as an alarm. Foundation only, no dependencies, no network, no AI model: it runs instantly on the device.

It powers the quick-add bar of [plainday](https://apps.apple.com/tr/app/plainday/id6823780735), a day planner for iPhone.

| Input | Title | Day | Time | Repeat |
|---|---|---|---|---|
| `Cuma fizyoloji ödevi 18:00` | Fizyoloji ödevi | Friday | 18:00 | – |
| `yarın annemi ara 18:00` | Annemi ara | tomorrow | 18:00 | – |
| `bu akşam sinema` | Sinema | today | 19:00 | – |
| `her sabah 7de alarm vitamin` | Vitamin | today | 07:00 | daily, ⏰ alarm |
| `hafta içi her gün spor` | Spor | | | Mon–Fri |
| `her pazartesi ve çarşamba yüzme` | Yüzme | | | Mon, Wed |
| `friday math homework 6pm` | Math homework | Friday | 18:00 | – |
| `every monday and wednesday swim` | Swim | | | Mon, Wed |
| `buy milk` | Buy milk | – | – | – |

*(Real output, with "now" set to Monday 19 October 2026, 10:00.)*

## Why

Most natural-language date parsers are English-first. Turkish is agglutinative: the time hides inside suffixes (`7'de`, `7de`, `saat 5'te`), weekdays are written with or without dotted letters (`çarşamba`, `carsamba`), and `15.10` can be a date or a time. PlainParse handles these the way people actually type on a phone, and falls back to English when that understands more of the sentence.

## Usage

```swift
import PlainParse

let parser = QuickAddParser(preferredLanguage: .turkish)
let entry = parser.parse("Cuma fizyoloji ödevi 18:00", now: .now)

entry.title      // "Fizyoloji ödevi"
entry.day        // next Friday
entry.minute     // 1080 (18:00, minutes after midnight)
entry.rule       // RepeatRule(kind: .none)
entry.highlights // ranges of "Cuma" and "18:00", to highlight them as the user types
```

Pass your lists to have a sentence filed into one:

```swift
let lists = [ListRef(id: schoolID, name: "Okul")]
parser.parse("okul sunum hazırla perşembe", now: .now, lists: lists).listID // schoolID
```

`RepeatRule.occurs(on:startingFrom:calendar:)` tells you whether a repeating task falls on a given day.

## What it understands

- **Days**: bugün / today, yarın / tomorrow, öbür gün / day after tomorrow, weekday names (always the next one), `next tuesday`, `next week`
- **Dates**: `15 ekim`, `oct 15`, `october 15th`, `15/10`, `10/15` (day or month first from the locale)
- **Times**: `18:00`, `18.30`, `6pm`, `7'de`, `7de`, `bu akşam`, `sabah`; after `saat` / `at`, a bare hour from 1 to 6 means the afternoon (`saat 3` → 15:00)
- **Repeats**: her gün / every day, her sabah, hafta içi / weekdays, her hafta sonu / every weekend, `her pazartesi ve çarşamba`, her ay / monthly
- **Alarms**: `alarm`, `alarmlı`, `with an alarm` (only together with a time, so "alarm saati al" is just a task)

## Install

Swift Package Manager:

```swift
.package(url: "https://github.com/kerem-sahin/plainparse.git", branch: "main")
```

iOS 17+ / macOS 14+, Swift 6.

## Tests

150 tests, most of them real phrases:

```bash
swift test
```

## License

MIT. Made by [Kerem Şahin](https://github.com/kerem-sahin).

---

<details>
<summary>🇹🇷 Türkçe</summary>

**PlainParse**, tek satırlık düz bir cümleyi göreve çeviren bir Swift paketi: "Cuma fizyoloji ödevi 18:00" → başlık, gün, saat, tekrar, liste ve alarm. Türkçenin ekleriyle (`7'de`, `7de`), noktasız yazılan gün adlarıyla ve `15.10` gibi belirsiz ifadelerle başa çıkar; anlamazsa İngilizceyi dener. Bağımlılık yok, internet yok, yapay zekâ modeli yok; cihazda anında çalışır. plainday uygulamasının hızlı ekleme çubuğu bununla çalışıyor.

</details>
