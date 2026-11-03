import Exiftool
import ImageData
import SwiftUI
import UDF

struct MetadataPresetQuickView: View {
    @Bindable var session: MetadataPresetSession
    var editRules: ([MetadataWorkflowCard]) -> Void
    var completed: (MetadataWorkflowPreview, [MetadataRecipeIssue]) -> Void
    @Environment(Store<PhotoTrailState, PhotoTrailEvent>.self) private var store
    @Environment(MetadataLoadingQueue.self) private var queue
    @AppStorage("PhotoTrail.MetadataPresets") private var presetData = Data()
    @AppStorage(MetadataPresetParameters.key) private var parameterData = Data()
    @State private var baseline: [MetadataWorkflowCard] = []
    @State private var launching = false
    @State private var active = false
    @Environment(\.metadataEditSession) private var inlineSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(session.original.name).font(.headline)
            ForEach(Array(session.cards.enumerated()), id: \.element.id) { index, card in
                VStack(alignment: .leading, spacing: 8) {
                    if session.cards.count > 1 { Text(L10n.text("操作 %1$@", index + 1)).font(.caption).foregroundStyle(.secondary) }
                    MetadataOperationCardView(operations: operations(card.id), readings: [], selected: .constant(true),
                        availableTags: MetadataTag.allCases, index: index, moveUp: nil, moveDown: nil, remove: {},
                        inlineLayout: true, quickParameters: true, datePolicy: policy(card.id))
                }
                if index + 1 < session.cards.count { Divider() }
            }
            .disabled(session.busy)
            if !session.notice.isEmpty { Text(session.notice).font(.caption).foregroundStyle(.orange) }
            if session.preparing {
                ProgressView(L10n.text("正在准备全部照片：%1$@/%2$@", session.preparationCount, store.imageData.count)).controlSize(.small)
            } else if !session.application.notice.isEmpty {
                Text(session.application.notice).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            HStack {
                Button(L10n.text("更新预设")) { update() }
                    .disabled(!changed || !session.isValid || session.busy)
                    .accessibilityIdentifier("metadataPresetUpdate")
                Button(L10n.text("编辑规则")) { editRules(session.cards) }.disabled(session.busy)
                Spacer(minLength: 8)
                if session.busy {
                    Button(L10n.text("取消")) { session.cancel() }
                } else {
                    Button(L10n.text("应用到全部 %1$@ 张照片", store.imageData.count)) {
                        guard !launching else { return }
                        launching = true
                        Task { @MainActor in
                            await Task.yield()
                            if let inlineSession, inlineSession.inline {
                                guard await inlineSession.finishInline(in: store) else { launching = false; return }
                            }
                            if active { session.applyAll(in: store, queue: queue) }
                            launching = false
                        }
                    }.buttonStyle(.borderedProminent)
                        .disabled(launching || !session.isValid || store.imageData.isEmpty || store.saveInProgress || store.renameInProgress || store.importProgress.isActive)
                        .accessibilityIdentifier("metadataPresetApplyAll")
                }
            }
        }
        .padding(12).background(Color.accentColor.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
        .textFieldStyle(.roundedBorder)
        .onAppear { active = true; if baseline.isEmpty { baseline = session.cards } }
        .onChange(of: session.cards) { session.application.resetFeedback() }
        .onChange(of: store.state) { session.application.stateChanged(store.state) }
        .onChange(of: session.application.busy) {
            if !session.application.busy, let result = session.application.result { completed(result, session.application.recipeIssues) }
        }
        .onDisappear { active = false; session.cancel() }
    }
    private var changed: Bool {
        session.cards.flatMap(\.operations) != baseline.flatMap(\.operations) || session.cards.map(\.datePolicy) != baseline.map(\.datePolicy)
    }
    private func operations(_ id: UUID) -> Binding<[MetadataOperation]> {
        Binding(get: { session.cards.first { $0.id == id }?.operations ?? [] }, set: { value in
            if let index = session.cards.firstIndex(where: { $0.id == id }) { session.cards[index].operations = value }
        })
    }
    private func policy(_ id: UUID) -> Binding<MetadataDateCopyPolicy> {
        Binding(get: { session.cards.first { $0.id == id }?.datePolicy ?? .init() }, set: { value in
            if let index = session.cards.firstIndex(where: { $0.id == id }) { session.cards[index].datePolicy = value }
        })
    }
    private func update() {
        do {
            let presets = try MetadataPreset.stored(in: presetData)
            guard let current = presets.first(where: { $0.name == session.original.name }),
                  current.operations == baseline.flatMap(\.operations),
                  try MetadataPresetParameters.cards(current, data: parameterData).map(\.datePolicy) == baseline.map(\.datePolicy) else {
                throw MetadataCreatorPlanError.sourceChanged
            }
            let data = try MetadataPresetSession.stored(name: current.name, cards: session.cards,
                presetData: presetData, parameterData: parameterData, replace: true)
            presetData = data.0; parameterData = data.1; baseline = session.cards
            session.notice = L10n.text("预设已保存。")
        } catch { session.notice = L10n.text("预设未保存，请检查名称、参数或已有预设数据。") }
    }
}
