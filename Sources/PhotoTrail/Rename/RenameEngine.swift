import Foundation
import NaturalLanguage

/// Pure name computation. File access and mutation belong to RenameExecutor.
enum RenameEngine {
    static func split(_ name: String) -> (stem: String, ext: String) {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return (name, "") }
        return (String(name[..<dot]), String(name[dot...]))
    }

    static func validName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && name.utf8.count <= 255 &&
        !name.contains("/") && !name.contains(":") && !name.unicodeScalars.contains { $0.value == 0 }
    }

    static func key(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.lowercased()
    }

    static func tag(_ token: String, input: RenameInput) -> String? {
        if let exact = input.tags[token], !exact.isEmpty { return exact }
        if ["DurationInSeconds", "Duration_MM_SS", "Duration_HH_MM_SS"].contains(token),
           let raw = tag("Duration", input: input), let seconds = durationSeconds(raw) {
            if token == "DurationInSeconds" { return String(seconds) }
            let total = Int(seconds.rounded(.down))
            return token == "Duration_MM_SS" ? padded(total / 60, width: 2) + "_" + padded(total % 60, width: 2) :
                padded(total / 3600, width: 2) + "_" + padded(total / 60 % 60, width: 2) + "_" + padded(total % 60, width: 2)
        }
        let aliases: [String: [String]] = [
            "CameraModel": ["Model"], "CameraMake": ["Make"], "CameraSerialNumber": ["SerialNumber"],
            "ImageCaption": ["Caption-Abstract", "Description", "ImageDescription"],
            "ImageKeywords": ["Keywords", "Subject"], "ImageUserComment": ["UserComment"],
            "Lens": ["LensModel", "LensID", "Lens"], "Aperture": ["FNumber", "Aperture"],
            "ShutterSpeed": ["ExposureTime", "ShutterSpeed"], "FocalLength35mm": ["FocalLengthIn35mmFormat"],
            "IPTCCity": ["City"], "IPTCCountry": ["Country-PrimaryLocationName", "Country"],
            "IPTCProvinceState": ["Province-State", "State"], "Artist": ["Artist", "Creator"],
            "Track": ["Track", "TrackNumber"], "TrackNum": ["Track", "TrackNumber"],
            "NumTracks": ["TrackCount", "TotalTracks"], "CDNum": ["DiscNumber", "DiskNumber"],
            "numCds": ["DiscCount", "TotalDiscs"], "Song": ["Title"],
            "AlbumArtist": ["AlbumArtist", "Band"], "AudioSampleRate": ["SampleRate", "AudioSampleRate"],
            "DurationInSeconds": ["Duration"], "width": ["ImageWidth"], "height": ["ImageHeight"],
            "ImageWidth": ["ImageWidth", "ExifImageWidth"], "ImageHeight": ["ImageHeight", "ExifImageHeight"]
        ]
        let candidates = aliases[token] ?? [token]
        for candidate in candidates {
            // Explicit family-qualified tokens are exact; unqualified tokens use stable family order.
            let matches = input.tags.keys.filter { $0.split(separator: ":").last.map(String.init) == candidate }.sorted()
            if let found = matches.first, let value = input.tags[found], !value.isEmpty {
                if token == "TrackNum" || token == "CDNum" { return value.components(separatedBy: "/").first }
                return value
            }
        }
        if token == "NumTracks" || token == "numCds" {
            let raw = tag(token == "NumTracks" ? "Track" : "DiscNumber", input: input)?.components(separatedBy: "/")
            if raw?.count == 2 { return raw?.last }
        }
        switch token {
        case "FileName": return input.name
        case "FileNameWithoutExtension": return split(input.name).stem
        case "FileExtension": return String(split(input.name).ext.dropFirst())
        case "ParentFolderName": return input.directory.lastPathComponent
        case "FilePath": return input.url.path
        case "NULL": return ""
        default:
            let casingBases = ["Artist", "Album", "Song", "AlbumArtist", "FileName", "FileExtension"]
            for base in casingBases where token != base {
                if token == base.lowercased() { return tag(base, input: input)?.lowercased() }
                if token == base.uppercased() { return tag(base, input: input)?.uppercased() }
                if token == base + "_sentence_case" || (base == "AlbumArtist" && token == "Album_Artist_sentence_case"),
                   let value = tag(base, input: input) {
                    return value.prefix(1).uppercased() + value.dropFirst().lowercased()
                }
                if token == base + "_Capitalized" { return tag(base, input: input)?.capitalized }
            }
            if token.hasPrefix("0"), let value = tag(String(token.dropFirst()), input: input),
               let number = Int(value.split(separator: "/").first ?? "") { return padded(number, width: 2) }
            if token.hasPrefix("UUID"), let uuid = input.tags["PhotoTrail:RenameUUID"] {
                let length = Int(token.dropFirst(4)) ?? 30
                return String(uuid.replacingOccurrences(of: "-", with: "").prefix(length))
            }
            return nil
        }
    }

    private static func durationSeconds(_ raw: String) -> Double? {
        let parts = raw.split(separator: ":")
        let value: Double?
        if parts.count > 1, parts.count <= 3, parts.allSatisfy({ Double($0) != nil }) {
            value = parts.reduce(0) { $0 * 60 + (Double($1) ?? 0) }
        } else { value = raw.split(separator: " ").first.flatMap { Double($0) } }
        guard let value, value.isFinite, value >= 0, value < 1_000_000_000 else { return nil }
        return value
    }

    struct ShotDate {
        var date: Date
        var zone: TimeZone
        var raw: String
        var offsetRecorded = true
    }

    static func parseDate(_ raw: String, offset: String? = nil) -> ShotDate? {
        // No offset means wall-clock time. UTC is a neutral container, not an inferred shooting timezone.
        let pattern = #"^(\d{4})[:-](\d{2})[:-](\d{2})[ T](\d{2}):(\d{2}):(\d{2})(\.\d+)?\s*(Z|[+-]\d{2}:?\d{2})?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)) else { return nil }
        func capture(_ n: Int) -> String {
            Range(match.range(at: n), in: raw).map { String(raw[$0]) } ?? ""
        }
        let zoneText = capture(8).isEmpty ? (offset ?? "") : capture(8)
        var seconds = 0
        if zoneText != "Z", !zoneText.isEmpty {
            let digits = zoneText.dropFirst().replacingOccurrences(of: ":", with: "")
            guard digits.count == 4, let hour = Int(digits.prefix(2)), let minute = Int(digits.suffix(2)),
                  hour <= 23, minute < 60 else { return nil }
            seconds = (zoneText.hasPrefix("-") ? -1 : 1) * (hour * 3600 + minute * 60)
        }
        guard let zone = TimeZone(secondsFromGMT: seconds) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        var components = DateComponents()
        components.year = Int(capture(1)); components.month = Int(capture(2)); components.day = Int(capture(3))
        components.hour = Int(capture(4)); components.minute = Int(capture(5)); components.second = Int(capture(6))
        guard let date = calendar.date(from: components),
              [Calendar.Component.year, .month, .day, .hour, .minute, .second].allSatisfy({
                  calendar.component($0, from: date) == components.value(for: $0)
              }) else { return nil }
        let fraction = Double("0" + capture(7)) ?? 0
        return ShotDate(date: date.addingTimeInterval(fraction), zone: zone, raw: raw, offsetRecorded: !zoneText.isEmpty)
    }

    static func shooting(_ input: RenameInput, settings: RenameSettings) -> ShotDate? {
        let priorities = settings.datePriority.split(separator: "\n").map(String.init)
        for name in priorities {
            if let raw = tag(name, input: input) {
                let created = name.hasSuffix(":CreateDate")
                let offset = tag(created ? "OffsetTimeDigitized" : "OffsetTimeOriginal", input: input)
                if var date = parseDate(raw, offset: offset) {
                    if !raw.contains("."), let subsec = tag(created ? "SubSecTimeDigitized" : "SubSecTimeOriginal", input: input),
                       let fraction = Double("0." + subsec), fraction < 1 {
                        date.date = date.date.addingTimeInterval(fraction)
                    }
                    return date
                }
            }
        }
        return nil
    }

    static func dateValue(_ input: RenameInput, rule: RenameRule, settings: RenameSettings) -> String? {
        let chosen: ShotDate?
        switch rule.dateSource {
        case .shooting: chosen = shooting(input, settings: settings)
        case .created: chosen = input.created.map { ShotDate(date: $0, zone: .current, raw: "") }
        case .modified: chosen = input.modified.map { ShotDate(date: $0, zone: .current, raw: "") }
        case .now: chosen = ShotDate(date: input.referenceDate, zone: .current, raw: "")
        }
        guard let chosen else { return nil }
        let zone = rule.timeZone == "source" || !chosen.offsetRecorded ? chosen.zone :
            rule.timeZone == "local" ? TimeZone.current : TimeZone(identifier: rule.timeZone)
        guard let zone else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        var date = chosen.date
        if rule.nightHour > 0, calendar.component(.hour, from: date) < rule.nightHour,
           let previous = calendar.date(byAdding: .day, value: -1, to: date) { date = previous }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = zone
        formatter.dateFormat = rule.dateFormat
        return formatter.string(from: date)
    }

    static func alphabet(_ number: Int) -> String? {
        guard number > 0, number <= 1_000_000_000 else { return nil }
        var n = number
        var result = ""
        while n > 0 {
            n -= 1
            result = String(UnicodeScalar(65 + n % 26)!) + result
            n /= 26
        }
        return result
    }

    static func roman(_ number: Int) -> String? {
        guard (1...3999).contains(number) else { return nil }
        var n = number
        var result = ""
        for (value, letters) in [(1000,"M"),(900,"CM"),(500,"D"),(400,"CD"),(100,"C"),(90,"XC"),
                                 (50,"L"),(40,"XL"),(10,"X"),(9,"IX"),(5,"V"),(4,"IV"),(1,"I")] {
            while n >= value { result += letters; n -= value }
        }
        return result
    }

    private static func selectedRanges(_ text: String, matching pattern: String, rule: RenameRule,
                                       regex: Bool = false) throws -> [Range<String.Index>] {
        guard !pattern.isEmpty else { return [] }
        let expression = try NSRegularExpression(pattern: regex ? pattern : NSRegularExpression.escapedPattern(for: pattern),
                                                  options: rule.caseSensitive ? [] : [.caseInsensitive])
        let ranges = expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text) }
        switch rule.occurrence {
        case .all: return ranges
        case .first: return Array(ranges.prefix(1))
        case .last: return Array(ranges.suffix(1))
        case .nth: return rule.matchNumber > 0 && rule.matchNumber <= ranges.count ? [ranges[rule.matchNumber - 1]] : []
        }
    }

    private static func replacing(_ input: String, rule: RenameRule, mode: Int) throws -> String {
        let pattern = NSRegularExpression.escapedPattern(for: rule.text)
        let query = mode == 0 ? "^" + pattern : mode == 1 ? pattern + "$" : pattern
        let ranges = try selectedRanges(input, matching: query, rule: rule, regex: true)
        var result = input
        for range in ranges.reversed() { result.replaceSubrange(range, with: rule.replacement) }
        return result
    }

    private static func insert(_ content: String, into name: String, mode: Int, rule: RenameRule) throws -> (String, RenameIssue?) {
        switch mode {
        case 0: return (content, nil)
        case 1: return (content + name, nil)
        case 2: return (name + content, nil)
        case 3, 4:
            let ranges = try selectedRanges(name, matching: rule.anchor, rule: rule)
            guard !ranges.isEmpty else { return (name, .missingAnchor) }
            var result = name
            for range in ranges.reversed() { result.insert(contentsOf: content, at: mode == 3 ? range.lowerBound : range.upperBound) }
            return (result, nil)
        default:
            let chars = Array(name)
            guard rule.position >= 0, rule.position <= chars.count else { throw RenameError.invalidRule(rule.action) }
            return (String(chars.prefix(rule.position)) + content + String(chars.dropFirst(rule.position)), nil)
        }
    }

    static func template(_ text: String, input: RenameInput, rule: RenameRule, settings: RenameSettings) throws -> String? {
        let regex = try NSRegularExpression(pattern: #"<([^<>]+)>"#)
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var result = text
        let components: [String: String] = ["Day":"d", "0Day":"dd", "Month":"M", "0Month":"MM", "2DigitYear":"yy",
            "4DigitYear":"yyyy", "Hour24":"H", "0Hour24":"HH", "Hour12":"h", "0Hour12":"hh", "Minute":"m",
            "0Minute":"mm", "Second":"s", "0Second":"ss", "am_pm":"a", "AM_PM":"a", "SubSecond":"SS", "0SubSecond":"SSS"]
        for match in matches.reversed() {
            guard let range = Range(match.range, in: text), let tokenRange = Range(match.range(at: 1), in: text) else { continue }
            let token = String(text[tokenRange])
            var value: String?
            for (prefix, source) in [("ShootingDate", RenameRule.DateSource.shooting), ("CreationDate", .created), ("ModificationDate", .modified), ("ModDate", .modified)] {
                if token.hasPrefix(prefix), let format = components[String(token.dropFirst(prefix.count))] {
                    var dateRule = rule; dateRule.dateSource = source; dateRule.dateFormat = format
                    value = dateValue(input, rule: dateRule, settings: settings)
                    if token.hasSuffix("am_pm") { value = value?.lowercased() }
                    if token.hasSuffix("AM_PM") { value = value?.uppercased() }
                }
            }
            if value == nil { value = tag(token, input: input) }
            if value == nil, token.hasPrefix("0"), let n = tag(String(token.dropFirst()), input: input).flatMap(Int.init) {
                value = String(format: "%02d", n)
            }
            guard let value else { return nil }
            result.replaceSubrange(range, with: value)
        }
        return result
    }

    static func transform(_ name: String, input: RenameInput, rule: RenameRule, index: Int,
                          settings: RenameSettings) throws -> (String, RenameIssue?) {
        guard (1...97).contains(rule.action), rule.position >= 0, rule.length >= 0,
              (0...32).contains(rule.padding), (0...23).contains(rule.nightHour) else { throw RenameError.invalidRule(rule.action) }
        let parts = split(name)
        let selected: String
        switch rule.part {
        case .stem: selected = parts.stem
        case .entire: selected = name
        case .dottedExtension: selected = parts.ext
        case .extensionOnly: selected = String(parts.ext.dropFirst())
        }
        let (value, issue) = try transformPart(selected, input: input, rule: rule, index: index, settings: settings)
        let output: String
        switch rule.part {
        case .stem: output = value + parts.ext
        case .entire: output = value
        case .dottedExtension: output = parts.stem + value
        case .extensionOnly: output = parts.stem + (value.isEmpty ? "" : "." + value)
        }
        return (output, issue)
    }

}

