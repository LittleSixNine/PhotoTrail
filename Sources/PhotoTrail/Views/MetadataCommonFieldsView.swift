import Exiftool
import ImageData
import SwiftUI
import UDF

struct MetadataCommonFieldsView: View {
    let values: [[MetadataTag: MetadataTagValue]]
    let readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)]?
    let usesSidecar: Bool
    let showField: (MetadataTag) -> Bool
    let openEditor: (MetadataTag) -> Void
    let openDates: () -> Void
    let showAll: () -> Void
    @Environment(Store<PhotoTrailState, PhotoTrailEvent>.self) private var store
    @State private var error: String?
    @State private var keyword = ""
    @State private var otherSources = false
    @State private var calendarTag: MetadataTag?
    @State private var calendarDate = Date()
    @FocusState private var keywordFocused: Bool

    private var makeTag: MetadataTag { usesSidecar ? .make : .exifMake }
    private var modelTag: MetadataTag { usesSidecar ? .model : .exifModel }
    private var dateTags: [MetadataTag] {
        usesSidecar ? [.dateOriginal, .sidecarDate, .dateModified] : [.captureDate, .exifCreateDate, .exifModifyDate]
    }
    private let descriptionTags: [MetadataTag] = [.titleDefault, .descriptionDefault, .creator, .rightsDefault, .subject]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("直接编辑数值；修改暂存后，统一写入照片。"))
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            if descriptionTags.contains(where: showField) {
                section(L10n.text("照片信息")) {
                    ForEach(descriptionTags.filter(showField), id: \.rawValue) { tag in
                        if tag == .subject { keywordRow } else { textRow(tag) }
                    }
                }
            }
            if dateTags.contains(where: showField) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(L10n.text("拍摄时间")).fontWeight(.semibold)
                        Spacer()
                        Button(L10n.text("批量调整…"), action: openDates).buttonStyle(.borderless).disabled(readings == nil)
                    }
                    grouped {
                        ForEach(dateTags.filter(showField), id: \.rawValue) { tag in textRow(tag) }
                    }
                }
            }
            if showField(makeTag) || showField(modelTag) {
                section(L10n.text("设备")) {
                    if showField(modelTag) {
                        MetadataDevicePicker(tag: modelTag, make: raw(makeTag), model: raw(modelTag),
                            value: Binding(get: { raw(modelTag) }, set: { _ = apply(.setText($0), tag: modelTag) }),
                            compact: true, onBrandSelection: { _ = apply(.setText($0), tag: makeTag) })
                            .padding(10).disabled(readings == nil)
                    }
                    if showField(makeTag) { textRow(makeTag) }
                    if showField(modelTag) { textRow(modelTag) }
                }
            }
            let primary = Set(descriptionTags + dateTags + [makeTag, modelTag])
            let others = MetadataTag.allCases.filter { MetadataFieldFilter.commonTags.contains($0.rawValue)
                && !primary.contains($0) && showField($0) && (!usesSidecar || $0.supportsSidecar) }
            if !others.isEmpty {
                DisclosureGroup(L10n.text("其他来源的常用字段"), isExpanded: $otherSources) {
                    Text(L10n.text("只修改此字段；其他来源中的同名字段保持原值。"))
                        .font(.caption).foregroundStyle(.secondary).padding(.vertical, 6)
                    grouped { ForEach(others, id: \.rawValue) { tag in textRow(tag, sourceVisible: true) } }
                }
            }
            HStack {
                Button(L10n.text("查看完整字段与标签来源"), action: showAll).buttonStyle(.borderless)
                Spacer(minLength: 0)
                Text(L10n.text("编辑范围：所选 %1$@ 张照片", values.count)).foregroundStyle(.secondary)
            }.font(.caption)
        }
        .font(.system(size: 13)).controlSize(.regular)
        .padding(.horizontal, 4).padding(.vertical, 8)
        .onChange(of: keywordFocused) { store.send(.textfieldFocusChanged(keywordFocused), undoable: false) }
        .onDisappear {
            if keywordFocused { store.send(.textfieldFocusChanged(false), undoable: false) }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).fontWeight(.semibold)
            grouped(content: content)
        }
    }
    private func grouped<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5) }
    }

    private func textRow(_ tag: MetadataTag, sourceVisible: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tag == .captureDate || tag == .dateOriginal ? L10n.text("拍摄时间") : tag.displayName).fontWeight(.medium)
                    if sourceVisible { Text(tag.rawValue).font(.system(size: 10)).foregroundStyle(.secondary) }
                }.frame(width: 96, alignment: .leading).help(tag.displayName + "\n" + tag.rawValue)
                MetadataQuickTextField(value: raw(tag), placeholder: placeholder(tag), identifier: "metadataQuick." + tag.rawValue,
                    editable: readings != nil, apply: { apply(MetadataQuickEdit.action($0, tag: tag), tag: tag) },
                    editing: { active in
                        if active { store.beginUndoGroup(description: L10n.text("编辑元数据…")) }
                        else { store.endUndoGroup() }
                        store.send(.textfieldFocusChanged(active), undoable: false)
                    }, cancel: { changed in
                        if changed { store.undo() }
                        error = nil
                    })
                    .frame(height: 24)
                    .help(tag.rawValue + "\n" + raw(tag))
                if tag.isDate {
                    Button {
                        calendarDate = (try? MetadataDate(raw(tag)))?.date ?? Date()
                        calendarTag = tag
                    } label: { Image(systemName: "calendar") }
                        .buttonStyle(.borderless).disabled(readings == nil)
                        .accessibilityLabel(L10n.text("选择日期与时间"))
                        .popover(isPresented: Binding(get: { calendarTag == tag }, set: { if !$0 { calendarTag = nil } })) {
                            calendar(tag)
                        }
                }
                fieldMenu(tag)
            }.padding(.horizontal, 10).padding(.vertical, 7)
            Divider().padding(.horizontal, 10)
        }
    }

    private var keywordRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(MetadataTag.subject.displayName).fontWeight(.medium).help(MetadataTag.subject.rawValue)
                .frame(width: 96, alignment: .leading).padding(.top, 4)
            VStack(alignment: .leading, spacing: 6) {
                if case .uniform(.list(let words)) = MetadataSelectionValue.summarize(values, tag: .subject) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), alignment: .leading)], alignment: .leading, spacing: 6) {
                        ForEach(words, id: \.self) { word in
                            HStack(spacing: 4) {
                                Text(word).lineLimit(1).help(word)
                                Button { _ = apply(.removeKeywords([word]), tag: .subject) } label: {
                                    Image(systemName: "xmark").font(.system(size: 9))
                                }.buttonStyle(.borderless).disabled(readings == nil).accessibilityLabel(L10n.text("移除指定关键词") + " " + word)
                            }.padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.08), in: Capsule())
                        }
                    }
                } else if case .mixed = MetadataSelectionValue.summarize(values, tag: .subject) {
                    Text(L10n.text("多个值；添加关键词会保留每张照片原有的关键词。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    TextField(L10n.text("输入关键词后回车"), text: $keyword).textFieldStyle(.roundedBorder)
                        .focused($keywordFocused).onSubmit(addKeyword).accessibilityIdentifier("metadataQuickKeyword")
                    Button(action: addKeyword) { Image(systemName: "plus") }
                        .disabled(keyword.isEmpty || readings == nil).accessibilityLabel(L10n.text("追加关键词"))
                }.disabled(readings == nil)
            }
            fieldMenu(.subject).padding(.top, 4)
        }.padding(10)
    }

    private func addKeyword() {
        if !keyword.isEmpty, apply(.appendKeywords([keyword]), tag: .subject) { keyword = "" }
    }
    private func fieldMenu(_ tag: MetadataTag) -> some View {
        HStack(spacing: 4) {
            if store.imageData.contains(where: { store.selection.contains($0.id) && $0.creatorDraft?.changes[tag] != nil }) {
                Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(.orange).help(L10n.text("待保存"))
            }
            Menu {
                Button(L10n.text("编辑元数据…")) { openEditor(tag) }
                Button(L10n.text("清除字段")) { _ = apply(.remove, tag: tag) }
            } label: { Image(systemName: "ellipsis").frame(width: 16) }
                .menuStyle(.borderlessButton).fixedSize().disabled(readings == nil)
                .help(tag.rawValue).accessibilityLabel(L10n.text("编辑元数据…") + " · " + tag.displayName)
        }
    }
    private func calendar(_ tag: MetadataTag) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tag.displayName).font(.headline)
            DatePicker(L10n.text("选择日期与时间"), selection: $calendarDate).datePickerStyle(.field)
                .environment(\.timeZone, (try? MetadataDate(raw(tag)))?.displayTimeZone ?? TimeZone(secondsFromGMT: 0)!)
            Text(L10n.text("可直接编辑完整时间，保留所需的秒、亚秒和时区。"))
                .font(.caption).foregroundStyle(.secondary)
            Button(L10n.text("应用")) {
                let original = try? MetadataDate(raw(tag))
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
                let text = original.flatMap { try? $0.shifting(seconds: Int(calendarDate.timeIntervalSince($0.date).rounded())).text }
                    ?? formatter.string(from: calendarDate)
                if apply(.setText(text), tag: tag) { calendarTag = nil }
            }.buttonStyle(.borderedProminent)
        }.padding(16)
    }
    private func raw(_ tag: MetadataTag) -> String {
        guard case .uniform(let value) = MetadataSelectionValue.summarize(values, tag: tag) else { return "" }
        switch value { case .text(let text): return text; case .list(let words): return words.joined(separator: "\n") }
    }
    private func placeholder(_ tag: MetadataTag) -> String {
        if case .mixed = MetadataSelectionValue.summarize(values, tag: tag) { return L10n.text("多个值") }
        return L10n.text("未填写")
    }
    @discardableResult private func apply(_ action: MetadataFieldEditAction, tag: MetadataTag) -> Bool {
        guard let readings else { return false }
        do {
            try MetadataQuickEdit.apply(action, tag: tag, readings: readings, store: store)
            error = nil
            return true
        } catch {
            self.error = L10n.text("无法暂存：请检查输入或重新读取元数据。")
            return false
        }
    }
}
