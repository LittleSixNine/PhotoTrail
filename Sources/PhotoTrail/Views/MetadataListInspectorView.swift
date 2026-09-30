import Exiftool
import ImageData
import SwiftUI
import UDF

private struct MetadataInspectionRequest: Sendable {
    let id: ImageData.ID
    let url: URL?
    let creatorImageURL: URL?
}

private enum MetadataInspectionRead: Sendable {
    case values(MetadataInspectionSnapshot, [LegacyCreatorTag: [String]]?)
    case unsupported
    case failed
}

struct MetadataListInspectorView: View {
    @Environment(Store<PhotoTrailState, PhotoTrailEvent>.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var results: [ImageData.ID: MetadataInspectionRead] = [:]
    @State private var observedVersions: [MetadataInspectionFileVersion] = []
    @State private var loading = false
    @State private var loadID = UUID()
    @State private var revision = 0
    @State private var fieldQuery = ""

    private let fields: [MetadataTag] = [.creator, .descriptionDefault, .subject]

    private struct LoadKey: Hashable {
        let ids: [ImageData.ID]
        let urls: [URL?]
        let creatorImageURLs: [URL?]
        let revision: Int
    }

    private var selected: [ImageData] {
        store.imageData.filter { store.selection.contains($0.id) }
    }

    private var loadKey: LoadKey {
        LoadKey(ids: selected.map(\.id),
                urls: selected.map(\.metadataInspectionURL),
                creatorImageURLs: selected.map(\.metadataCreatorImageURL),
                revision: revision)
    }

    private var selectedVersions: [MetadataInspectionFileVersion] {
        selected.flatMap(\.metadataInspectionVersions)
    }

    private func reloadIfFilesChanged() {
        guard selectedVersions != observedVersions else { return }
        revision += 1
    }

    private var completeValues: [[MetadataTag: MetadataTagValue]]? {
        let values = selected.compactMap { image -> [MetadataTag: MetadataTagValue]? in
            guard case .values(let snapshot, _) = results[image.id] else { return nil }
            return snapshot.values
        }
        return values.count == selected.count ? values : nil
    }

    private var completeLegacyValues: [[LegacyCreatorTag: [String]]]? {
        let values = selected.compactMap { image -> [LegacyCreatorTag: [String]]? in
            guard case .values(_, let legacy) = results[image.id] else { return nil }
            return legacy
        }
        return values.count == selected.count ? values : nil
    }

    private var visibleFields: [MetadataTag] {
        guard !fieldQuery.isEmpty else { return fields }
        return fields.filter {
            $0.rawValue.localizedCaseInsensitiveContains(fieldQuery)
                || label(for: $0).localizedCaseInsensitiveContains(fieldQuery)
                || ($0 == .creator && [LegacyCreatorTag.exifArtist, .iptcByline]
                    .contains { $0.rawValue.localizedCaseInsensitiveContains(fieldQuery) })
                || ($0 == .creator && "EXIF:Artist".localizedCaseInsensitiveContains(fieldQuery))
        }
    }

    private func label(for tag: MetadataTag) -> String {
        switch tag {
        case .creator: L10n.text("作者")
        case .descriptionDefault: L10n.text("说明")
        case .subject: L10n.text("关键词")
        }
    }

    private var sourceDescription: String {
        if selected.count == 1, let image = selected.first {
            switch image.metadata.source {
            case .image(let url):
                return L10n.text("图像文件：%1$@", url.lastPathComponent)
            case .xmp:
                return L10n.text("XMP 附属文件：%1$@",
                                 image.metadataInspectionURL?.lastPathComponent ?? image.name)
            case .photos:
                return L10n.text("照片图库项目暂不支持读取这些描述字段。")
            case .copy:
                return L10n.text("此条目没有可读取的本地文件。")
            }
        }
        let imageCount = selected.filter {
            if case .image = $0.metadata.source { return true }
            return false
        }.count
        let sidecarCount = selected.filter {
            if case .xmp = $0.metadata.source { return true }
            return false
        }.count
        return L10n.text("读取来源：图像 %1$@ 张，XMP %2$@ 张，非本地 %3$@ 张。",
                         imageCount, sidecarCount, selected.count - imageCount - sidecarCount)
    }

    private var readFailureCount: Int {
        selected.filter {
            guard let result = results[$0.id] else { return false }
            if case .failed = result { return true }
            return false
        }.count
    }

    private var legacyReadFailureCount: Int {
        selected.filter {
            guard case .values(_, let legacy) = results[$0.id] else { return false }
            return legacy == nil
        }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.text("元数据（只读）")).font(.headline)
                if selected.isEmpty {
                    Text(L10n.text("Please select an image"))
                        .foregroundStyle(.secondary)
                } else {
                    Text(L10n.text("已选择 %1$@ 张照片", selected.count))
                        .foregroundStyle(.secondary)
                    Text(sourceDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(L10n.text("搜索元数据字段"), text: $fieldQuery)
                    if loading {
                        ProgressView()
                    } else if let values = completeValues {
                        if visibleFields.isEmpty {
                            Text(L10n.text("没有匹配的字段"))
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(visibleFields, id: \.rawValue) { tag in
                                    field(label(for: tag), tag: tag, values: values)
                                    if tag != visibleFields.last { Divider() }
                                }
                            }
                        }
                    } else {
                        Text(L10n.text("部分照片无法读取描述元数据；暂不汇总字段。"))
                            .foregroundStyle(.secondary)
                        if readFailureCount > 0 {
                            Text(L10n.text("读取失败：%1$@ 张；请检查来源文件。", readFailureCount))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button(L10n.text("重新读取元数据")) { revision += 1 }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            if scenePhase == .active { reloadIfFilesChanged() }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active { reloadIfFilesChanged() }
        }
        .task(id: loadKey) {
            let requests = selected.map {
                MetadataInspectionRequest(id: $0.id, url: $0.metadataInspectionURL,
                                          creatorImageURL: $0.metadataCreatorImageURL)
            }
            let versions = selectedVersions
            observedVersions = versions
            let token = UUID()
            loadID = token
            results = [:]
            guard !requests.isEmpty else { loading = false; return }
            loading = true

            let worker = Task.detached(priority: .userInitiated) {
                var loaded: [ImageData.ID: MetadataInspectionRead] = [:]
                for request in requests {
                    guard !Task.isCancelled else { break }
                    guard let url = request.url,
                          let imageURL = request.creatorImageURL else {
                        loaded[request.id] = .unsupported
                        continue
                    }
                    do {
                        let snapshot = try MetadataInspectionSnapshot.read(
                            [.creator, .descriptionDefault, .subject], from: url)
                        let legacy = try? Exiftool.helper.legacyCreatorTags(from: imageURL)
                        loaded[request.id] = .values(snapshot, legacy)
                    } catch {
                        loaded[request.id] = .failed
                    }
                }
                return loaded
            }
            let loaded = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled, loadID == token else { return }
            if selectedVersions != versions {
                revision += 1
                return
            }
            results = loaded
            loading = false
        }
    }

    private func field(_ label: String, tag: MetadataTag,
                       values: [[MetadataTag: MetadataTagValue]]) -> some View {
        let summary = MetadataSelectionValue.summarize(values, tag: tag)
        return VStack(alignment: .leading, spacing: 8) {
            LabeledContent(label) {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(display(summary))
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                    Text(tag.rawValue).font(.caption2).foregroundStyle(.secondary)
                }
            }
            if tag == .creator { creatorCompatibility(values: values) }
        }
    }

    @ViewBuilder
    private func creatorCompatibility(values: [[MetadataTag: MetadataTagValue]]) -> some View {
        if let legacy = completeLegacyValues {
            ForEach([LegacyCreatorTag.exifArtist, .iptcByline], id: \.rawValue) { tag in
                LabeledContent(tag.rawValue) {
                    Text(display(MetadataSelectionValue.summarize(legacy, tag: tag)))
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
            }
            let conflicts = zip(values, legacy).filter {
                MetadataSelectionValue.creatorSourcesConflict(xmp: $0[.creator], legacy: $1)
            }.count
            if conflicts > 0 {
                Text(L10n.text("作者来源冲突：%1$@ 张。", conflicts))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } else if legacyReadFailureCount > 0 {
            Text(L10n.text("兼容作者来源读取失败：%1$@ 张。", legacyReadFailureCount))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func display(_ summary: MetadataSelectionValue) -> String {
        switch summary {
        case .unselected: "—"
        case .absent: L10n.text("未填写")
        case .uniform(.text(let value)): value
        case .uniform(.list(let values)): values.joined(separator: ", ")
        case .mixed(let present, let total):
            L10n.text("多个值（%1$@/%2$@ 张有值）", present, total)
        }
    }
}
