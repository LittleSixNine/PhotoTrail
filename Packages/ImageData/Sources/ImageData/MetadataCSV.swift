import CryptoKit
import Exiftool
import Foundation

public enum MetadataCSVError: Error { case invalidCSV, unsupportedFormat, invalidIdentity }

public struct MetadataCSVRecord: Sendable {
    public let id: String
    public let relativePath: String
    public let values: [MetadataTag: MetadataTagValue]
    public init(url: URL, relativePath: String, values: [MetadataTag: MetadataTagValue]) throws {
        guard Self.safePath(relativePath) else { throw MetadataCSVError.invalidIdentity }
        id = SHA256.hash(data: Data(url.standardizedFileURL.path.utf8)).map { String(format: "%02x", $0) }.joined()
        self.relativePath = relativePath; self.values = values
    }
    static func safePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\")
            && !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == ".." || $0 == "." || $0.isEmpty })
            && !path.contains(where: { "*?[]".contains($0) })
    }
}

public struct MetadataCSVImport: Sendable {
    public let operations: [String: [MetadataOperation]]
    public let warnings: [String]
}

public enum MetadataCSV {
    public static func export(_ records: [MetadataCSVRecord], tags: [MetadataTag], displayOnly: Bool = false) throws -> String {
        var rows = [[displayOnly ? "PhotoTrail display CSV 1" : "PhotoTrail CSV 1", "RelativePath"] + tags.map(\.rawValue)]
        let encoder = JSONEncoder()
        for record in records {
            var row = [record.id, record.relativePath]
            for tag in tags {
                guard let value = record.values[tag] else { row.append(""); continue }
                if displayOnly {
                    let text: String = switch value { case .text(let text): text; case .list(let words): words.joined(separator: " / ") }
                    row.append(text.first.map { "=+-@\t\r".contains($0) } == true ? "'" + text : text)
                } else {
                    let data: Data = switch value {
                    case .text(let text): try encoder.encode(text)
                    case .list(let words): try encoder.encode(words)
                    }
                    row.append(String(decoding: data, as: UTF8.self))
                }
            }
            rows.append(row)
        }
        return rows.map { $0.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    public static func parse(_ text: String) throws -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = ""
        var quoted = false, closed = false, start = true
        let chars = Array(text.hasPrefix("\u{feff}") ? String(text.dropFirst()) : text)
        var index = 0
        func finishField() { row.append(field); field = ""; closed = false; start = true }
        while index < chars.count {
            let char = chars[index]
            if quoted {
                if char == "\"" {
                    if index + 1 < chars.count, chars[index + 1] == "\"" { field.append("\""); index += 1 }
                    else { quoted = false; closed = true }
                } else { field.append(char) }
            } else if char == "\"" {
                guard start, !closed else { throw MetadataCSVError.invalidCSV }
                quoted = true; start = false
            } else if char == "," { finishField() }
            else if char == "\n" || char == "\r" || char == "\r\n" {
                finishField(); rows.append(row); row = []
                if char == "\r", index + 1 < chars.count, chars[index + 1] == "\n" { index += 1 }
            } else {
                guard !closed else { throw MetadataCSVError.invalidCSV }
                field.append(char); start = false
            }
            index += 1
        }
        guard !quoted else { throw MetadataCSVError.invalidCSV }
        if !field.isEmpty || !row.isEmpty || closed { finishField(); rows.append(row) }
        return rows
    }

    public static func load(_ text: String, authorized: [MetadataCSVRecord]) throws -> MetadataCSVImport {
        let rows = try parse(text)
        guard let header = rows.first, header.count >= 2, header[0] == "PhotoTrail CSV 1", header[1] == "RelativePath" else {
            throw MetadataCSVError.unsupportedFormat
        }
        guard Set(header).count == header.count, Set(authorized.map(\.id)).count == authorized.count else {
            throw MetadataCSVError.invalidIdentity
        }
        let allowed = Dictionary(uniqueKeysWithValues: authorized.map { ($0.id, $0.relativePath) })
        let tags = header.dropFirst(2).map { MetadataTag(rawValue: $0) }
        var warnings = header.dropFirst(2).filter { MetadataTag(rawValue: $0) == nil }.map { "Unknown column: \($0)" }
        var seen = Set<String>(), paths = Set<String>()
        var operations: [String: [MetadataOperation]] = [:]
        // Duplicate identities invalidate the entire input, rather than silently applying the first row.
        for row in rows.dropFirst() {
            guard row.count == header.count else { throw MetadataCSVError.invalidCSV }
            guard seen.insert(row[0]).inserted, paths.insert(row[1]).inserted else { throw MetadataCSVError.invalidIdentity }
        }
        let decoder = JSONDecoder()
        for (number, row) in rows.dropFirst().enumerated() {
            guard MetadataCSVRecord.safePath(row[1]), allowed[row[0]] == row[1] else {
                warnings.append("Row \(number + 2): unauthorized identity or path"); continue
            }
            var actions: [MetadataOperation] = []
            do {
                for (index, tag) in tags.enumerated() {
                    guard let tag, !row[index + 2].isEmpty else { continue }
                    let cell = row[index + 2]
                    let action: MetadataFieldEditAction
                    if cell == "@clear" { action = .remove }
                    else if tag.isList {
                        let words = try decoder.decode([String].self, from: Data(cell.utf8))
                        action = tag == .creator ? .replaceAuthors(words) : .replaceKeywords(words)
                    } else {
                        let text = try decoder.decode(String.self, from: Data(cell.utf8))
                        action = .setText(text)
                    }
                    _ = try action.change(for: tag, from: nil)
                    actions.append(MetadataOperation(tag: tag, action: action))
                }
                operations[row[0]] = actions
            } catch { warnings.append("Row \(number + 2): invalid field value") }
        }
        return MetadataCSVImport(operations: operations, warnings: warnings)
    }
}
