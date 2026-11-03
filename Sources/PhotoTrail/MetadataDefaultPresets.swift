import Exiftool
import Foundation
import ImageData

extension MetadataPreset {
    static func defaultPresets() throws -> [MetadataPreset] {
        try [
            MetadataPreset(name: L10n.text("拍摄时间加 1 小时"), operations: [
                MetadataOperation(tag: .captureDate, action: .offsetDate(years: 0, months: 0, days: 0,
                                                                         hours: 1, minutes: 0, seconds: 0))
            ]),
            MetadataPreset(name: L10n.text("从文件名恢复拍摄时间"), operations: [
                MetadataOperation(tag: .captureDate, action: .filenameDate(
                    pattern: #"^(?:IMG_)?(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})(?:\.[^.]+)$"#,
                    template: "$1:$2:$3 $4:$5:$6"))
            ]),
            MetadataPreset(name: L10n.text("统一照片的日期字段"), operations: unifiedDateOperations),
            MetadataPreset(name: L10n.text("补齐作者与版权"), operations: [
                MetadataOperation(tag: .creator, action: .fillMissingAuthors([])),
                MetadataOperation(tag: .rightsDefault, action: .fillMissingText(""))
            ])
        ]
    }

    static func installDefaultsIfNeeded(in defaults: UserDefaults = .standard) throws {
        let installedKey = "PhotoTrail.MetadataDefaultPresets.v1"
        let updatedDateKey = "PhotoTrail.MetadataUnifiedDatePreset.v2"
        let installed = defaults.bool(forKey: installedKey)
        guard !installed || !defaults.bool(forKey: updatedDateKey) else { return }
        let key = "PhotoTrail.MetadataPresets"
        guard defaults.object(forKey: key) == nil || defaults.data(forKey: key) != nil else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let original = try stored(in: defaults.data(forKey: key) ?? Data())
        var entries = original
        if installed {
            let names = Set(AppLanguage.allCases.map { L10n.string("统一照片的日期字段", language: $0) })
            let previous = [MetadataTag.dateOriginal, .sidecarDate].map { MetadataOperation(tag: $0, action: .copy(.captureDate)) }
            let candidates = entries.indices.filter { names.contains(entries[$0].name) && entries[$0].operations == previous }
            if !candidates.isEmpty {
                let parameterKey = MetadataPresetParameters.key
                guard defaults.object(forKey: parameterKey) == nil || defaults.data(forKey: parameterKey) != nil else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                let parameters = try MetadataPresetParameters.entries(defaults.data(forKey: parameterKey) ?? Data())
                for index in candidates {
                    if let saved = parameters[entries[index].name], saved.operations == previous,
                       saved.policies.contains(where: { !$0.isEmpty }) { continue }
                    entries[index] = try MetadataPreset(name: entries[index].name, operations: unifiedDateOperations)
                }
            }
        } else {
            let names = Set(entries.map(\.name))
            entries += try defaultPresets().filter { !names.contains($0.name) }
        }
        if !installed || entries != original { defaults.set(try JSONEncoder().encode(entries), forKey: key) }
        defaults.set(true, forKey: installedKey)
        defaults.set(true, forKey: updatedDateKey)
    }

    private static var unifiedDateOperations: [MetadataOperation] {
        [MetadataTag.sidecarDate, .dateOriginal, .dateDigitized, .dateModified, .exifCreateDate, .exifModifyDate,
         .fileCreateDate, .fileModifyDate, .iptcDateCreated, .iptcTimeCreated].map {
            MetadataOperation(tag: $0, action: .copy(.captureDate))
        }
    }
}
