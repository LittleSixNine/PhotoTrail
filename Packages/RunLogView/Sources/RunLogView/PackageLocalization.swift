import Foundation

enum PackageLocalization {
    static func text(_ key: String) -> String {
        let language = UserDefaults.standard.string(forKey: "PhotoTrailLanguage")
        let path = language.flatMap { Bundle.module.path(forResource: $0, ofType: "lproj") }
        let bundle = path.flatMap(Bundle.init(path:)) ?? Bundle.module
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}
