import Exiftool
import ImageData
import SwiftUI
import UDF

private struct MetadataInspectionRequest: Sendable {
    let id: ImageData.ID
    let url: URL?
}

private enum MetadataInspectionRead: Sendable {
    case values([MetadataTag: MetadataTagValue])
    case unavailable
}

struct MetadataListInspectorView: View {
    @Environment(Store<PhotoTrailState, PhotoTrailEvent>.self) private var store
    @State private var results: [ImageData.ID: MetadataInspectionRead] = [:]
    @State private var loading = false
    @State private var loadID = UUID()
    @State private var revision = 0

    private struct LoadKey: Hashable {
        let ids: [ImageData.ID]
        let urls: [URL?]
        let revision: Int
    }

    private var selected: [ImageData] {
        store.imageData.filter { store.selection.contains($0.id) }
    }

    private var loadKey: LoadKey {
        LoadKey(ids: selected.map(\.id),
                urls: selected.map(\.metadataInspectionURL),
                revision: revision)
    }

    private var completeValues: [[MetadataTag: MetadataTagValue]]? {
        let values = selected.compactMap { image -> [MetadataTag: MetadataTagValue]? in
            guard case .values(let tags) = results[image.id] else { return nil }
            return tags
        }
        return values.count == selected.count ? values : nil
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
                    if loading {
                        ProgressView()
                    } else if let values = completeValues {
                        VStack(alignment: .leading, spacing: 12) {
                            field(L10n.text("作者"), tag: .creator, values: values)
                            Divider()
                            field(L10n.text("说明"), tag: .descriptionDefault, values: values)
                            Divider()
                            field(L10n.text("关键词"), tag: .subject, values: values)
                        }
                    } else {
                        Text(L10n.text("部分照片无法读取描述元数据；暂不汇总字段。"))
                            .foregroundStyle(.secondary)
                    }
                    Button(L10n.text("重新读取元数据")) { revision += 1 }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .task(id: loadKey) {
            let requests = selected.map {
                MetadataInspectionRequest(id: $0.id, url: $0.metadataInspectionURL)
            }
            let token = UUID()
            loadID = token
            results = [:]
            guard !requests.isEmpty else { loading = false; return }
            loading = true

            let worker = Task.detached(priority: .userInitiated) {
                var loaded: [ImageData.ID: MetadataInspectionRead] = [:]
                for request in requests {
                    guard !Task.isCancelled else { break }
                    guard let url = request.url else {
                        loaded[request.id] = .unavailable
                        continue
                    }
                    do {
                        let tags = try Exiftool.helper.metadataTags(
                            [.creator, .descriptionDefault, .subject], from: url)
                        loaded[request.id] = .values(tags)
                    } catch {
                        loaded[request.id] = .unavailable
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
            results = loaded
            loading = false
        }
    }

    private func field(_ label: String, tag: MetadataTag,
                       values: [[MetadataTag: MetadataTagValue]]) -> some View {
        let summary = MetadataSelectionValue.summarize(values, tag: tag)
        return LabeledContent(label) {
            VStack(alignment: .trailing, spacing: 3) {
                Text(display(summary))
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
                Text(tag.rawValue).font(.caption2).foregroundStyle(.secondary)
            }
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
