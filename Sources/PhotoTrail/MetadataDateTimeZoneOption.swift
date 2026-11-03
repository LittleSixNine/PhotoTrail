import Foundation

struct MetadataDateTimeZoneOption: Identifiable {
    let offset: String
    let identifier: String
    var daylight = false
    var id: String { offset }

    // Labels describe standard offsets; selecting one never enables automatic DST conversion.
    func label(locale: Locale) -> String {
        let region = offset == "-12:00" ? L10n.text("贝克岛、豪兰岛")
            : TimeZone(identifier: identifier)?.localizedName(for: daylight ? .daylightSaving : .standard, locale: locale) ?? identifier
        return "UTC" + offset + " · " + region
    }

    static let common: [Self] = [
        ("-12:00", "Etc/GMT+12"), ("-11:00", "Pacific/Niue"),
        ("-10:00", "Pacific/Honolulu"), ("-09:30", "Pacific/Marquesas"),
        ("-09:00", "America/Anchorage"), ("-08:00", "America/Los_Angeles"),
        ("-07:00", "America/Denver"), ("-06:00", "America/Chicago"),
        ("-05:00", "America/New_York"), ("-04:00", "America/Halifax"),
        ("-03:30", "America/St_Johns"), ("-03:00", "America/Argentina/Buenos_Aires"),
        ("-02:00", "Atlantic/South_Georgia"), ("-01:00", "Atlantic/Azores"),
        ("+00:00", "Europe/London"), ("+01:00", "Europe/Paris"),
        ("+02:00", "Europe/Helsinki"), ("+03:00", "Asia/Riyadh"),
        ("+03:30", "Asia/Tehran"), ("+04:00", "Asia/Dubai"),
        ("+04:30", "Asia/Kabul"), ("+05:00", "Asia/Karachi"),
        ("+05:30", "Asia/Kolkata"), ("+05:45", "Asia/Kathmandu"),
        ("+06:00", "Asia/Dhaka"), ("+06:30", "Asia/Yangon"),
        ("+07:00", "Asia/Bangkok"), ("+08:00", "Asia/Shanghai"),
        ("+08:45", "Australia/Eucla"), ("+09:00", "Asia/Tokyo"),
        ("+09:30", "Australia/Darwin"), ("+10:00", "Australia/Brisbane"),
        ("+10:30", "Australia/Lord_Howe"), ("+11:00", "Pacific/Guadalcanal"),
        ("+12:00", "Pacific/Fiji"), ("+12:45", "Pacific/Chatham"),
        ("+13:00", "Pacific/Tongatapu"), ("+14:00", "Pacific/Kiritimati")
    ].map { Self(offset: $0.0, identifier: $0.1) }

    static var options: [Self] {
        var values = common
        values.insert(Self(offset: "-02:30", identifier: "America/St_Johns", daylight: true), at: 12)
        values.insert(Self(offset: "+13:45", identifier: "Pacific/Chatham", daylight: true), at: values.count - 1)
        return values
    }
}
