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
            MetadataPreset(name: L10n.text("统一照片的日期字段"), operations: [
                MetadataOperation(tag: .dateOriginal, action: .copy(.captureDate)),
                MetadataOperation(tag: .sidecarDate, action: .copy(.captureDate))
            ]),
            MetadataPreset(name: L10n.text("补齐作者与版权"), operations: [
                MetadataOperation(tag: .creator, action: .fillMissingAuthors([])),
                MetadataOperation(tag: .rightsDefault, action: .fillMissingText(""))
            ])
        ]
    }

    static func installDefaultsIfNeeded(in defaults: UserDefaults = .standard) throws {
        let installedKey = "PhotoTrail.MetadataDefaultPresets.v1"
        guard !defaults.bool(forKey: installedKey) else { return }
        let key = "PhotoTrail.MetadataPresets"
        guard defaults.object(forKey: key) == nil || defaults.data(forKey: key) != nil else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let entries = try stored(in: defaults.data(forKey: key) ?? Data())
        let names = Set(entries.map(\.name))
        let additions = try defaultPresets().filter { !names.contains($0.name) }
        defaults.set(try JSONEncoder().encode(entries + additions), forKey: key)
        defaults.set(true, forKey: installedKey)
    }
}
