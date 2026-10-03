import Exiftool
import SwiftUI

struct MetadataDevicePicker: View {
    let tag: MetadataTag
    let make: String?
    let model: String?
    @Binding var value: String
    @State private var brandID = ""
    @State private var query = ""

    private let catalog = MetadataDeviceCatalog.shared

    private var devices: [MetadataDeviceCatalog.Device] {
        return catalog.brands.first { $0.id == brandID }?.models.filter {
            $0.matches(query)
        } ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(L10n.text("设备品牌"), selection: $brandID) {
                Text(L10n.text("选择品牌")).tag("")
                ForEach(catalog.brands) { brand in Text(brand.name).tag(brand.id) }
            }
            .accessibilityIdentifier("metadataDeviceBrand")
            HStack {
                TextField(L10n.text("搜索机型或型号编号"), text: $query)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("metadataDeviceSearch")
                Menu(L10n.text("选择机型")) {
                    ForEach(devices) { device in
                        Button(device.name == device.value(for: tag) ? device.name : "\(device.name) · \(device.value(for: tag) ?? "")") {
                            if let selectedValue = device.value(for: tag) { value = selectedValue }
                        }
                    }
                    if devices.isEmpty { Text(L10n.text("没有匹配机型，可直接输入自定义值。")) }
                }
                .disabled(brandID.isEmpty)
                .accessibilityIdentifier("metadataDeviceModel")
            }
            Text(L10n.text("选择机型只填入当前字段；下方仍可自定义。型号以样本为准，可能因地区或固件而不同。"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { brandID = catalog.brand(matching: value, tag: tag, make: make, model: model) ?? "" }
        .onChange(of: brandID) { query = "" }
    }
}
