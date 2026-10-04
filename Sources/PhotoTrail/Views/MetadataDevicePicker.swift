import Exiftool
import SwiftUI

struct MetadataDevicePicker: View {
    let tag: MetadataTag
    let make: String?
    let model: String?
    @Binding var value: String
    var compact = false
    var onBrandSelection: ((String) -> Void)?
    @State private var brandID = ""
    @State private var query = ""
    @State private var showingModels = false

    private let catalog = MetadataDeviceCatalog.shared
    private var isModel: Bool { [.model, .exifModel].contains(tag) }
    private var availableBrands: [MetadataDeviceCatalog.Brand] {
        catalog.brands.filter { isModel || $0.models.contains { !$0.isProductNameOnly } }
    }
    private var brand: MetadataDeviceCatalog.Brand? { catalog.brands.first { $0.id == brandID } }
    private var devices: [MetadataDeviceCatalog.Device] {
        var seen = Set<String>()
        return brand?.models.filter {
            (isModel || !$0.isProductNameOnly) && $0.matches(query) && seen.insert($0.name + "\u{1f}" + (isModel ? $0.model : $0.make)).inserted
        } ?? []
    }
    private var selection: MetadataDeviceCatalog.Device? {
        guard !value.isEmpty else { return nil }
        return brand?.models.first { isModel ? $0.model == value || $0.name == value : $0.make == value && $0.model == model }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("设备品牌")).font(.subheadline.weight(.medium))
                    Picker(L10n.text("设备品牌"), selection: Binding(get: { brandID }, set: { selected in
                        brandID = selected; query = ""
                        if !isModel, let make = brand?.models.first(where: { !$0.isProductNameOnly })?.make { value = make }
                        if isModel, let make = brand?.models.first(where: { !$0.isProductNameOnly })?.make {
                            onBrandSelection?(make)
                        }
                    })) {
                        Text(L10n.text("选择品牌")).tag("")
                        ForEach(availableBrands) { brand in Text(brand.name).tag(brand.id) }
                    }.labelsHidden().frame(maxWidth: .infinity)
                        .accessibilityIdentifier("metadataDeviceBrand")
                }.frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("设备型号")).font(.subheadline.weight(.medium))
                    Button { showingModels = true } label: {
                        HStack {
                            Text(isModel && !value.isEmpty ? value : selection?.name ?? L10n.text("选择机型"))
                                .lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.down").font(.caption)
                        }.frame(maxWidth: .infinity)
                    }
                    .disabled(brandID.isEmpty)
                    .accessibilityIdentifier("metadataDeviceModel")
                    .popover(isPresented: $showingModels, arrowEdge: .bottom) { modelList }
                }.frame(maxWidth: .infinity)
            }.controlSize(compact ? .regular : .large)
            if !compact { Text(L10n.text(isModel
                ? "点击商品名称或元数据型号，填入对应名称；名称相同时只显示一项。"
                : "选择机型可填入样本中的制造商名称，只修改当前字段。"))
                .font(.callout).foregroundStyle(.secondary)
            }
        }
        .onAppear { brandID = catalog.brand(matching: value, tag: tag, make: make, model: model) ?? "" }
        .onChange(of: make) {
            if compact { brandID = catalog.brand(matching: "", tag: tag, make: make, model: "") ?? "" }
        }

    }

    private var modelList: some View {
        let devices = devices
        let hasPairs = isModel && devices.contains { !$0.isProductNameOnly && $0.name != $0.model }
        return VStack(alignment: .leading, spacing: 12) {
            Text(brand?.name ?? "").font(.headline)
            TextField(L10n.text("搜索机型或型号编号"), text: $query)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("metadataDeviceSearch")
            if hasPairs {
                HStack {
                    Text(L10n.text("商品名称")).frame(maxWidth: .infinity, alignment: .leading)
                    Text(L10n.text("元数据型号")).frame(maxWidth: .infinity, alignment: .leading)
                }.font(.caption.weight(.medium)).foregroundStyle(.secondary).padding(.horizontal, 8)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(devices) { device in
                        HStack(spacing: 0) {
                            if device.isProductNameOnly {
                                choice(device, label: device.name, productName: true)
                            } else if isModel && device.name != device.model {
                                choice(device, label: device.name, productName: true)
                                Divider()
                                choice(device, label: device.model, productName: false)
                            } else {
                                choice(device, label: isModel ? device.model : device.name + " → " + device.make, productName: false)
                            }
                        }.fixedSize(horizontal: false, vertical: true)
                        Divider()
                    }
                    if devices.isEmpty {
                        Text(L10n.text("没有匹配机型，可直接输入自定义值。"))
                            .foregroundStyle(.secondary).padding(.vertical, 24)
                    }
                }
            }.frame(height: 320)
            Text(L10n.text("同一行对应同一设备；“仅商品名”表示尚未核实元数据型号。"))
                .font(.caption).foregroundStyle(.secondary)
            Text(onBrandSelection != nil
                 ? L10n.text("选择机型将填入已核实的品牌和所选名称；下方仍可自定义。")
                 : L10n.text("选择机型只填入当前字段；下方仍可自定义。型号以样本为准，可能因地区或固件而不同。"))
                .font(.caption).foregroundStyle(.secondary)
        }.padding(18).frame(width: 580).font(.system(size: 15)).controlSize(.large)
    }

    private func choice(_ device: MetadataDeviceCatalog.Device, label: String, productName: Bool) -> some View {
        let candidate = device.selectionValue(for: tag, productName: productName)
        let selected = value == candidate
        return Button {
            if !device.isProductNameOnly { onBrandSelection?(device.make) }
            if let candidate { value = candidate }
            showingModels = false
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark").opacity(selected ? 1 : 0).frame(width: 14)
                Text(label).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                if device.isProductNameOnly {
                    Text(L10n.text("仅商品名")).font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 8).padding(.vertical, 11)
                .background(selected ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityValue(selected ? L10n.text("已选择") : "")
            .help(device.isProductNameOnly ? L10n.text("商品名已核实，元数据型号尚未核实；仅填入商品名。") : candidate ?? "")
    }
}
