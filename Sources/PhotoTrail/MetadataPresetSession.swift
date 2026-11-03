import Exiftool
import Foundation
import ImageData
import SwiftUI
import UDF

@MainActor @Observable
final class MetadataPresetSession: Identifiable {
    let id = UUID()
    let original: MetadataPreset
    var cards: [MetadataWorkflowCard]
    var preparing = false
    var preparationCount = 0
    var notice = ""
    let application = MetadataDraftApplication()
    private var preparation: Task<Void, Never>?
    private var generation = UUID()
    var busy: Bool { preparing || application.busy }
    var isValid: Bool { !cards.isEmpty && cards.allSatisfy(\.isComplete) }

    init(preset: MetadataPreset, parameters: Data) throws {
        original = preset
        cards = try MetadataPresetParameters.cards(preset, data: parameters)
    }

    static func stored(name: String, cards: [MetadataWorkflowCard], presetData: Data, parameterData: Data,
                       replace: Bool) throws -> (Data, Data) {
        guard !cards.isEmpty, cards.allSatisfy(\.isComplete) else { throw MetadataFieldEditError.invalidValue }
        try MetadataBatchRecipe.validate(cards)
        let preset = try MetadataPreset(name: name, operations: cards.flatMap(\.operations))
        var presets = try MetadataPreset.stored(in: presetData)
        if let index = presets.firstIndex(where: { $0.name == name }) {
            guard replace else { throw MetadataFieldEditError.invalidValue }
            presets[index] = preset
        } else {
            guard !replace else { throw MetadataFieldEditError.invalidValue }
            presets.append(preset)
        }
        let data = try JSONEncoder().encode(presets)
        let parameters = try MetadataPresetParameters.updating(preset, cards: cards, data: parameterData)
        return (data, parameters)
    }

    func cancel() {
        generation = UUID(); preparation?.cancel(); preparation = nil; preparing = false
        application.cancel()
    }

    func applyAll(in store: Store<PhotoTrailState, PhotoTrailEvent>, queue: MetadataLoadingQueue) {
        guard !busy, isValid, !store.imageData.isEmpty, !store.saveInProgress,
              !store.renameInProgress, !store.importProgress.isActive else { return }
        let images = store.imageData.sorted(using: store.sortOrder)
        queue.synchronize(images)
        let cards = cards
        let token = UUID(); generation = token; preparing = true; preparationCount = 0; notice = ""
        preparation = Task {
            do {
                var readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)] = []
                for image in images {
                    try Task.checkCancellation()
                    guard generation == token, image.supportsMetadataEditing, image.updatable, !image.hasLegacyDateChanges,
                          store.state.creatorSaveResults[image.id] != .resultUnknown,
                          case .editable(let snapshot, _) = await queue.read(
                            MetadataInspectionRequest(id: image.id, url: image.metadataInspectionURL,
                                                      creatorImageURL: image.metadataCreatorImageURL), kind: .editable) else {
                        throw MetadataCreatorPlanError.sourceChanged
                    }
                    readings.append((image, snapshot)); preparationCount += 1
                }
                try Task.checkCancellation()
                guard generation == token,
                      MetadataDraftRequest(readings: readings, requiresSelection: false, requiresAllPhotos: true).matches(store.state, checkFiles: true) else {
                    throw MetadataCreatorPlanError.sourceChanged
                }
                application.apply(readings: readings, operations: [], requiresSelection: false,
                                  cards: cards, requiresAllPhotos: true, store: store)
            } catch {
                guard generation == token else { return }
                notice = error is CancellationError ? L10n.text("已取消，未加入待保存修改。")
                    : L10n.text("照片列表或来源不可用，未应用预设。请重新读取后重试。")
            }
            guard generation == token else { return }
            preparing = false; preparation = nil
        }
    }
}

private struct MetadataPresetEditorKey: EnvironmentKey {
    static let defaultValue: (@MainActor (MetadataPreset) -> Void)? = nil
}
extension EnvironmentValues {
    var metadataPresetEditor: (@MainActor (MetadataPreset) -> Void)? {
        get { self[MetadataPresetEditorKey.self] }
        set { self[MetadataPresetEditorKey.self] = newValue }
    }
}