extension RenameEngine {
    // One dispatcher preserves the researched action IDs; family helpers share insertion and matching.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private static func transformPart(_ name: String, input: RenameInput, rule: RenameRule, index: Int,
                                      settings: RenameSettings) throws -> (String, RenameIssue?) {
        let action = rule.action
        if (1...5).contains(action) { return try insert(rule.text, into: name, mode: action, rule: rule) }
        if (6...11).contains(action) {
            var remove = rule
            if action <= 8 { remove.replacement = "" }
            return (try replacing(name, rule: remove, mode: (action - 6) % 3), nil)
        }
        if (12...16).contains(action) {
            let ranges = try selectedRanges(name, matching: rule.text, rule: rule)
            guard !ranges.isEmpty else { return (name, .missingAnchor) }
            let content = ranges.map { String(name[$0]) }.joined()
            var remaining = name
            for range in ranges.reversed() { remaining.removeSubrange(range) }
            let mode = [1,2,5,3,4][action - 12]
            return try insert(content, into: remaining, mode: mode, rule: rule)
        }
        if (17...19).contains(action) {
            let chars = Array(rule.text)
            let replacements = Array(rule.replacement)
            if action == 17, replacements.count != chars.count && replacements.count != 1 { throw RenameError.invalidRule(action) }
            var result = ""
            for character in name {
                let found = chars.firstIndex { rule.caseSensitive ? $0 == character : String($0).lowercased() == String(character).lowercased() }
                if action == 19 { if found != nil { result.append(character) } }
                else if let found {
                    if action == 17 { result.append(replacements[replacements.count == 1 ? 0 : found]) }
                } else { result.append(character) }
            }
            return (result, nil)
        }
        switch action {
        case 20: return (String(name.drop(while: { $0.isWhitespace })), nil)
        case 21: return (String(String(name.reversed()).drop(while: { $0.isWhitespace }).reversed()), nil)
        case 22: return (String(name.filter { !"aeiouAEIOU".contains($0) }), nil)
        case 23: return (String(name.filter { character in
            !character.unicodeScalars.contains { $0.properties.isEmojiPresentation || ($0.properties.isEmoji && $0.value > 127) || $0.value == 0xFE0F || $0.value == 0x20E3 }
        }), nil)
        case 24: return (String(name.dropFirst(rule.length)), nil)
        case 25: return (String(name.dropLast(rule.length)), nil)
        case 26, 27:
            var chars = Array(name)
            guard rule.position <= chars.count, rule.length <= chars.count - rule.position else { throw RenameError.invalidRule(action) }
            let content = String(chars[rule.position..<(rule.position + rule.length)])
            chars.removeSubrange(rule.position..<(rule.position + rule.length))
            if action == 26 { return (String(chars), nil) }
            guard rule.start >= 0, rule.start <= chars.count else { throw RenameError.invalidRule(action) }
            chars.insert(contentsOf: Array(content), at: rule.start)
            return (String(chars), nil)
        case 28: return (name.lowercased(), nil)
        case 29: return (name.prefix(1).uppercased() + name.dropFirst().lowercased(), nil)
        case 30: return (name.capitalized(with: Locale(identifier: "en_US_POSIX")), nil)
        case 31: return (name.uppercased(), nil)
        case 32: return (try lexicalCase(name, rule: rule), nil)
        case 33: return (name.removingPercentEncoding ?? name, nil)
        case 34:
            let regex = try NSRegularExpression(pattern: #"([a-z0-9])([A-Z])|([A-Z])([A-Z][a-z])"#)
            var result = name
            for match in regex.matches(in: name, range: NSRange(name.startIndex..., in: name)).reversed() {
                let left = match.range(at: 1).location != NSNotFound ? 1 : 3
                if let right = Range(match.range(at: left + 1), in: name) { result.insert(" ", at: right.lowerBound) }
            }
            return (result, nil)
        case 35: return (name.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX")), nil)
        case 36: return (String(name.replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: "/", with: "-").prefix(31)), nil)
        case 37:
            var result = String(name.unicodeScalars.map { scalar in
                scalar.value < 32 || "<>:\"/\\|?*".unicodeScalars.contains(scalar) ? "_" : String(scalar)
            }.joined().reversed().drop(while: { $0 == "." || $0 == " " }).reversed())
            let base = split(result).stem.uppercased()
            if ["CON","PRN","AUX","NUL"].contains(base) || (1...9).contains(where: { base == "COM\($0)" || base == "LPT\($0)" }) { result = "_" + result }
            return (result, nil)
        case 38: return (String(name.prefix(rule.length)), nil)
        case 39:
            let parts = split(name)
            func dos(_ text: String, count: Int) -> String {
                String(text.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber || "_$~!#%&-{}()@'`".contains($0)) }.prefix(count))
            }
            let ext = dos(String(parts.ext.dropFirst()), count: 3)
            return (dos(parts.stem, count: 8) + (ext.isEmpty ? "" : "." + ext), nil)
        case 52, 53:
            let expression = try NSRegularExpression(pattern: #"\d+"#)
            let matches = expression.matches(in: name, range: NSRange(name.startIndex..., in: name))
            let chosen: [NSTextCheckingResult]
            switch rule.occurrence {
            case .all: chosen = matches
            case .first: chosen = Array(matches.prefix(1))
            case .last: chosen = Array(matches.suffix(1))
            case .nth: chosen = rule.matchNumber > 0 && rule.matchNumber <= matches.count ? [matches[rule.matchNumber - 1]] : []
            }
            var result = name
            for match in chosen.reversed() {
                guard let range = Range(match.range, in: name) else { continue }
                var replacement = ""
                if action == 52 {
                    guard let n = Int(name[range]) else { throw RenameError.invalidRule(action) }
                    let operation: (partialValue: Int, overflow: Bool)
                    switch rule.numberOperation {
                    case .add: operation = n.addingReportingOverflow(rule.numberValue)
                    case .subtract: operation = n.subtractingReportingOverflow(rule.numberValue)
                    case .multiply: operation = n.multipliedReportingOverflow(by: rule.numberValue)
                    case .divide:
                        guard rule.numberValue != 0 else { throw RenameError.invalidRule(action) }
                        operation = n.dividedReportingOverflow(by: rule.numberValue)
                    case .set: operation = (rule.numberValue, false)
                    }
                    guard !operation.overflow else { throw RenameError.invalidRule(action) }
                    replacement = padded(operation.partialValue, width: max(rule.padding, String(name[range]).count))
                }
                result.replaceSubrange(range, with: replacement)
            }
            return (result, nil)
        case 94:
            let lines = rule.text.components(separatedBy: .newlines).filter { !$0.isEmpty }
            if lines.contains(where: { $0.contains("\t") }) {
                guard lines.allSatisfy({ $0.components(separatedBy: "\t").count == 2 }) else { throw RenameError.invalidRule(action) }
                let rows = lines.map { $0.components(separatedBy: "\t") }
                let pathMode = rows[0][0].hasPrefix("/")
                guard rows.allSatisfy({ $0[0].hasPrefix("/") == pathMode }) else { throw RenameError.invalidRule(action) }
                let current = pathMode ? input.url.path : input.name
                let matched = rows.filter { rule.caseSensitive ? $0[0] == current : key($0[0]) == key(current) }
                guard matched.count <= 1 else { throw RenameError.invalidRule(action) }
                return matched.first.map { ($0[1], nil) } ?? (name, .listMismatch)
            }
            return index < lines.count ? (lines[index], nil) : (name, .listMismatch)
        case 95, 96:
            let expression = try NSRegularExpression(pattern: rule.text, options: rule.caseSensitive ? [] : [.caseInsensitive])
            let range = NSRange(name.startIndex..., in: name)
            if action == 95 {
                var result = name
                for match in expression.matches(in: name, range: range).reversed() {
                    if let matched = Range(match.range, in: name) {
                        let replacement = try regexReplacement(rule.replacement, match: match, name: name, expression: expression)
                        result.replaceSubrange(matched, with: replacement)
                    }
                }
                return (result, nil)
            }
            guard let match = expression.firstMatch(in: name, range: range), !rule.fullMatch || match.range == range else { return (name, .excluded) }
            return (try regexReplacement(rule.replacement, match: match, name: name, expression: expression), nil)
        case 97: return (rule.text, nil)
        default: break
        }
        var content: String
        var mode: Int
        if (40...45).contains(action) {
            guard let value = dateValue(input, rule: rule, settings: settings) else { return (name, .missingDate) }
            content = value; mode = action - 40
        } else if (46...51).contains(action) || (54...65).contains(action) {
            let multiplied = rule.step.multipliedReportingOverflow(by: index)
            let initial = action >= 60 ? try alphabetIndex(rule.alphabetStart) : rule.start
            let added = initial.addingReportingOverflow(multiplied.partialValue)
            guard !multiplied.overflow, !added.overflow else { throw RenameError.invalidRule(action) }
            let n = added.partialValue
            if action >= 60 {
                guard let value = alphabet(n) else { throw RenameError.invalidRule(action) }
                guard (1...32).contains(rule.alphabetWidth) else { throw RenameError.invalidRule(action) }
                content = String(repeating: "A", count: max(0, rule.alphabetWidth - value.count)) + value
                if rule.alphabetStart == rule.alphabetStart.lowercased() { content = content.lowercased() }
                mode = action - 60
            } else if action >= 54 {
                guard let value = roman(n) else { throw RenameError.invalidRule(action) }
                content = rule.caseSensitive ? value : value.lowercased(); mode = action - 54
            } else { content = padded(n, width: rule.padding); mode = action - 46 }
            content = rule.prefix + content + rule.suffix
        } else if (66...77).contains(action) {
            guard let value = try template(rule.text, input: input, rule: rule, settings: settings) else { return (name, .missingTag) }
            content = value
            mode = action <= 71 ? [0,1,2,5,3,4][action - 66] : [0,2,1,3,4,5][action - 72]
        } else if (78...83).contains(action) {
            guard let width = tag("ImageWidth", input: input), let height = tag("ImageHeight", input: input) else { return (name, .missingTag) }
            content = rule.prefix + width + (rule.text.isEmpty ? "x" : rule.text) + height + rule.suffix
            mode = [2,1,0,3,4,5][action - 78]
        } else if (84...93).contains(action) {
            if action <= 88 { content = input.directory.lastPathComponent; mode = action - 83 }
            else {
                let components = Array(input.directory.pathComponents.dropFirst().reversed())
                guard rule.position < components.count, rule.length > 0 else { return (name, .missingTag) }
                let chosen = components.dropFirst(rule.position).prefix(rule.length)
                if rule.skipMissing && chosen.count < rule.length { return (name, .missingTag) }
                content = chosen.reversed().joined(separator: rule.text.isEmpty ? "_" : rule.text)
                mode = action - 88
            }
            content = rule.prefix + content + rule.suffix
        } else { throw RenameError.invalidRule(action) }
        return try insert(content, into: name, mode: mode, rule: rule)
    }

}

