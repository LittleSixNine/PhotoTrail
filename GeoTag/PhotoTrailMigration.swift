import Foundation

enum PhotoTrailMigration {
    static func settings() {
        let defaults = UserDefaults.standard
        AMapStyleName.migrateLegacyPreference(in: defaults)
        for (old, new) in [
            ("GeoTagCNMapProvider", "PhotoTrailMapProvider"),
            ("GeoTagCNSetupCompleted", "PhotoTrailSetupCompleted"),
            ("GeoTagCNDetailWidthRatio", "PhotoTrailDetailWidthRatio"),
            ("GeoTagCNFilmstripHeightRatio", "PhotoTrailFilmstripHeightRatio"),
            ("GeoTagCNSatellite", "PhotoTrailSatellite")
        ] where defaults.object(forKey: new) == nil {
            defaults.set(defaults.object(forKey: old), forKey: new)
        }
        if defaults.object(forKey: SettingsPreferences.showAllPhotoLocationsKey) == nil,
           let oldScope = defaults.string(forKey: "PhotoTrailPinScope") {
            defaults.set(oldScope != "selected" && oldScope != "current",
                         forKey: SettingsPreferences.showAllPhotoLocationsKey)
        }
    }

    static func file(at newURL: URL, legacyURL: URL) {
        let files = FileManager.default
        guard !files.fileExists(atPath: newURL.path),
              files.fileExists(atPath: legacyURL.path) else { return }
        do {
            try files.createDirectory(at: newURL.deletingLastPathComponent(),
                                      withIntermediateDirectories: true)
            try files.copyItem(at: legacyURL, to: newURL)
        } catch {
            // Keep reading logic recoverable; the original file is never removed.
        }
    }
}
