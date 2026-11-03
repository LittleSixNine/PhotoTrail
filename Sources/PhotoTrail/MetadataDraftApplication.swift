import Exiftool
import ImageData
import SwiftUI
import UDF

// Freeze only the state that can change this batch's meaning.
struct MetadataDraftRequest: Sendable {
    let readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)]
    let selection: Set<ImageData.ID>
    let order: [ImageData.ID]
    let requiresSelection: Bool
    let requiresAllPhotos: Bool

    init(readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)], requiresSelection: Bool = true, requiresAllPhotos: Bool = false) {
        self.requiresSelection = requiresSelection
        self.requiresAllPhotos = requiresAllPhotos
        self.readings = readings
        selection = Set(readings.map(\.image.id))
        order = readings.map(\.image.id)
    }

    @MainActor func matches(_ state: PhotoTrailState, checkFiles: Bool = false) -> Bool {
        guard !state.saveInProgress, !state.renameInProgress, !state.importProgress.isActive, (!requiresSelection || state.selection == selection),
              (!requiresSelection || state.imageData.filter({ selection.contains($0.id) }).sorted(using: state.sortOrder).map(\.id) == order) else { return false }
        if requiresAllPhotos && state.imageData.sorted(using: state.sortOrder).map(\.id) != order { return false }
        let images = Dictionary(uniqueKeysWithValues: state.imageData.map { ($0.id, $0) })
        return readings.allSatisfy { reading in
            guard let image = images[reading.image.id], image.updatable == reading.image.updatable, !image.hasLegacyDateChanges,
                  image.name == reading.image.name,
                  image.metadata == reading.image.metadata, image.creatorDraft == reading.image.creatorDraft,
                  state.creatorSaveResults[image.id] != .resultUnknown else { return false }
            return !checkFiles || MetadataInspectionFileVersion.read(reading.snapshot.url) == reading.snapshot.version
        }
    }
}

@MainActor @Observable
final class MetadataDraftApplication {
    private(set) var busy = false
    private(set) var applied = false
    private(set) var calculationStarted = false
    private(set) var notice = ""
    private(set) var result: MetadataWorkflowPreview?
    private(set) var recipeIssues: [MetadataRecipeIssue] = []
    private(set) var appliedImageRevision: UUID?
    private(set) var appliedUndoDescription = ""
    private var request: MetadataDraftRequest?
    private var requestID: UUID?
    private var worker: Task<MetadataWorkflowPreview, Error>?

    func cancel() {
        requestID = nil
        worker?.cancel()
        worker = nil
        request = nil
        busy = false
        calculationStarted = false
    }

    func stateChanged(_ state: PhotoTrailState) {
        if let request, !request.matches(state) { cancel(); notice = L10n.text("来源文件已变化；请重新读取元数据。") }
    }

    private func calculationDidStart(_ id: UUID) {
        guard requestID == id else { return }
        calculationStarted = true
        notice = L10n.text("正在计算与校验…")
    }

    func apply(readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)],
               operations: [MetadataOperation], imported: MetadataWorkflowPreview? = nil,
               description: String? = nil, requiresSelection: Bool = true, dateBatch: MetadataDateBatch? = nil, cards: [MetadataWorkflowCard]? = nil, requiresAllPhotos: Bool = false,
               store: Store<PhotoTrailState, PhotoTrailEvent>) {
        guard !busy, !applied, !store.saveInProgress else { return }
        let request = MetadataDraftRequest(readings: readings, requiresSelection: requiresSelection, requiresAllPhotos: requiresAllPhotos)
        guard request.matches(store.state) else {
            notice = L10n.text("来源文件已变化；请重新读取元数据。")
            OperationFailure.present(notice); return
        }
        result = nil; recipeIssues = []
        let id = UUID()
        self.request = request; requestID = id; busy = true
        notice = L10n.text("正在准备应用…")
        let worker = Task.detached(priority: .userInitiated) {
            await self.calculationDidStart(id)
            try Task.checkCancellation()
            if let imported {
                // Imported CSV has already passed identity/conflict validation; revalidate every source.
                try MetadataWorkflowPreview.validateSources(readings)
                return imported
            }
            if let cards {
                let prepared = try MetadataBatchRecipe.prepare(readings, cards: cards)
                await self.recipePrepared(prepared.issues, requestID: id)
                return prepared.preview
            }
            if let dateBatch { return try dateBatch.prepare(readings) }
            return try MetadataWorkflowPreview.prepare(readings, operations: operations)
        }
        self.worker = worker
        Task {
            do {
                let result = try await worker.value
                guard requestID == id else { return }
                notice = L10n.text("正在复核来源并加入待保存…")
                guard request.matches(store.state, checkFiles: true) else { throw MetadataCreatorPlanError.sourceChanged }
                if !result.items.isEmpty {
                    store.send(.creatorDraftApplied(result.items), description: description ?? L10n.text("编辑元数据…"))
                    appliedImageRevision = store.state.imageRevision
                    appliedUndoDescription = store.undoDescription
                }
                let missing = result.skipped.filter { result.skipReasons[$0] == .missingValue }.count
                let unmatched = result.skipped.filter { result.skipReasons[$0] == .filenameMismatch }.count
                notice = L10n.text("结果：%1$@ 张修改；%2$@ 张无变化；缺失跳过 %3$@ 项；文件名未匹配 %4$@ 项。",
                    result.items.count, Set(result.steps.map(\.id)).subtracting(result.items.map(\.id)).count, missing, unmatched)
                if !result.skipped.isEmpty && result.skipReasons.isEmpty { notice += "\n" + result.skipped.joined(separator: "\n") }
                let unsupported = result.skipped.filter { result.skipReasons[$0] == .unsupportedField }
                if !unsupported.isEmpty {
                    notice += "\n" + L10n.text("已跳过不支持的文件或字段") + "\n" + unsupported.joined(separator: "\n")
                }
                self.result = result
                applied = !result.items.isEmpty
                requestID = nil; self.request = nil; self.worker = nil; busy = false
            } catch {
                guard requestID == id else { return }
                cancel()
                if case Exiftool.ExiftoolError.unsupportedIPTCEncoding = error {
                    notice = L10n.text("现有 IPTC 未明确声明 UTF-8，已阻止写入以保留原编码。")
                } else if case Exiftool.ExiftoolError.invalidTagValue(let tag) = error {
                    notice = tag == MetadataTag.iptcTimeCreated.rawValue
                        ? L10n.text("IPTC 时间必须包含时区，例如 12:34:56+08:00。")
                        : L10n.text("字段值格式无效：%1$@", tag)
                } else if error is CancellationError { notice = L10n.text("已取消，未加入待保存修改。") }
                else { notice = L10n.text("操作失败：%1$@", String(describing: error)) }
                if !(error is CancellationError) { OperationFailure.present(notice) }
            }
        }
    }

    private func recipePrepared(_ issues: [MetadataRecipeIssue], requestID: UUID) {
        if self.requestID == requestID { recipeIssues = issues }
    }

    func canUndo(in store: Store<PhotoTrailState, PhotoTrailEvent>) -> Bool {
        applied && !store.saveInProgress && store.canUndo && store.state.imageRevision == appliedImageRevision
            && store.undoDescription == appliedUndoDescription
    }

    func resetFeedback() {
        guard !busy, !applied else { return }
        result = nil; notice = ""
    }

    func undo(in store: Store<PhotoTrailState, PhotoTrailEvent>) {
        guard canUndo(in: store) else { return }
        store.undo()
        applied = false; result = nil; appliedImageRevision = nil; notice = L10n.text("已撤销本次批量修改。")
    }
}
