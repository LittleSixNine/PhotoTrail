import Foundation
import ImageData

enum SettingsPreferences {
    static let metadataTextSizeKey = "PhotoTrailMetadataTextSize"
    static let metadataSpacingKey = "PhotoTrailMetadataSpacing"
    static let metadataTagNamesKey = "PhotoTrailMetadataTagNames"
    static let recordSearchesKey = "PhotoTrailRecordSearches"
    static let recentSearchesKey = "PhotoTrailRecentMapSearches"
    static let photoSortKey = "PhotoTrailPhotoSort.v1"

    struct PhotoSort: Codable, Equatable {
        var field: String
        var descending: Bool
    }

    static func photoSort(defaults: UserDefaults = .standard) -> [KeyPathComparator<ImageData>] {
        let saved = defaults.data(forKey: photoSortKey).flatMap { try? JSONDecoder().decode([PhotoSort].self, from: $0) } ?? []
        let sorts = saved.compactMap { item -> KeyPathComparator<ImageData>? in
            let order: SortOrder = item.descending ? .reverse : .forward
            switch item.field {
            case "name": return KeyPathComparator(\ImageData.name, order: order)
            case "captured": return KeyPathComparator(\ImageData.metadata.timestamp, order: order)
            case "import": return KeyPathComparator(\ImageData.id, order: order)
            default: return nil
            }
        }
        return sorts.isEmpty ? [KeyPathComparator(\ImageData.name)] : sorts
    }

    static func savePhotoSort(_ sorts: [KeyPathComparator<ImageData>], defaults: UserDefaults = .standard) {
        let saved = sorts.compactMap { sort -> PhotoSort? in
            let field: String
            switch sort.keyPath {
            case \ImageData.name: field = "name"
            case \ImageData.metadata.timestamp: field = "captured"
            case \ImageData.id: field = "import"
            default: return nil
            }
            return PhotoSort(field: field, descending: sort.order == .reverse)
        }
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: photoSortKey) }
    }

    static let showAllPhotoLocationsKey = "PhotoTrailShowAllPhotoLocations"
    static let mapStartupViewKey = "PhotoTrailMapStartupView"
    static let showSaveSummaryKey = "PhotoTrailShowSaveSummary"
    static let doubleClickKey = "PhotoTrailMapDoubleClickEdit"
    static let dragPinKey = "PhotoTrailMapPinDragEdit"
    static let cameraTimeZoneKey = "PhotoTrailCameraTimeZone"
    static let photoGPXGapKey = "PhotoTrailPhotoGPXGapMinutes"
    static let pairJPGRAWKey = "PhotoTrailPairJPGRAW"
    static let recursiveImportKey = "PhotoTrailRecursiveImport"
    static let automaticRegionKey = "PhotoTrailAutomaticRegionLookup"
    static let backupReminderKey = "PhotoTrailBackupReminderDays"
    static let saveCurrentPageKey = "PhotoTrailSaveCurrentPage"
    static let skipSaveScopePromptKey = "PhotoTrailSkipSaveScopePrompt"
    static let writeRegionKey = "PhotoTrailWriteRegionWithLocation"

    static let startupWorkspaceKey = "PhotoTrailStartupWorkspace"
    static let lastWorkspaceKey = "PhotoTrailLastWorkspace"

    enum Workspace: String, CaseIterable, Identifiable {
        case last, metadata, map, rename
        var id: Self { self }
        var title: String {
            switch self {
            case .last: L10n.text("上次工作区")
            case .metadata: L10n.text("元数据编辑")
            case .map: L10n.text("地图定位")
            case .rename: L10n.text("重命名")
            }
        }
    }

    static func initialWorkspace(defaults: UserDefaults = .standard) -> Workspace {
        let preference = defaults.string(forKey: startupWorkspaceKey).flatMap(Workspace.init(rawValue:)) ?? .last
        if preference != .last { return preference }
        if let last = defaults.string(forKey: lastWorkspaceKey).flatMap(Workspace.init(rawValue:)), last != .last { return last }
        return defaults.bool(forKey: "AlternateLayout") ? .map : .metadata
    }

    enum MapStartupView: String, CaseIterable, Identifiable {
        case device, last
        var id: Self { self }
        var title: String {
            switch self {
            case .device: L10n.text("设备当前位置")
            case .last: L10n.text("上次地图视野")
            }
        }
    }

    static func displayedPhotos(_ images: [ImageData], selection: Set<ImageData.ID>,
                                showAll: Bool) -> [ImageData] {
        showAll ? images : images.filter { selection.contains($0.id) }
    }

    static var initialCameraTimeZone: TimeZone {
        let identifier = UserDefaults.standard.string(forKey: cameraTimeZoneKey) ?? ""
        return TimeZone(identifier: identifier) ?? .current
    }

    static var photoGPXGap: TimeInterval {
        let value = UserDefaults.standard.object(forKey: photoGPXGapKey) as? Double ?? 5
        return value.isFinite && value > 0 && value <= 1_000_000 ? value * 60 : 300
    }

    static var backupReminderDays: Int? {
        let value = UserDefaults.standard.object(forKey: backupReminderKey) as? Int ?? 7
        return [7, 30, 90].contains(value) ? value : nil
    }
}

enum MetadataSaveScope: String { case all, metadata, map }
