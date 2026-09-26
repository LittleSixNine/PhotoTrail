import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case spanish = "es"
    case portuguese = "pt-BR"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        case .traditionalChinese: "繁體中文"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .spanish: "Español"
        case .portuguese: "Português do Brasil"
        }
    }
    var defaultMapProvider: String { self == .simplifiedChinese ? "amap" : "apple" }

    static func resolved(preferences: [String]) -> Self {
        let match = Bundle.preferredLocalizations(from: ["en"] + allCases.filter { $0 != .english }.map(\.rawValue),
                                                  forPreferences: preferences.map { $0.hasPrefix("pt") ? "pt-BR" : $0 }).first
        return match.flatMap(Self.init(rawValue:)) ?? .english
    }
}

enum L10n {
    static let languageKey = "PhotoTrailLanguage"

    static var language: AppLanguage {
        UserDefaults.standard.string(forKey: languageKey).flatMap(AppLanguage.init(rawValue:))
            ?? AppLanguage.resolved(preferences: Locale.preferredLanguages)
    }
    static var locale: Locale { Locale(identifier: language.rawValue) }

    static func text(_ key: String, _ arguments: Any...) -> String {
        let format = string(key, language: language)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: locale,
                      arguments: arguments.map { String(describing: $0) as NSString })
    }

    static func string(_ key: String, language: AppLanguage, bundle: Bundle = .main) -> String {
        let path = bundle.path(forResource: language.rawValue, ofType: "lproj")
            ?? bundle.path(forResource: "en", ofType: "lproj")
        let localized = path.flatMap(Bundle.init(path:)) ?? bundle
        return localized.localizedString(forKey: key, value: key, table: nil)
    }

    static func configureDefaults(_ defaults: UserDefaults = .standard) {
        let selected = defaults.string(forKey: languageKey).flatMap(AppLanguage.init(rawValue:))
            ?? AppLanguage.resolved(preferences: Locale.preferredLanguages)
        // Register a fallback; never replace an existing user's chosen map.
        defaults.register(defaults: ["PhotoTrailMapProvider": selected.defaultMapProvider])
        if defaults.string(forKey: languageKey) != nil {
            defaults.set([selected.rawValue], forKey: "AppleLanguages")
        }
    }

    static func select(_ language: AppLanguage, defaults: UserDefaults = .standard) {
        defaults.set(language.rawValue, forKey: languageKey)
        defaults.set([language.rawValue], forKey: "AppleLanguages")
    }

    static var mapScript: String {
        let keys = [
            "写入照片",
            "地点预览",
            "地点预览失败，请检查网络。",
            "当前位置",
            "所选位置校验失败，未修改照片。请检查网络、凭据或服务配额。",
            "搜索地点",
            "收藏",
            "未命名地点",
            "正在校验所选位置…",
            "照片状态已变化，请重新拖动。",
            "红色标记为搜索地点，尚未修改照片。",
            "设备位置",
            "设备位置暂时无法显示，请检查网络。",
            "请先选择可编辑的照片。",
            "部分照片位置显示失败；原照片数据未改变。请检查网络或服务配额。",
            "高德地图已就绪。点选地图或搜索地点。",
            "PhotoTrail 地图",
            "正在加载高德地图…"
        ]
        let payload: [String: Any] = ["language": language.rawValue,
                                     "strings": Dictionary(uniqueKeysWithValues: keys.map { ($0, text($0)) })]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return "window.photoTrailLocalization = \(json);"
    }

    static func mapError(_ code: String) -> String {
        let messages: [String: String] = [
            "service_timeout": "服务响应超时",
            "invalid_coordinate": "坐标无效",
            "coordinate_conversion_failed": "坐标转换失败",
            "invalid_response_coordinate": "返回坐标无效",
            "photo_conversion_failed": "照片坐标转换失败",
            "invalid_track_coordinate": "轨迹坐标无效",
            "amap_conversion_failed": "高德坐标转换失败",
            "incomplete_coordinates": "高德返回的坐标数量不完整",
            "track_conversion_failed": "轨迹转换失败",
            "unknown_region": "无法确认行政区",
            "search_failed": "搜索失败",
            "loader_unavailable": "地图加载器不可用",
            "authentication_failed": "地图鉴权失败",
            "region_lookup_failed": "地区查询失败"
        ]
        if code.hasPrefix("amap_service:") {
            let service = String(code.dropFirst("amap_service:".count))
            if service.range(of: "^[A-Z][A-Z0-9_]{0,79}$", options: .regularExpression) != nil {
                return text("高德服务：%1$@", service)
            }
        }
        return text(messages[code] ?? "轨迹转换失败")
    }

    static var helpURL: URL {
        let base = "https://github.com/LittleSixNine/PhotoTrail"
        return URL(string: language == .simplifiedChinese ? base
            : "\(base)/blob/phototrail/docs/i18n/README.\(language.rawValue).md")!
    }
}

struct AppLanguagePicker: View {
    @AppStorage(L10n.languageKey) private var selected = L10n.language.rawValue

    var body: some View {
        Picker(L10n.text("语言"), selection: $selected) {
            ForEach(AppLanguage.allCases) { language in
                Text(verbatim: language.title).tag(language.rawValue)
            }
        }
        .accessibilityIdentifier("appLanguagePicker")
        .onChange(of: selected) {
            if let language = AppLanguage(rawValue: selected) { L10n.select(language) }
        }
    }
}