extension RenameEngine {
    static func padded(_ n: Int, width: Int) -> String {
        let digits = String(n).drop(while: { $0 == "-" })
        return (n < 0 ? "-" : "") + String(repeating: "0", count: max(0, width - digits.count)) + digits
    }

    static func matches(_ input: RenameInput, rule: RenameRule, settings: RenameSettings) -> Bool {
        let conditions = rule.filters.map { condition in
            let value: String?
            switch condition.field {
            case .name: value = input.name
            case .fileExtension: value = String(split(input.name).ext.dropFirst())
            case .comment: value = tag("ImageUserComment", input: input)
            case .shootingDate:
                var dateRule = rule; dateRule.dateSource = .shooting; dateRule.dateFormat = "yyyy-MM-dd HH:mm:ss"
                value = dateValue(input, rule: dateRule, settings: settings)
            }
            if condition.comparison == .exists { return value?.isEmpty == false }
            if condition.comparison == .missing { return value?.isEmpty != false }
            guard let value else { return false }
            let actual = rule.caseSensitive ? value : key(value)
            let expected = rule.caseSensitive ? condition.value : key(condition.value)
            switch condition.comparison {
            case .contains: return actual.contains(expected)
            case .notContains: return !actual.contains(expected)
            case .equals: return actual == expected
            case .notEquals: return actual != expected
            case .starts: return actual.hasPrefix(expected)
            case .ends: return actual.hasSuffix(expected)
            case .before: return actual < expected
            case .after: return actual > expected
            case .exists, .missing: return false
            }
        }
        return rule.filterAny ? conditions.contains(true) : conditions.allSatisfy { $0 }
    }

