import Exiftool
import Foundation
import ImageData
import Testing
@testable import PhotoTrail

struct MetadataWorkflowCardTests {
    @Test @MainActor func customFilenameFormatsParseAndSurvivePresetRoundTrip() throws {
        let (folder, inputs) = try MetadataBatchEditingTests().input([[:]])
        defer { try? FileManager.default.removeItem(at: folder) }
        let cases = [("YYYY.MM.DD_HHmmss", "2026.11.02_143025", "14:30:25"),
                     ("YYYY.MMDD", "2026.1102", "00:00:00"),
                     ("IMG_YYYYMMDD_HHmmss", "IMG_20261102_143025", "14:30:25"),
                     ("旅行_DD.MM.YYYY_HHmm", "旅行_02.11.2026_1430", "14:30:00"),
                     ("YYYY年MM月DD日_HH", "2026年11月02日_14", "14:00:00"),
                     ("[YYYY-MM-DD](HH.mm.ss)+", "[2026-11-02](14.30.25)+", "14:30:25")]
        for (format, name, time) in cases {
            let action = try MetadataFilenameDateFormat.customAction(format)
            let preset = try MetadataPreset(name: "custom", operations: [MetadataOperation(tag: .captureDate, action: action)])
            let restored = try MetadataPreset.decode(preset.encode())
            #expect(MetadataFilenameDateFormat.customFormat(in: restored.operations[0].action) == format)
            #expect(MetadataFilenameDateFormat.example(for: format) == name)
            let reading = (image: ImageData(metadata: inputs[0].image.metadata, name: "prefix_" + name + "_suffix.jpg"),
                           snapshot: inputs[0].snapshot)
            let result = try MetadataWorkflowPreview.prepare([reading], operations: restored.operations)
            #expect(result.items.first?.changes[.captureDate] == .set(.text("2026:11:02 " + time)))
        }
    }

