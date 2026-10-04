import Exiftool
import ImageData
import UDF

enum MetadataQuickEdit {
    static func action(_ text: String, tag: MetadataTag) -> MetadataFieldEditAction {
        if text.isEmpty { return .remove }
        if tag == .creator { return .replaceAuthors(text.components(separatedBy: "\n")) }
        if tag.isList { return .replaceKeywords(text.components(separatedBy: "\n")) }
        if tag.isDate, text.count >= 10 {
            return .setText(text.prefix(10).replacingOccurrences(of: "-", with: ":") + text.dropFirst(10))
        }
        return .setText(text)
    }

    @MainActor static func apply(_ action: MetadataFieldEditAction, tag: MetadataTag,
                                 readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)],
                                 store: Store<PhotoTrailState, PhotoTrailEvent>) throws {
        guard !readings.isEmpty, !store.saveInProgress else { throw MetadataCreatorPlanError.unavailableTarget }
        let current = try readings.map { reading in
            guard let image = store.imageData.first(where: { $0.id == reading.image.id }),
                  image.metadataInspectionURL == reading.image.metadataInspectionURL,
                  image.metadataCreatorImageURL == reading.image.metadataCreatorImageURL,
                  !image.hasLegacyChanges, store.creatorSaveResults[image.id] != .resultUnknown else {
                throw MetadataCreatorPlanError.sourceChanged
            }
            return (image: image, snapshot: reading.snapshot)
        }
        let plan = try MetadataCreatorEditPlan.prepare(current, tag: tag, action: action)
        guard plan.items.contains(where: { $0.change != nil }) else { return }
        store.send(.creatorDraftApplied(plan.items), description: L10n.text("编辑元数据…"))
    }
}
