import Foundation
import Testing
@testable import PhotoTrail

struct LocalizationTests {
    @Test func languageNegotiationAndMapDefaults() {
        #expect(AppLanguage.resolved(preferences: ["zh-CN"]) == .simplifiedChinese)
        #expect(AppLanguage.resolved(preferences: ["zh-TW"]) == .traditionalChinese)
        #expect(AppLanguage.resolved(preferences: ["zh-HK"]) == .traditionalChinese)
        #expect(AppLanguage.resolved(preferences: ["en-GB"]) == .english)
        #expect(AppLanguage.resolved(preferences: ["pt-PT"]) == .portuguese)
        #expect(AppLanguage.resolved(preferences: ["de", "ja"]) == .japanese)
        #expect(AppLanguage.resolved(preferences: ["de"]) == .english)
        for language in AppLanguage.allCases {
            #expect(language.defaultMapProvider == (language == .simplifiedChinese ? "amap" : "apple"))
        }
    }

    @Test func defaultsPreserveExistingMapAndCameraTimeZone() throws {
        let name = "PhotoTrail.LocalizationTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        for language in AppLanguage.allCases {
            defaults.removePersistentDomain(forName: name)
            L10n.select(language, defaults: defaults)
            L10n.configureDefaults(defaults)
            #expect(defaults.string(forKey: "PhotoTrailMapProvider") == language.defaultMapProvider)
            defaults.set("amap", forKey: "PhotoTrailMapProvider")
            defaults.set("Asia/Shanghai", forKey: SettingsPreferences.cameraTimeZoneKey)
            L10n.select(.japanese, defaults: defaults)
            L10n.configureDefaults(defaults)
            #expect(defaults.string(forKey: "PhotoTrailMapProvider") == "amap")
            #expect(defaults.string(forKey: SettingsPreferences.cameraTimeZoneKey) == "Asia/Shanghai")
        }
    }

    @Test func everyLanguageIsPackagedAndFormatsWithoutChangingArguments() throws {
        for language in AppLanguage.allCases {
            let path = try #require(Bundle.main.path(forResource: language.rawValue, ofType: "lproj"))
            let bundle = try #require(Bundle(path: path))
            let text = L10n.string("选择语言", language: language)
            #expect(!text.isEmpty)
            if language != .simplifiedChinese { #expect(text != "选择语言") }
            let permissions = bundle.localizedString(forKey: "NSPhotoLibraryUsageDescription",
                                                       value: nil, table: "InfoPlist")
            #expect(permissions != "NSPhotoLibraryUsageDescription")
            let format = L10n.string("导出失败：%1$@", language: language)
            let name = "旅の写真 100% {1} \"été\".jpg"
            let message = String(format: format, name as NSString)
            #expect(message.contains(name))
            #expect(!message.contains("%1$@"))
        }
    }

    @Test func mapErrorsDoNotExposeUntrustedServiceText() {
        #expect(L10n.mapError("amap_service:INVALID_USER_KEY").contains("INVALID_USER_KEY"))
        #expect(!L10n.mapError("amap_service:https://example.invalid/?key=secret").contains("secret"))
        #expect(!L10n.mapError("unexpected private response").contains("private"))
    }
}