    @Test func invalidCustomFilenameFormatsAndModifiedPatternsAreRejected() throws {
        for format in ["", "YYYY", "YYYY-MM", "MM-DD", "YYYY-MM-DD-YYYY", "YYYY-MM-MM-DD", "yyyy-MM-dd",
                       "YYYY-MM-DD_mm", "YYYY-MM-DD_HHss", "YYYY-MM-DD_HHmmss_ss",
                       "YYYY\nMMDD", String(repeating: "x", count: 257) + "YYYYMMDD"] {
            #expect(throws: (any Error).self) { try MetadataFilenameDateFormat.customAction(format) }
        }
        let action = try MetadataFilenameDateFormat.customAction("YYYY.MMDD")
        guard case .filenameDate(let pattern, let template) = action else { Issue.record("Missing filename action"); return }
        #expect(MetadataFilenameDateFormat.customFormat(in: .filenameDate(pattern: pattern + "x", template: template)) == nil)
        #expect(MetadataFilenameDateFormat.customFormat(in: .filenameDate(pattern: pattern, template: "bad")) == nil)
        #expect(MetadataFilenameDateFormat.customFormat(in: .filenameDate(
            pattern: "(?#PhotoTrailFilenameFormat:invalid)", template: template)) == nil)
    }

    @Test @MainActor func simpleFilenameFormatsParseExamplesAndKeepVersionOnePresets() throws {
        let (folder, inputs) = try MetadataBatchEditingTests().input([[:]])
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = inputs[0]
        for format in MetadataFilenameDateFormat.allCases {
            let name = "holiday_" + format.example.replacingOccurrences(of: ".jpg", with: "_edited.jpg")
            let image = ImageData(metadata: input.image.metadata, name: name)
            let operation = MetadataOperation(tag: .captureDate, action: format.action)
            let preset = try MetadataPreset(name: format.rawValue, operations: [operation])
            #expect(try MetadataPreset.decode(preset.encode()) == preset)
            #expect(MetadataFilenameDateFormat.matching(format.action) == format)
            let result = try MetadataWorkflowPreview.prepare([(image, input.snapshot)], operations: preset.operations)
            let time = format.includesTime ? "14:30:25" : "00:00:00"
            #expect(result.items.first?.changes[.captureDate] == .set(.text("2026:11:02 " + time)))
        }
        #expect(MetadataFilenameDateFormat.matching(MetadataFilenameDateFormat.legacyDefaultAction) == .compactDateTime)
        #expect(MetadataFilenameDateFormat.matching(.filenameDate(pattern: "custom", template: "custom")) == nil)
    }

    @Test @MainActor func simpleFilenameDatesSkipInvalidAndPartialNumericMatches() throws {
        let names = ["2026.0230.jpg", "2026.11021.jpg", "12026.1102.jpg", "no-date.jpg"]
        let (folder, inputs) = try MetadataBatchEditingTests().input(Array(repeating: [:], count: names.count))
        defer { try? FileManager.default.removeItem(at: folder) }
        let readings = zip(inputs, names).map { reading, name in
            (image: ImageData(metadata: reading.image.metadata, name: name), snapshot: reading.snapshot)
        }
        let result = try MetadataWorkflowPreview.prepare(readings, operations: [
            MetadataOperation(tag: .captureDate, action: MetadataFilenameDateFormat.dottedDate.action)
        ])
        #expect(result.items.isEmpty && result.skipDetails.count == names.count)
    }

    @Test @MainActor func defaultsPreserveExistingPresetsAndOnlyInstallOnce() throws {
        let suite = "PhotoTrail.DefaultPresets.Tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let builtins = try MetadataPreset.defaultPresets()
        let custom = try MetadataPreset(name: builtins[0].name, operations: [
            MetadataOperation(tag: .titleDefault, action: .setText("keep"))
        ])
        defaults.set(try JSONEncoder().encode([custom]), forKey: "PhotoTrail.MetadataPresets")
        try MetadataPreset.installDefaultsIfNeeded(in: defaults)
        let installed = try MetadataPreset.stored(in: #require(defaults.data(forKey: "PhotoTrail.MetadataPresets")))
        #expect(installed == [custom] + Array(builtins.dropFirst()))
        defaults.set(Data("[]".utf8), forKey: "PhotoTrail.MetadataPresets")
        try MetadataPreset.installDefaultsIfNeeded(in: defaults)
        #expect(defaults.data(forKey: "PhotoTrail.MetadataPresets") == Data("[]".utf8))
    }

    @Test @MainActor func defaultsInstallForNewAndPreviouslyEmptyLibraries() throws {
        for data: Data? in [nil, Data(), Data("[]".utf8)] {
            let suite = "PhotoTrail.DefaultPresets.Tests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            if let data { defaults.set(data, forKey: "PhotoTrail.MetadataPresets") }
            try MetadataPreset.installDefaultsIfNeeded(in: defaults)
            let installed = try MetadataPreset.stored(in: #require(defaults.data(forKey: "PhotoTrail.MetadataPresets")))
            let expected = try MetadataPreset.defaultPresets()
            #expect(installed == expected)
            for preset in installed { #expect(try MetadataPreset.decode(preset.encode()) == preset) }
        }
    }

    @Test @MainActor func defaultsNeverOverwriteCorruptOrFutureLibraries() throws {
        for value: Any in [Data("invalid".utf8), Data(#"[{"version":99,"name":"future","operations":[]}]"#.utf8), "invalid"] {
            let suite = "PhotoTrail.DefaultPresets.Tests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(value, forKey: "PhotoTrail.MetadataPresets")
            #expect(throws: (any Error).self) { try MetadataPreset.installDefaultsIfNeeded(in: defaults) }
            #expect(!defaults.bool(forKey: "PhotoTrail.MetadataDefaultPresets.v1"))
            #expect((defaults.object(forKey: "PhotoTrail.MetadataPresets") as? NSObject) == (value as? NSObject))
        }
    }

    @Test @MainActor func defaultDateOperationsComputeAndSkipMissingSources() throws {
        let date = "2026:10:31 23:30:25.123+08:00"
        let (folder, readings) = try MetadataBatchEditingTests().input([[.captureDate: .text(date)], [:]])
        defer { try? FileManager.default.removeItem(at: folder) }
        let presets = try MetadataPreset.defaultPresets()
        let shifted = try MetadataWorkflowPreview.prepare(readings, operations: presets[0].operations)
        #expect(shifted.items.count == 1 && shifted.skipDetails.count == 1)
        #expect(shifted.items[0].changes[.captureDate] == .set(.text("2026:11:01 00:30:25.123+08:00")))
        let unified = try MetadataWorkflowPreview.prepare(readings, operations: presets[2].operations)
        #expect(unified.items.count == 1 && unified.skipDetails.count == 10)
        #expect(unified.items[0].changes[.dateOriginal] == .set(.text(date)))
        #expect(unified.items[0].changes[.sidecarDate] == .set(.text(date)))
        #expect(presets[2].operations.map(\.tag) == [.sidecarDate, .dateOriginal, .dateDigitized, .dateModified,
            .exifCreateDate, .exifModifyDate, .fileCreateDate, .fileModifyDate, .iptcDateCreated, .iptcTimeCreated])
        #expect(Set(unified.items[0].changes.keys) == Set(presets[2].operations.map(\.tag)))
        #expect(unified.items[0].changes[.iptcDateCreated] == .set(.text("2026:10:31")))
        #expect(unified.items[0].changes[.iptcTimeCreated] == .set(.text("23:30:25+08:00")))
    }

    @Test @MainActor func unifiedDefaultUpgradesUnchangedPresetsInEveryLanguageOnce() throws {
        let expected = try MetadataPreset.defaultPresets()[2].operations
        for language in AppLanguage.allCases {
            let suite = "PhotoTrail.DefaultDate.Tests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let name = L10n.string("统一照片的日期字段", language: language)
            let previous = try MetadataPreset(name: name, operations: [
                .init(tag: .dateOriginal, action: .copy(.captureDate)), .init(tag: .sidecarDate, action: .copy(.captureDate))
            ])
            defaults.set(try JSONEncoder().encode([previous]), forKey: "PhotoTrail.MetadataPresets")
            defaults.set(true, forKey: "PhotoTrail.MetadataDefaultPresets.v1")
            try MetadataPreset.installDefaultsIfNeeded(in: defaults)
            let installed = try MetadataPreset.stored(in: #require(defaults.data(forKey: "PhotoTrail.MetadataPresets")))
            #expect(installed.count == 1 && installed[0].name == name)
            #expect(installed[0].operations == expected)
            defaults.set(Data("[]".utf8), forKey: "PhotoTrail.MetadataPresets")
            try MetadataPreset.installDefaultsIfNeeded(in: defaults)
            #expect(defaults.data(forKey: "PhotoTrail.MetadataPresets") == Data("[]".utf8))
        }
    }

    @Test @MainActor func unifiedDefaultPreservesCustomRulesAndLocalParameters() throws {
        for mode in ["edited", "renamed", "deleted", "policy", "corrupt"] {
            let suite = "PhotoTrail.DefaultDate.Tests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let operations = [MetadataOperation(tag: .dateOriginal, action: .copy(.captureDate)),
                              MetadataOperation(tag: .sidecarDate, action: .copy(.captureDate))]
            let preset = try MetadataPreset(name: mode == "renamed" ? "mine" : L10n.text("统一照片的日期字段"),
                operations: mode == "edited" ? [.init(tag: .dateOriginal, action: .copy(.sidecarDate))] : operations)
            let data = try JSONEncoder().encode(mode == "deleted" ? [] : [preset])
            defaults.set(data, forKey: "PhotoTrail.MetadataPresets")
            defaults.set(true, forKey: "PhotoTrail.MetadataDefaultPresets.v1")
            if mode == "policy" {
                var cards = MetadataWorkflowCard.cards(from: operations)
                cards[0].datePolicy.offset = "+08:00"
                defaults.set(try MetadataPresetParameters.updating(preset, cards: cards, data: Data()), forKey: MetadataPresetParameters.key)
            } else if mode == "corrupt" {
                defaults.set(Data("invalid".utf8), forKey: MetadataPresetParameters.key)
            }
            let parameters = defaults.data(forKey: MetadataPresetParameters.key)
            if mode == "corrupt" {
                #expect(throws: Error.self) { try MetadataPreset.installDefaultsIfNeeded(in: defaults) }
                #expect(!defaults.bool(forKey: "PhotoTrail.MetadataUnifiedDatePreset.v2"))
            } else { try MetadataPreset.installDefaultsIfNeeded(in: defaults) }
            #expect(defaults.data(forKey: "PhotoTrail.MetadataPresets") == data)
            #expect(defaults.data(forKey: MetadataPresetParameters.key) == parameters)
        }
    }

    @Test @MainActor func defaultFilenameParserRejectsInvalidDatesAndUnmatchedNames() throws {
        let names = ["IMG_20261001_143025.jpg", "20261002_153026.JPG", "IMG_20260230_120000.jpg", "sample.jpg"]
        let (folder, inputs) = try MetadataBatchEditingTests().input(Array(repeating: [:], count: names.count))
        defer { try? FileManager.default.removeItem(at: folder) }
        let readings = zip(inputs, names).map { reading, name in
            (image: ImageData(metadata: reading.image.metadata, name: name), snapshot: reading.snapshot)
        }
        let preset = try MetadataPreset.defaultPresets()[1]
        let result = try MetadataWorkflowPreview.prepare(readings, operations: preset.operations)
        #expect(result.items.count == 2 && result.skipDetails.count == 2)
        #expect(result.items[0].changes[.captureDate] == .set(.text("2026:10:01 14:30:25")))
        #expect(result.items[1].changes[.captureDate] == .set(.text("2026:10:02 15:30:26")))
    }

    @Test @MainActor func copyrightTemplateRequiresInputAndPreservesExistingValues() throws {
        let preset = try MetadataPreset.defaultPresets()[3]
        #expect(preset.operations.allSatisfy { $0.action.hasEmptyInput })
        let (folder, readings) = try MetadataBatchEditingTests().input([
            [:], [.creator: .list(["existing"]), .rightsDefault: .text("existing rights")]
        ])
        defer { try? FileManager.default.removeItem(at: folder) }
        let filled = [MetadataOperation(tag: .creator, action: .fillMissingAuthors(["Photographer"])),
                      MetadataOperation(tag: .rightsDefault, action: .fillMissingText("© Photographer"))]
        let result = try MetadataWorkflowPreview.prepare(readings, operations: filled)
        #expect(result.items.count == 1)
        #expect(result.items[0].changes[.creator] == .set(.list(["Photographer"])))
        #expect(result.items[0].changes[.rightsDefault] == .set(.text("© Photographer")))
    }

    @Test func presetShortcutsPersistChoicesAndIgnoreRemovedNames() throws {
        let presets = try ["one", "two", "three", "four"].map {
            try MetadataPreset(name: $0, operations: [MetadataOperation(tag: .titleDefault, action: .setText($0))])
        }
        #expect(MetadataPresetShortcuts.names(in: presets, data: Data()) == ["one", "two", "three"])
        var data = MetadataPresetShortcuts.updating("two", enabled: false, in: presets, data: Data())
        data = MetadataPresetShortcuts.updating("four", enabled: true, in: presets, data: data)
        #expect(MetadataPresetShortcuts.names(in: presets, data: data) == ["one", "three", "four"])
        #expect(MetadataPresetShortcuts.names(in: Array(presets.dropFirst()), data: data) == ["three", "four"])
        let duplicates = try JSONEncoder().encode(["one", "one", "missing"])
        #expect(MetadataPresetShortcuts.names(in: presets, data: duplicates) == ["one"])
        let empty = try JSONEncoder().encode([String]())
        #expect(MetadataPresetShortcuts.names(in: presets, data: empty).isEmpty)
    }

    @Test func emptyAssignmentsCannotImplicitlyClearMixedValuesInEditors() {
        for action: MetadataFieldEditAction in [.replaceKeywords([]), .replaceKeywords([""]),
            .replaceAuthors([]), .fillMissingAuthors([]), .appendKeywords([]),
            .removeKeywords([]), .setText(""), .fillMissingText(""), .appendText("")] {
            #expect(action.hasEmptyInput)
        }
        for action: MetadataFieldEditAction in [.remove, .copy(.captureDate),
            .offsetDate(years: 0, months: 0, days: 0, hours: 1, minutes: 0, seconds: 0),
            .replaceKeywords(["A,B"]), .setText(" ")] {
            #expect(!action.hasEmptyInput)
        }
    }

    @Test func renamingPreservesOperationsAndRejectsNameConflicts() throws {
        let operation = MetadataOperation(tag: .captureDate, action: .shiftDate(seconds: 60))
        let presets = [try MetadataPreset(name: "图片", operations: [operation]),
                       try MetadataPreset(name: "图片 2", operations: [operation])]
        let renamed = try MetadataWorkflowCard.renamePreset("图片", to: "  统一时间  ", in: presets)
        #expect(renamed.map(\.name) == ["统一时间", "图片 2"])
        #expect(renamed[0].operations == presets[0].operations)
        #expect(try MetadataWorkflowCard.renamePreset("图片", to: "图片", in: presets) == presets)
        for invalid in ["图片 2", "  "] {
            #expect(throws: (any Error).self) {
                try MetadataWorkflowCard.renamePreset("图片", to: invalid, in: presets)
            }
        }
        #expect(throws: (any Error).self) {
            try MetadataWorkflowCard.renamePreset("不存在", to: "统一时间", in: presets)
        }
    }

    @Test func duplicatePresetNamesSkipExistingSuffixes() {
        #expect(MetadataWorkflowCard.uniquePresetName("图片", existing: ["图片", "图片 2"]) == "图片 3")
        #expect(MetadataWorkflowCard.uniquePresetName("图片", existing: ["图片", "图片 3"]) == "图片 2")
        #expect(MetadataWorkflowCard.uniquePresetName("图片 2", existing: ["图片 2"]) == "图片 2 2")
        #expect(MetadataWorkflowCard.uniquePresetName("图片", existing: [], allowOriginal: true) == "图片")
        #expect(MetadataWorkflowCard.uniquePresetName("图片", existing: ["图片", "图片 2"], allowOriginal: true) == "图片 3")
    }

    @Test func cardsPreserveOperationOrderAndLegacyPresetFormat() throws {
        let first = MetadataOperation(tag: .captureDate, action: .shiftDate(seconds: 60))
        let second = MetadataOperation(tag: .dateOriginal, action: .copy(.captureDate))
        let third = MetadataOperation(tag: .sidecarDate, action: .copy(.captureDate))
        var cards = MetadataWorkflowCard.cards(from: [first, second, third])
        #expect(cards.count == 2)
        #expect(cards.flatMap(\.operations) == [first, second, third])
        #expect(MetadataWorkflowCard.cards(from: [second, second]).count == 2)
        let selfCopy = MetadataOperation(tag: .captureDate, action: .copy(.captureDate))
        #expect(MetadataWorkflowCard.cards(from: [selfCopy, second]).count == 2)
        let id = cards[1].id
        cards.swapAt(0, 1)
        #expect(cards[0].id == id)
        let preset = try MetadataPreset(name: "日期", operations: cards.flatMap(\.operations))
        #expect(try MetadataPreset.decode(preset.encode()).operations == [second, third, first])
    }
}