    static func ordered(_ inputs: [RenameInput], settings: RenameSettings) -> [RenameInput] {
        guard settings.sort != .input else { return settings.descending ? inputs.reversed() : inputs }
        return inputs.enumerated().sorted { left, right in
            let comparison: ComparisonResult
            switch settings.sort {
            case .name: comparison = left.element.name.compare(right.element.name)
            case .natural: comparison = left.element.name.localizedStandardCompare(right.element.name)
            case .created, .modified, .shooting:
                func date(_ item: RenameInput) -> Date? {
                    switch settings.sort {
                    case .created: item.created
                    case .modified: item.modified
                    default: shooting(item, settings: settings)?.date
                    }
                }
                let lhs = date(left.element) ?? .distantFuture, rhs = date(right.element) ?? .distantFuture
                comparison = lhs == rhs ? .orderedSame : lhs < rhs ? .orderedAscending : .orderedDescending
            case .input: comparison = .orderedSame
            }
            if comparison == .orderedSame { return left.offset < right.offset }
            return settings.descending ? comparison == .orderedDescending : comparison == .orderedAscending
        }.map(\.element)
    }

    // Final allocation keeps all members of a photo group on the same stem.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func preview(inputs: [RenameInput], rules: [RenameRule], settings: RenameSettings,
                        occupied: [String: Set<String>]) throws -> [RenamePreview] {
        let inputs = ordered(inputs, settings: settings)
        let sourceOrder = settings.sourceExtensions.split(separator: ",").map { key($0.trimmingCharacters(in: .whitespaces)) }
        let targets = Set(settings.targetExtensions.split(separator: ",").map { key($0.trimmingCharacters(in: .whitespaces)) })
        func group(_ input: RenameInput) -> String {
            let ext = key(String(split(input.name).ext.dropFirst()))
            return settings.pair && (sourceOrder.contains(ext) || targets.contains(ext)) ?
                input.directory.path + "/" + key(split(input.name).stem) : input.url.path
        }
        let grouped = Dictionary(grouping: inputs, by: group)
        let leaders: [String: RenameInput] = grouped.mapValues { values in
            values.min { left, right in
                let lhs = sourceOrder.firstIndex(of: key(String(split(left.name).ext.dropFirst()))) ?? Int.max
                let rhs = sourceOrder.firstIndex(of: key(String(split(right.name).ext.dropFirst()))) ?? Int.max
                return lhs < rhs
            }!
        }
        var counts: [UUID: [String: Int]] = [:]
        var computed: [String: RenamePreview] = [:]
        for input in inputs where computed[group(input)] == nil {
            let groupID = group(input)
            let leader = leaders[groupID]!
            var name = leader.name
            var steps: [RenameStep] = []
            var issues: [RenameIssue] = []
            var included = true
            var skip = false
            for rule in rules where rule.enabled {
                if rule.action == 99 { continue }
                if rule.action == 98 {
                    included = matches(leader, rule: rule, settings: settings)
                    steps.append(RenameStep(id: rule.id, name: name, issue: included ? nil : .excluded))
                    continue
                }
                guard included, !skip else { steps.append(RenameStep(id: rule.id, name: name, issue: .excluded)); continue }
                let domain = rule.perDirectory ? leader.directory.path : ""
                let ordinal = counts[rule.id, default: [:]][domain, default: 0]
                counts[rule.id, default: [:]][domain] = ordinal + 1
                let (next, issue) = try transform(name, input: leader, rule: rule, index: ordinal, settings: settings)
                name = next
                if let issue { issues.append(issue) }
                if rule.skipMissing, issue == .missingDate || issue == .missingTag || issue == .listMismatch {
                    skip = true; name = leader.name
                }
                steps.append(RenameStep(id: rule.id, name: name, issue: issue, ordinal: ordinal))
            }
            if !included && name == leader.name { issues.append(.excluded) }
            computed[groupID] = RenamePreview(source: leader.url, target: leader.directory.appendingPathComponent(name),
                                              steps: steps, issues: issues, group: groupID)
        }
        var result = inputs.map { input -> RenamePreview in
            var row = computed[group(input)]!
            let final: String
            if row.source != input.url {
                final = split(row.target.lastPathComponent).stem + split(input.name).ext
            } else { final = row.target.lastPathComponent }
            row = RenamePreview(source: input.url, target: input.directory.appendingPathComponent(final),
                                steps: row.steps.map { step in
                                    RenameStep(id: step.id, name: row.source == input.url ? step.name : split(step.name).stem + split(input.name).ext,
                                               issue: step.issue, ordinal: step.ordinal)
                                }, issues: row.issues, group: row.group)
            if !validName(final) { row.issues.append(.invalidName) }
            if input.metadataFailure { row.issues.append(.metadataFailure) }
            return row
        }
        // Reserve external and unchanged files. All changing sources are staged before any target is committed.
        var reserved = occupied
        for row in result where row.changes {
            reserved[row.source.deletingLastPathComponent().path, default: []].remove(key(row.source.lastPathComponent))
        }
        var processed = Set<String>()
        let groupIndices = Dictionary(grouping: result.indices, by: { result[$0].group })
        for index in result.indices {
            let groupID = result[index].group
            guard processed.insert(groupID).inserted else { continue }
            let indices = groupIndices[groupID]!
            guard indices.contains(where: { result[$0].changes }) else { continue }
            let originalTargets = indices.map { result[$0].target }
            var suffix = settings.keepFirst ? 0 : 1
            while true {
                let digits = settings.conflictDigits ?? 3
                guard (2...5).contains(digits) else { throw RenameError.invalidPreset }
                let value = settings.conflict == .letters ? alphabet(suffix) ?? String(suffix) : padded(suffix, width: digits)
                let format = settings.conflict == .letters ? settings.letterSuffixFormat ?? .plain : settings.numberSuffixFormat ?? .underscore
                let tail = suffix == 0 ? "" : format.format(value)
                let proposed = originalTargets.map { url -> URL in
                    let parts = split(url.lastPathComponent)
                    return url.deletingLastPathComponent().appendingPathComponent(parts.stem + tail + parts.ext)
                }
                let unique = Set(proposed.map { $0.deletingLastPathComponent().path + "/" + key($0.lastPathComponent) }).count == proposed.count
                let available = proposed.allSatisfy { validName($0.lastPathComponent) && !reserved[$0.deletingLastPathComponent().path, default: []].contains(key($0.lastPathComponent)) }
                if unique && available {
                    for (index, url) in zip(indices, proposed) {
                        result[index].target = url
                        reserved[url.deletingLastPathComponent().path, default: []].insert(key(url.lastPathComponent))
                    }
                    break
                }
                if settings.conflict == .stop || !unique || suffix >= 100_000 || proposed.contains(where: { !validName($0.lastPathComponent) }) {
                    for index in indices { result[index].issues.append(.conflict) }
                    break
                }
                suffix += 1
            }
        }
        for index in result.indices where result[index].source.path == result[index].target.path && result[index].issues.isEmpty {
            result[index].issues.append(.unchanged)
        }
        return result
    }
}

