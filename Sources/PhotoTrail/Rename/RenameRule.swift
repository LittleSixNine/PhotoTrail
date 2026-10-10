import Foundation

struct RenameAction: Codable, Identifiable, Sendable {
    let number: Int
    let category: String
    let categoryChinese: String
    let title: String
    let titleChinese: String
    var id: Int { number }

    static let all: [Self] = {
        guard let url = Bundle.main.url(forResource: "RenameActions", withExtension: "json"),
              let data = try? Data(contentsOf: url), let actions = try? JSONDecoder().decode([Self].self, from: data)
        else { return [] }
        return actions
    }()
}

struct RenameRule: Codable, Equatable, Identifiable, Sendable {
    enum Part: String, Codable, CaseIterable { case stem, entire, dottedExtension, extensionOnly }
    enum Occurrence: String, Codable, CaseIterable { case all, first, last, nth }
    enum DateSource: String, Codable, CaseIterable { case shooting, created, modified, now }
    enum CaseStyle: String, Codable, CaseIterable { case keep, lower, upper, title }
    enum NumberOperation: String, Codable, CaseIterable { case add, subtract, multiply, divide, set }
    var id = UUID()
    var action = 40
    var enabled = true
    var part = Part.stem
    var metadataField: String? = nil
    var text = ""
    var replacement = ""
    var anchor = ""
    // All character positions are zero-based extended grapheme clusters, never UTF-16 offsets.
    var position = 0
    var length = 1
    var occurrence = Occurrence.all
    var matchNumber = 1
    var caseSensitive = true
    var start = 1
    var counter = 0
    var step = 1
    var padding = 3
    var alphabetStart = "A"
    var alphabetWidth = 1
    var lexicalCases: [String: CaseStyle] = [
        "Noun": .title, "Verb": .title, "Adjective": .title, "Adverb": .title, "Pronoun": .lower,
        "Determiner": .lower, "Preposition": .lower, "Conjunction": .lower, "Particle": .lower,
        "Interjection": .title, "Number": .keep, "Classifier": .keep, "Idiom": .keep, "OtherWord": .keep
    ]
    var prefix = ""
    var suffix = ""
    var numberOperation = NumberOperation.add
    var numberValue = 1
    var dateSource = DateSource.shooting
    var dateFormat = "yyyyMMdd_HHmmss"
    var timeZone = "source"
    var nightHour = 0
    var skipMissing = true
    var fullMatch = false
    var perDirectory = false
    var filterAny = false
    var filters = [RenameFilterCondition()]
}

struct RenameFilterCondition: Codable, Equatable, Identifiable, Sendable {
    enum Field: String, Codable, CaseIterable { case name, fileExtension, shootingDate, comment }
    enum Comparison: String, Codable, CaseIterable { case contains, notContains, equals, notEquals, starts, ends, before, after, exists, missing }
    var id = UUID()
    var field = Field.name
    var comparison = Comparison.contains
    var value = ""
}

struct RenameSettings: Codable, Equatable, Sendable {
    enum Conflict: String, Codable, CaseIterable { case stop, numbers, letters }
    enum Sort: String, Codable, CaseIterable { case input, name, natural, shooting, created, modified, fileExtension, folder, size, make, model, city, rating, metadata, manual }
    enum SuffixFormat: String, Codable, CaseIterable {
        case plain, underscore, dash, parentheses
        func format(_ value: String) -> String {
            switch self {
            case .plain: value
            case .underscore: "_" + value
            case .dash: "-" + value
            case .parentheses: "(" + value + ")"
            }
        }
    }
    var metadataSortTag: String? = nil
    var numberSuffixFormat: SuffixFormat?
    var letterSuffixFormat: SuffixFormat?
    var conflictDigits: Int?
    var conflict = Conflict.numbers
    var sort = Sort.input
    var descending = false
    var keepFirst = true
    var pair = true
    var sourceExtensions = "jpg,jpeg,heic,cr3,cr2,nef,arw,dng,raf"
    var targetExtensions = "xmp,aae,thm"
    var datePriority = [
        "Composite:SubSecDateTimeOriginal", "Composite:DateTimeOriginal", "ExifIFD:DateTimeOriginal",
        "XMP-exif:DateTimeOriginal", "ExifIFD:CreateDate", "QuickTime:CreationDate", "QuickTime:DateTimeOriginal",
        "QuickTime:ContentCreateDate", "QuickTime:CreateDate", "QuickTime:MediaCreateDate", "ID3:Date", "XMP-xmp:CreateDate"
    ].joined(separator: "\n")
}

struct RenamePreset: Codable, Identifiable, Sendable {
    var id = UUID()
    var version = 1
    var name: String
    var rules: [RenameRule]
    var settings: RenameSettings
    var example: String? = nil
}

struct RenameInput: Sendable, Equatable {
    var url: URL
    var tags: [String: String] = [:]
    var created: Date?
    var modified: Date?
    var metadataFailure = false
    var tagsRead = false
    var referenceDate = Date()
    var name: String { url.lastPathComponent }
    var directory: URL { url.deletingLastPathComponent() }
}

enum RenameIssue: String, Codable, Sendable {
    case missingDate, missingTag, missingAnchor, listMismatch, excluded, unchanged, invalidName, conflict, metadataFailure
}

struct RenameStep: Identifiable, Sendable {
    let id: UUID
    let name: String
    let issue: RenameIssue?
    var ordinal: Int? = nil
}

struct RenamePreview: Identifiable, Sendable {
    let source: URL
    var target: URL
    var steps: [RenameStep]
    var issues: [RenameIssue]
    var group: String
    var id: URL { source }
    var changes: Bool { source.path != target.path && !issues.contains(.invalidName) && !issues.contains(.conflict) }
}

enum RenameError: Error { case invalidRule(Int), invalidPreset, stalePlan, occupied, invalidSource, recoveryRequired }
