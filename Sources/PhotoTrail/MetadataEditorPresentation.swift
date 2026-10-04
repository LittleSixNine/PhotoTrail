import Exiftool

extension MetadataTag {
    var isLongText: Bool {
        [.descriptionDefault, .rightsDefault, .exifDescription, .exifCopyright, .exifComment, .iptcCaption].contains(self)
    }

    var flashPresets: [(Int, String)] {
        [(0, "未闪光"), (1, "已闪光"), (9, "强制开启并闪光"), (16, "关闭且未闪光"),
         (24, "自动，未闪光"), (25, "自动，已闪光"), (32, "无闪光灯"), (65, "已闪光，防红眼")]
            .map { ($0.0, "\($0.0) · \(L10n.text($0.1))") }
    }

    var inputExample: String {
        switch self {
        case .exposureTime, .exifExposureTime, .exifShutter: "1/125"
        case .fNumber, .exifFNumber, .exifAperture, .exifMaxAperture: "2.8"
        case .iso, .exifISO: "100"
        case .focalLength, .exifFocalLength, .exifFocal35: "50"
        case .exposureBias, .exifExposureBias: "0"
        case .exifFlash: "0"
        case .iptcCountryCode: "CHN"
        default: displayName
        }
    }

    var editorHint: String {
        if isDeviceIdentity { return L10n.text("可在预设名称上修改，也可直接输入自定义名称。") }
        if self == .creator { return L10n.text("每行一位作者") }
        if isList { return L10n.text("列表值每行一项；逗号属于内容。") }
        if isDate { return L10n.text("可直接编辑完整时间，保留所需的秒、亚秒和时区。") }
        if self == .iptcCountryCode { return L10n.text("使用三个英文字母的国家代码，例如 CHN。") }
        if self == .exifFlash { return L10n.text("输入 EXIF 闪光灯状态代码（0–127），例如 0 表示未闪光。") }
        if numericRange != nil { return L10n.text("输入数值或分数，例如 1/125；单位显示在右侧。") }
        return L10n.text("只修改此字段；其他来源中的同名字段保持原值。")
    }
}