extension RenameEngine {
    static func nextCounter(_ rule: RenameRule, rows: [RenamePreview]) throws -> Int {
        // A later missing-tag rule can skip an ordinal; do not reuse an already assigned later number.
        let last = rows.flatMap(\.steps).filter { $0.id == rule.id && $0.issue == nil }.compactMap(\.ordinal).max()
        let consumed = last.map { $0 + 1 } ?? 0
        let delta = rule.step.multipliedReportingOverflow(by: consumed)
        let next = rule.start.addingReportingOverflow(delta.partialValue)
        guard !delta.overflow, !next.overflow else { throw RenameError.invalidRule(rule.action) }
        return next.partialValue
    }

    static func regexReplacement(_ template: String, match: NSTextCheckingResult, name: String,
                                 expression: NSRegularExpression) throws -> String {
        let controls = try NSRegularExpression(pattern: #"(?<!\\)\\[ULulE]"#)
        let found = controls.matches(in: template, range: NSRange(template.startIndex..., in: template))
        var start = template.startIndex
        var run: Character?
        var next: Character?
        var result = ""
        func append(_ segment: Substring) {
            var value = expression.replacementString(for: match, in: name, offset: 0, template: String(segment))
            if run == "U" { value = value.uppercased() }
            if run == "L" { value = value.lowercased() }
            if !value.isEmpty, let change = next {
                value = (change == "u" ? value.prefix(1).uppercased() : value.prefix(1).lowercased()) + value.dropFirst()
                next = nil
            }
            result += value
        }
        for control in found {
            guard let range = Range(control.range, in: template) else { continue }
            append(template[start..<range.lowerBound])
            let command = template[range].last!
            if command == "E" { run = nil; next = nil }
            else if command == "U" || command == "L" { run = command }
            else { next = command }
            start = range.upperBound
        }
        append(template[start...])
        return result
    }
}

extension RenameEngine {
    static func alphabetIndex(_ letters: String) throws -> Int {
        let upper = letters.uppercased()
        guard !upper.isEmpty, upper.count <= 7 else { throw RenameError.invalidRule(60) }
        var result = 0
        for scalar in upper.unicodeScalars {
            guard (65...90).contains(scalar.value) else { throw RenameError.invalidRule(60) }
            result = result * 26 + Int(scalar.value) - 64
        }
        guard result <= 1_000_000_000 else { throw RenameError.invalidRule(60) }
        return result
    }

    static func lexicalCase(_ name: String, rule: RenameRule) throws -> String {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = name
        var changes: [(Range<String.Index>, String)] = []
        tagger.enumerateTags(in: name.startIndex..<name.endIndex, unit: .word, scheme: .lexicalClass,
                            options: [.omitWhitespace, .omitPunctuation]) { tag, range in
            let word = String(name[range])
            let changed: String
            switch tag.flatMap({ rule.lexicalCases[$0.rawValue] }) ?? .keep {
            case .keep: changed = word
            case .lower: changed = word.lowercased()
            case .upper: changed = word.uppercased()
            case .title: changed = word.capitalized
            }
            changes.append((range, changed))
            return true
        }
        var result = name
        for (range, value) in changes.reversed() { result.replaceSubrange(range, with: value) }
        for word in rule.text.split(whereSeparator: \.isWhitespace) {
            let expression = try NSRegularExpression(pattern: "(?i)\\b" + NSRegularExpression.escapedPattern(for: String(word)) + "\\b")
            result = expression.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result),
                                                         withTemplate: NSRegularExpression.escapedTemplate(for: String(word)))
        }
        return result
    }
}
