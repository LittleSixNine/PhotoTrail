import Exiftool
import ImageData
import SwiftUI
import UDF

struct MetadataPresetQuickView: View {
    let session: MetadataPresetSession
    @Binding var expanded: Bool
    @Binding var onlySelected: Bool
    var editRules: ([MetadataWorkflowCard]) -> Void
    var completed: (MetadataWorkflowPreview, [MetadataRecipeIssue]) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var contentHeight: CGFloat = 0
    @State private var measuredSession: UUID?

    private var reveal: Animation? { reduceMotion ? nil : .easeOut(duration: 0.22) }

    var body: some View {
        VStack(spacing: 0) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill").foregroundStyle(Color.accentColor)
                    Text(session.original.name).font(.headline)
                    Spacer()
                    Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(expanded ? 0 : -90))
                        .animation(reveal, value: expanded)
                        .foregroundStyle(.secondary)
                }.padding(.horizontal, 12).padding(.vertical, 9).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color.accentColor.opacity(0.09))
            .accessibilityLabel(Text(session.original.name))
            .accessibilityValue(Text(L10n.text(expanded ? "已展开" : "已收起")))
            .accessibilityIdentifier("metadataPresetDisclosure")
            .disabled(session.busy)

            ScrollView {
                MetadataPresetForm(session: session, onlySelected: $onlySelected, editRules: editRules, completed: completed)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        let isNewPreset = measuredSession != session.id
                        measuredSession = session.id
                        withAnimation(isNewPreset ? reveal : nil) { contentHeight = height }
                    }
                    .id(session.id)
                    .transition(.opacity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .animation(reveal, value: session.id)
            .frame(idealHeight: expanded ? contentHeight : 0, maxHeight: expanded ? contentHeight : 0, alignment: .top)
            .clipped()
            .animation(reveal, value: expanded)
            .allowsHitTesting(expanded)
            .accessibilityHidden(!expanded)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(.secondary.opacity(0.22)).allowsHitTesting(false) }
        .padding(.vertical, 3)
    }
}

private struct MetadataPresetForm: View {
    @Bindable var session: MetadataPresetSession
    @Binding var onlySelected: Bool
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

    private var scope: MetadataRuleScope { MetadataRuleScope(session.targetOperations, in: session.scope(in: store.state)) }

