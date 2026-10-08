import Foundation
import Metadata

// File timestamps are absolute instants. Missing offsets use the user's local time zone.
enum MetadataFileTime {
    static func parse(_ text: String) throws -> Date {
        guard text.range(of: #"^\d{4}:\d{2}:\d{2} \d{2}:\d{2}:\d{2}(\.\d{1,9})?(Z|[+-]\d{2}:\d{2})?$"#, options: .regularExpression) != nil else {
            throw Exiftool.ExiftoolError.invalidTagValue(tag: "System:FileDate")
        }
        var metadata = Metadata(source: .image(URL(fileURLWithPath: "/")))
        let fraction = text.range(of: #"\.\d+"#, options: .regularExpression)
        metadata.dateTimeCreated = fraction.map { text.replacingCharacters(in: $0, with: "") } ?? text
        guard let date = metadata.parsedDate(timeZone: .current) else {
            throw Exiftool.ExiftoolError.invalidTagValue(tag: "System:FileDate")
        }
        return date.addingTimeInterval(fraction.flatMap { Double(text[$0]) } ?? 0)
    }

    static func text(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        let seconds = floor(date.timeIntervalSince1970)
        let fraction = Int(((date.timeIntervalSince1970 - seconds) * 1_000_000).rounded())
        let base = Date(timeIntervalSince1970: seconds + (fraction == 1_000_000 ? 1 : 0))
        let main = formatter.string(from: base) + String(format: ".%06d", fraction % 1_000_000)
        formatter.dateFormat = "XXXXX"
        return main + formatter.string(from: base)
    }

    static func partial(_ text: String, tag: MetadataTag) throws -> String {
        let dateOnly = tag == .iptcDateCreated
        // Copying a complete shooting timestamp selects just the IPTC component.
        var value = text
        if text.count >= 19 && text.dropFirst(10).first == " " {
            let offset = String(text.dropFirst(19)).replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
            value = dateOnly ? String(text.prefix(10)) : String(text.dropFirst(11).prefix(8)) + offset
        }
        let pattern = dateOnly ? #"^\d{4}:\d{2}:\d{2}$"# : #"^\d{2}:\d{2}:\d{2}(Z|[+-]\d{2}:\d{2})$"#
        guard value.range(of: pattern, options: .regularExpression) != nil else {
            throw Exiftool.ExiftoolError.invalidTagValue(tag: tag.rawValue)
        }
        let format = dateOnly ? "yyyy:MM:dd" : "HH:mm:ssXXXXX"
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.isLenient = false
        formatter.dateFormat = format
        guard let date = formatter.date(from: value) else { throw Exiftool.ExiftoolError.invalidTagValue(tag: tag.rawValue) }
        if dateOnly && formatter.string(from: date) != value { throw Exiftool.ExiftoolError.invalidTagValue(tag: tag.rawValue) }
        return value.replacingOccurrences(of: "Z", with: "+00:00")
    }
}
