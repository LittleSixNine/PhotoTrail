import Foundation
import ImageData

enum MetadataFilenameDateFormat: String, CaseIterable {
    case compactDateTime = "YYYYMMDD_HHmmss"
    case dottedDate = "YYYY.MMDD"
    case fullDottedDate = "YYYY.MM.DD"
    case dashedDate = "YYYY-MM-DD"
    case compactDate = "YYYYMMDD"
    case dashedDateTime = "YYYY-MM-DD_HH-mm-ss"

    var includesTime: Bool { rawValue.contains("HH") }

    var example: String { Self.example(for: rawValue) + ".jpg" }

    static func example(for format: String) -> String {
        [("YYYY", "2026"), ("MM", "11"), ("DD", "02"),
         ("HH", "14"), ("mm", "30"), ("ss", "25")].reduce(format) {
            $0.replacingOccurrences(of: $1.0, with: $1.1)
        }
    }

    var action: MetadataFieldEditAction {
        // The enum cases are fixed, valid formats; user input goes through customAction.
        do {
            return try Self.compile(rawValue)
        } catch {
            preconditionFailure("Invalid built-in filename format: \(rawValue)")
        }
    }

    static func customAction(_ format: String) throws -> MetadataFieldEditAction {
        guard case .filenameDate(let pattern, let template) = try compile(format) else {
            throw MetadataFieldEditError.invalidValue
        }
        // Keep the typed format in an inert regex comment so v1 presets can reopen it.
        let encoded = Data(format.utf8).base64EncodedString()
        return .filenameDate(pattern: customPrefix + encoded + ")" + pattern, template: template)
    }

    static func customFormat(in action: MetadataFieldEditAction) -> String? {
        guard case .filenameDate(let pattern, _) = action, pattern.hasPrefix(customPrefix),
              let end = pattern.firstIndex(of: ")"),
              let data = Data(base64Encoded: String(pattern[pattern.index(pattern.startIndex,
                  offsetBy: customPrefix.count)..<end])),
              let format = String(data: data, encoding: .utf8),
              let rebuilt = try? customAction(format), rebuilt == action else { return nil }
        return format
    }

    private static let customPrefix = "(?#PhotoTrailFilenameFormat:"

    private static func compile(_ format: String) throws -> MetadataFieldEditAction {
        guard !format.isEmpty, format.count <= 256,
              !format.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw MetadataFieldEditError.invalidValue
        }
        let tokens = ["YYYY", "MM", "DD", "HH", "mm", "ss"]
        var remaining = format[...], pattern = #"(?<![0-9])"#
        var groups: [String: String] = [:]
        while !remaining.isEmpty {
            if let token = tokens.first(where: { remaining.hasPrefix($0) }) {
                guard groups[token] == nil else { throw MetadataFieldEditError.invalidValue }
                groups[token] = "$\(groups.count + 1)"
                pattern += token == "YYYY" ? #"([0-9]{4})"# : #"([0-9]{2})"#
                remaining = remaining.dropFirst(token.count)
            } else {
                pattern += NSRegularExpression.escapedPattern(for: String(remaining.removeFirst()))
            }
        }
        guard ["YYYY", "MM", "DD"].allSatisfy({ groups[$0] != nil }),
              groups["mm"] == nil || groups["HH"] != nil,
              groups["ss"] == nil || groups["mm"] != nil else { throw MetadataFieldEditError.invalidValue }
        pattern += #"(?![0-9])"#
        let values = tokens.map { groups[$0] ?? "00" }
        let date = values[0...2].joined(separator: ":"), time = values[3...5].joined(separator: ":")
        return .filenameDate(pattern: pattern,
                             template: date + " " + time)
    }

    static func matching(_ action: MetadataFieldEditAction) -> Self? {
        if action == legacyDefaultAction { return .compactDateTime }
        return allCases.first { $0.action == action }
    }

    static let legacyDefaultAction = MetadataFieldEditAction.filenameDate(
        pattern: #"^(?:IMG_)?(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})(?:\.[^.]+)$"#,
        template: "$1:$2:$3 $4:$5:$6")
}
