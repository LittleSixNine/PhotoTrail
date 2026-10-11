import Exiftool
import ImageData
import SwiftUI
import UDF

// Freeze only the state that can change this batch's meaning.
struct MetadataDraftRequest: Sendable {
    let readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)]
    let selection: Set<ImageData.ID>
    let order: [ImageData.ID]

    init(readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)]) {
        self.readings = readings
        selection = Set(readings.map(\.image.id))
        order = readings.map(\.image.id)
    }

    @MainActor func matches(_ state: PhotoTrailState, checkFiles: Bool = false) -> Bool {
        guard !state.saveInProgress, !state.renameInProgress, !state.importProgress.isActive, state.selection == selection,
              state.imageData.filter({ selection.contains($0.id) }).sorted(using: state.sortOrder).map(\.id) == order else { return false }
        let images = Dictionary(uniqueKeysWithValues: state.imageData.map { ($0.id, $0) })
        return readings.allSatisfy { reading in
            guard let image = images[reading.image.id], image.updatable, !image.hasLegacyChanges,
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
               store: Store<PhotoTrailState, PhotoTrailEvent>) {
        guard !busy, !applied, !store.saveInProgress else { return }
        let request = MetadataDraftRequest(readings: readings)
        guard request.matches(store.state) else { notice = L10n.text("来源文件已变化；请重新读取元数据。"); return }
        let id = UUID()
        self.request = request; requestID = id; busy = true
        notice = L10n.text("正在准备应用…")
        let worker = Task.detached(priority: .userInitiated) {
            await self.calculationDidStart(id)
            try Task.checkCancellation()
            if let imported {
                // Imported CSV has already passed identity/conflict validation; revalidate every source.
                _ = try MetadataCreatorEditPlan.prepare(readings, action: .fillMissing(["validation"]))
                return imported
            }
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
                    store.send(.creatorDraftApplied(result.items), description: L10n.text("编辑元数据…"))
                }
                let missing = result.skipped.filter { result.skipReasons[$0] == .missingValue }.count
                let unmatched = result.skipped.filter { result.skipReasons[$0] == .filenameMismatch }.count
                notice = L10n.text("结果：%1$@ 张修改；%2$@ 张无变化；缺失跳过 %3$@ 项；文件名未匹配 %4$@ 项。",
                    result.items.count, Set(result.steps.map(\.id)).subtracting(result.items.map(\.id)).count, missing, unmatched)
                if !result.skipped.isEmpty && result.skipReasons.isEmpty { notice += "\n" + result.skipped.joined(separator: "\n") }
                applied = !result.items.isEmpty
                requestID = nil; self.request = nil; self.worker = nil; busy = false
            } catch {
                guard requestID == id else { return }
                cancel()
                if case Exiftool.ExiftoolError.unsupportedIPTCEncoding = error {
                    notice = L10n.text("现有 IPTC 未明确声明 UTF-8，已阻止写入以保留原编码。")
                } else if error is CancellationError { notice = L10n.text("已取消，未加入待保存修改。") }
                else { notice = L10n.text("操作失败：%1$@", String(describing: error)) }
            }
        }
    }
}
