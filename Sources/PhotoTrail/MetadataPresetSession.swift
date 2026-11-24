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
    var activeCards: [MetadataWorkflowCard] {
        cards.compactMap(\.executableCard)
    }
    var isValid: Bool { !activeCards.isEmpty && activeCards.allSatisfy(\.isComplete) }

    init(preset: MetadataPreset, parameters: Data) throws {
        original = preset
        cards = try MetadataPresetParameters.cards(preset, data: parameters)
    }

    static func stored(name: String, cards: [MetadataWorkflowCard], presetData: Data, parameterData: Data,
                       replace: Bool) throws -> (Data, Data) {
        guard !cards.isEmpty else { throw MetadataFieldEditError.invalidValue }
        let active = cards.compactMap(\.executableCard)
        if !active.isEmpty { try MetadataBatchRecipe.validate(active) }
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

    var onlySelected = false
    func scope(in state: PhotoTrailState) -> [ImageData] {
        onlySelected ? state.members(of: state.selection) : state.imageData
    }

    var targetOperations: [MetadataOperation] { activeCards.flatMap(\.operations) }
    func targets(_ images: [ImageData]) -> [ImageData] {
        let operations = targetOperations
        return images.filter { image in operations.contains { $0.applies(to: image) } }
    }

    func applyAll(in store: Store<PhotoTrailState, PhotoTrailEvent>, queue: MetadataLoadingQueue) {
        guard !busy, isValid, !store.imageData.isEmpty, !store.saveInProgress,
              !store.renameInProgress, !store.importProgress.isActive else { return }
        let selectedScope = onlySelected ? store.selection : nil
        let images = targets(scope(in: store.state)).sorted(using: store.sortOrder)
        guard !images.isEmpty else { return }
        queue.synchronize(store.imageData)
        let cards = activeCards
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
                      MetadataDraftRequest(readings: readings, requiresSelection: false, requiresAllPhotos: true,
                                           selectedScope: selectedScope, allTargetOperations: targetOperations).matches(store.state, checkFiles: true) else {
                    throw MetadataCreatorPlanError.sourceChanged
                }
                application.apply(readings: readings, operations: [], requiresSelection: false,
                                  cards: cards, requiresAllPhotos: true, selectedScope: selectedScope, store: store)
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
