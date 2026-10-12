import Foundation

public enum MetadataDateError: Error { case invalidDate, missingDate, invalidSequence }

// Metadata without an offset remains a wall-clock value. It is never assigned UTC.
public struct MetadataDate: Equatable, Sendable {
    public let date: Date
    public let fraction: String
    public let offset: String

    public init(_ text: String) throws {
        let pattern = #"^(\d{4}):([0-9]{2}):([0-9]{2}) ([0-9]{2}):([0-9]{2}):([0-9]{2})(\.[0-9]{1,9})?(Z|[+-][0-9]{2}:[0-9]{2})?$"#
        let regex = try NSRegularExpression(pattern: pattern)
        let string = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: string.length)) else {
            throw MetadataDateError.invalidDate
        }
        func part(_ n: Int) -> String {
            let range = match.range(at: n)
            return range.location == NSNotFound ? "" : string.substring(with: range)
        }
        fraction = part(7)
        offset = part(8)
        guard let zone = Self.timeZone(offset) else { throw MetadataDateError.invalidDate }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let components = DateComponents(year: Int(part(1)), month: Int(part(2)), day: Int(part(3)),
                                        hour: Int(part(4)), minute: Int(part(5)), second: Int(part(6)))
        guard let result = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: result) == components else {
            throw MetadataDateError.invalidDate
        }
        date = result
    }

    private init(date: Date, fraction: String, offset: String) {
        self.date = date; self.fraction = fraction; self.offset = offset
    }

    private static func timeZone(_ offset: String) -> TimeZone? {
        if offset.isEmpty || offset == "Z" { return TimeZone(secondsFromGMT: 0) }
        let parts = offset.dropFirst().split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              hour <= 14, minute < 60, hour < 14 || minute == 0 else { return nil }
        return TimeZone(secondsFromGMT: (hour * 3600 + minute * 60) * (offset.first == "-" ? -1 : 1))
    }

    public var displayTimeZone: TimeZone { Self.timeZone(offset)! }

    public var text: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = Self.timeZone(offset)
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.string(from: date) + fraction + offset
    }

    public func shifting(seconds: Int) throws -> Self {
        let result = Self(date: date.addingTimeInterval(Double(seconds)), fraction: fraction, offset: offset)
        return try Self(result.text) // Reject dates outside the supported four-digit year.
    }

    public func offsetting(years: Int = 0, months: Int = 0, days: Int = 0,
                           hours: Int = 0, minutes: Int = 0, seconds: Int = 0) throws -> Self {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.timeZone(offset)!
        var result = date
        let offsets: [(Calendar.Component, Int, Int)] = [
            (.year, years, 9999), (.month, months, 120000), (.day, days, 3660000),
            (.hour, hours, 87840000), (.minute, minutes, 5270400000), (.second, seconds, 316224000000)
        ]
        for (component, amount, limit) in offsets where amount != 0 {
            guard (-limit...limit).contains(amount),
                  let changed = calendar.date(byAdding: component, value: amount, to: result),
                  (1...9999).contains(calendar.component(.year, from: changed)) else {
                throw MetadataDateError.invalidDate
            }
            if [.year, .month].contains(component),
               calendar.component(.day, from: changed) != calendar.component(.day, from: result) {
                throw MetadataDateError.invalidDate
            }
            result = changed
        }
        return try Self(Self(date: result, fraction: fraction, offset: offset).text)
    }

    public func addingCalendarDays(_ days: Int, timeZoneID: String?) throws -> Self {
        var calendar = Calendar(identifier: .gregorian)
        if let timeZoneID {
            guard !offset.isEmpty, let zone = TimeZone(identifier: timeZoneID),
                  zone.secondsFromGMT(for: date) == Self.timeZone(offset)?.secondsFromGMT() else {
                throw MetadataDateError.invalidDate
            }
            calendar.timeZone = zone
        } else { calendar.timeZone = Self.timeZone(offset)! }
        guard let changed = calendar.date(byAdding: .day, value: days, to: date) else {
            throw MetadataDateError.invalidDate
        }
        guard calendar.dateComponents([.hour, .minute, .second], from: changed)
            == calendar.dateComponents([.hour, .minute, .second], from: date) else { throw MetadataDateError.invalidDate }
        var suffix = offset
        if timeZoneID != nil {
            let seconds = calendar.timeZone.secondsFromGMT(for: changed)
            suffix = String(format: "%@%02d:%02d", seconds < 0 ? "-" : "+", abs(seconds) / 3600, abs(seconds) % 3600 / 60)
        }
        return try Self(Self(date: changed, fraction: fraction, offset: suffix).text)
    }

    public func replacing(_ component: Calendar.Component, with value: Int) throws -> Self {
        guard [.year, .month, .day, .hour, .minute, .second].contains(component) else {
            throw MetadataDateError.invalidDate
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.timeZone(offset)!
        var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        parts.setValue(value, for: component)
        guard let result = calendar.date(from: parts),
              calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: result) == parts else {
            throw MetadataDateError.invalidDate
        }
        return try Self(Self(date: result, fraction: fraction, offset: offset).text)
    }

    public static func sequence(start: String, stepSeconds: Int, count: Int) throws -> [String] {
        guard count > 0 else { throw MetadataDateError.invalidSequence }
        let first = try Self(start)
        return try (0..<count).map { index in
            let (delta, overflow) = stepSeconds.multipliedReportingOverflow(by: index)
            guard !overflow else { throw MetadataDateError.invalidSequence }
            return try first.shifting(seconds: delta).text
        }
    }

    // Integer seconds, nearest rounding; first and last endpoints are retained exactly.
    public static func distribute(start: String, end: String, count: Int) throws -> [String] {
        guard count > 0 else { throw MetadataDateError.invalidSequence }
        let first = try Self(start), last = try Self(end)
        guard first.offset == last.offset, first.fraction == last.fraction, last.date >= first.date else {
            throw MetadataDateError.invalidSequence
        }
        if count == 1 { return [first.text] }
        let interval = last.date.timeIntervalSince(first.date)
        return try (0..<count).map { try first.shifting(seconds: Int((interval * Double($0) / Double(count - 1)).rounded())).text }
    }
}