    var body: some View {
        let scope = self.scope
        VStack(alignment: .leading, spacing: 12) {
            MetadataPresetScopePicker(onlySelected: $onlySelected).disabled(session.busy)
            let configuredOperations = session.cards.flatMap(\.operations)
            let support = MetadataRuleScope(configuredOperations, in: session.scope(in: store.state))
            if support.skipped > 0 {
                let icons = MetadataMediaIcons(operations: configuredOperations)
                Text(icons.label + " · " + support.description).font(.caption).foregroundStyle(.red)
            }
            ForEach(Array(session.cards.enumerated()), id: \.element.id) { index, card in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(card.operations.map(\.tag.displayName).joined(separator: " · ")).font(.subheadline.weight(.medium))
                        Spacer()
                        MetadataMediaIcons(operations: card.operations)
                    }
                    if let guidance = card.parameterGuidance {
                        Text(guidance).font(.caption).foregroundStyle(.secondary)
                    }
                    MetadataRuleScopeText(card: card, images: session.scope(in: store.state),
                                          alreadyExplained: support.skipped > 0 ? support : nil)
                    MetadataOperationCardView(operations: operations(card.id), readings: [], selected: .constant(true),
                        availableTags: MetadataTag.allCases, index: index, moveUp: nil, moveDown: nil, remove: {},
                        inlineLayout: true, quickParameters: true, datePolicy: policy(card.id))
                }
                if index + 1 < session.cards.count { Divider() }
            }
            .disabled(session.busy)
            if !session.notice.isEmpty { Text(session.notice).font(.caption).foregroundStyle(.orange) }
            if session.preparing {
                ProgressView(L10n.text("正在准备文件：%1$@/%2$@", session.preparationCount, scope.count)).controlSize(.small)
            } else if !session.application.notice.isEmpty {
                Text(session.application.notice).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            HStack {
                Button(L10n.text("更新预设")) { update() }
                    .disabled(!changed || !session.activeCards.allSatisfy(\.isComplete) || session.busy)
                    .accessibilityIdentifier("metadataPresetUpdate")
                Button(L10n.text("编辑规则")) { editRules(session.cards) }.disabled(session.busy)
                Spacer(minLength: 8)
                if session.busy {
                    Button(L10n.text("取消")) { session.cancel() }
                } else {
                    Button(scope.applyLabel) {
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
                        .disabled(launching || !session.isValid || scope.count == 0 || store.saveInProgress || store.renameInProgress || store.importProgress.isActive)
                        .accessibilityIdentifier("metadataPresetApplyAll")
                }
            }
        }
        .padding(12)
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

struct MetadataMediaIcons: View {
    let supportsPhotos: Bool
    let supportsVideo: Bool

    init(operations: [MetadataOperation]) {
        supportsPhotos = operations.contains(where: \.supportsPhotoEditing)
        supportsVideo = operations.contains(where: \.supportsMovieEditing)
    }

    var label: String {
        if supportsPhotos && supportsVideo { return L10n.text("适用于照片和视频") }
        if supportsPhotos { return L10n.text("仅适用于照片") }
        if supportsVideo { return L10n.text("仅适用于视频") }
        return L10n.text("文件不支持此字段")
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "photo").frame(width: 16).opacity(supportsPhotos ? 1 : 0)
            Image(systemName: "video").frame(width: 16).opacity(supportsVideo ? 1 : 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .help(label)
    }
}

struct MetadataPresetScopePicker: View {
    @Binding var onlySelected: Bool

    var body: some View {
        Picker(L10n.text("操作范围"), selection: $onlySelected) {
            Text(L10n.text("全部导入文件")).tag(false)
            Text(L10n.text("当前选中项")).tag(true)
        }.pickerStyle(.segmented)
    }
}

struct MetadataRuleScope: Equatable {
    private(set) var photos = 0
    private(set) var videos = 0
    private(set) var skippedPhotos = 0
    private(set) var skippedVideos = 0
    var count: Int { photos + videos }
    var skipped: Int { skippedPhotos + skippedVideos }

    init(_ operations: [MetadataOperation], in images: [ImageData]) {
        for image in images {
            if operations.contains(where: { $0.applies(to: image) }) {
                if image.isLocalMovie { videos += 1 } else { photos += 1 }
            } else if image.isLocalMovie { skippedVideos += 1 } else { skippedPhotos += 1 }
        }
    }

    var skipLabel: String? {
        guard skipped > 0 else { return nil }
        if skippedPhotos == 0 { return L10n.text("跳过 %1$@ 段视频", skippedVideos) }
        if skippedVideos == 0 { return L10n.text("跳过 %1$@ 张照片", skippedPhotos) }
        return L10n.text("跳过 %1$@ 项", skipped)
    }

    var applyLabel: String {
        if photos > 0, videos == 0 { return L10n.text("应用到 %1$@ 张照片", photos) }
        if videos > 0, photos == 0 { return L10n.text("应用到 %1$@ 段视频", videos) }
        return L10n.text("应用到 %1$@ 项", count)
    }

    var description: String {
        if photos > 0, videos == 0, skippedVideos > 0, skippedPhotos == 0 {
            return L10n.text("仅更改 %1$@ 张照片，跳过 %2$@ 段视频。", photos, skippedVideos)
        }
        if videos > 0, photos == 0, skippedPhotos > 0, skippedVideos == 0 {
            return L10n.text("仅更改 %1$@ 段视频，跳过 %2$@ 张照片。", videos, skippedPhotos)
        }
        return L10n.text("本规则适用于 %1$@ 张照片、%2$@ 段视频，跳过 %3$@ 项", photos, videos, skipped)
    }
}

struct MetadataRuleScopeText: View {
    let card: MetadataWorkflowCard
    let images: [ImageData]
    var alreadyExplained: MetadataRuleScope?

    var body: some View {
        if let active = card.executableCard {
            let scope = MetadataRuleScope(active.operations, in: images)
            if scope != alreadyExplained {
                Text(scope.description).font(.caption)
                    .foregroundStyle(scope.skipped > 0 ? Color.red : .secondary)
            }
        } else {
            Text(L10n.text("本步留空，将跳过。")).font(.caption).foregroundStyle(.red)
        }
    }
}

struct MetadataPresetChooser: View {
    let presets: [MetadataPreset]
    let images: [ImageData]
    @Binding var onlySelected: Bool
    let shortcuts: [String]
    let toggleShortcut: (String, Bool) -> Void
    let choose: (MetadataPreset) -> Void
    let manage: () -> Void
    @State private var choosingShortcuts = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if choosingShortcuts {
                Text(L10n.text("选择常用预设")).font(.headline)
            } else {
                MetadataPresetScopePicker(onlySelected: $onlySelected)
            }
            Divider()
            if presets.isEmpty {
                Text(L10n.text("暂无预设")).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(presets, id: \.name) { preset in
                            let icons = MetadataMediaIcons(operations: preset.operations)
                            if choosingShortcuts {
                                Toggle(isOn: Binding(get: { shortcuts.contains(preset.name) },
                                    set: { toggleShortcut(preset.name, $0) })) {
                                    row(preset, icons: icons)
                                }.toggleStyle(.checkbox)
                            } else {
                                let scope = MetadataRuleScope(preset.operations, in: images)
                                let reason = !icons.supportsPhotos || !icons.supportsVideo ? icons.label : L10n.text("当前范围没有适用文件")
                                Button { choose(preset) } label: {
                                    row(preset, icons: icons, reason: scope.count == 0 ? reason : nil, skipLabel: scope.skipLabel)
                                }
                                .buttonStyle(.plain)
                                .disabled(scope.count == 0)
                                .accessibilityLabel(Text(preset.name + "、" + icons.label))
                                .accessibilityValue(Text(scope.skipped > 0 ? scope.description : ""))
                                .accessibilityIdentifier("presetChoice-" + preset.name)
                            }
                        }
                    }.padding(.trailing, 4)
                }.frame(height: min(CGFloat(presets.count) * 32, 320))
            }
            Divider()
            HStack {
                Button(L10n.text(choosingShortcuts ? "完成" : "选择常用预设")) { choosingShortcuts.toggle() }
                    .disabled(presets.isEmpty)
                Spacer()
                if !choosingShortcuts { Button(L10n.text("管理预设…"), action: manage) }
            }
        }.padding(12).frame(width: 380)
    }

    private func row(_ preset: MetadataPreset, icons: MetadataMediaIcons, reason: String? = nil, skipLabel: String? = nil) -> some View {
        HStack(spacing: 8) {
            Text(preset.name).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            if let reason { Text(reason).font(.caption).foregroundStyle(.secondary) }
            if let skipLabel { Text(skipLabel).font(.caption).foregroundStyle(.red) }
            icons
        }
        .padding(.horizontal, 4).frame(height: 30).contentShape(Rectangle())
        .help(preset.name + " · " + (reason ?? icons.label))
    }
}
