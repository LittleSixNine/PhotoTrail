import ImageData
import SwiftUI
import UDF

struct MetadataCreatorEditorSelection: Identifiable {
    let id = UUID()
    let readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)]
}

struct MetadataCreatorEditorView: View {
    let readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)]

    @Environment(Store<PhotoTrailState, PhotoTrailEvent>.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .set
    @State private var authors = ""
    @State private var preview: MetadataCreatorEditPlan?
    @State private var error: String?

    private enum Mode: Hashable, CaseIterable {
        case set, fillMissing, remove

        var label: String {
            switch self {
            case .set: L10n.text("设为")
            case .fillMissing: L10n.text("仅补空值")
            case .remove: L10n.text("清除作者")
            }
        }
    }

    private var action: MetadataCreatorEditAction {
        let names = authors.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        switch mode {
        case .set: return .set(names)
        case .fillMissing: return .fillMissing(names)
        case .remove: return .remove
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("编辑作者…")).font(.title2.bold())
            Text(L10n.text("已选择 %1$@ 张照片", readings.count))
                .font(.subheadline).foregroundStyle(.secondary)
            Picker(L10n.text("作者操作"), selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }.pickerStyle(.segmented)
            if mode != .remove {
                TextField(L10n.text("每行一位作者"), text: $authors, axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Button(L10n.text("预览")) { makePreview() }
                Spacer()
                Button(L10n.text("取消")) { dismiss() }
                Button(L10n.text("加入待保存修改")) { applyPreview() }
                    .disabled(preview?.items.contains(where: { $0.change != nil }) != true)
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            if let preview {
                let count = preview.items.filter { $0.change != nil }.count
                Text(L10n.text("预览：%1$@ 张将修改", count))
                    .font(.headline)
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(preview.items, id: \.id) { item in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.imageURL.lastPathComponent).fontWeight(.medium)
                                Text("\(display(item.original)) → \(display(item))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Divider()
                        }
                    }
                }.frame(maxHeight: 260)
            }
        }
        .padding(20)
        .frame(width: 450)
        .onChange(of: mode) { preview = nil; error = nil }
        .onChange(of: authors) { preview = nil; error = nil }
    }

    private func makePreview() {
        do {
            preview = try MetadataCreatorEditPlan.prepare(readings, action: action)
            error = nil
        } catch {
            preview = nil
            self.error = L10n.text("无法预览作者修改；请检查输入并重新读取元数据。")
        }
    }

    private func applyPreview() {
        guard let preview else { return }
        do {
            let current = try MetadataCreatorEditPlan.prepare(readings, action: action)
            guard current.items == preview.items, !store.saveInProgress else {
                self.preview = nil
                error = L10n.text("来源文件已变化；请重新读取元数据。")
                return
            }
            store.send(.creatorDraftApplied(current.items), description: L10n.text("编辑作者…"))
            dismiss()
        } catch {
            self.preview = nil
            self.error = L10n.text("来源文件已变化；请重新读取元数据。")
        }
    }

    private func display(_ value: MetadataCreatorValue) -> String {
        switch value {
        case .absent: L10n.text("未填写")
        case .names(let names): names.joined(separator: ", ")
        }
    }

    private func display(_ item: MetadataCreatorEditPlan.Item) -> String {
        switch item.change {
        case nil: display(item.original)
        case .remove: L10n.text("未填写")
        case .set(.list(let names)): names.joined(separator: ", ")
        case .set(.text(let name)): name
        }
    }
}
