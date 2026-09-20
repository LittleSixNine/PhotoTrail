import Foundation
import Testing
@testable import PhotoTrail

@MainActor
struct SoftwareUpdateTests {
    private func response(_ version: String, draft: Bool = false, prerelease: Bool = false) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["tag_name": version, "draft": draft,
                                                    "prerelease": prerelease, "body": "更新说明",
                                                    "html_url": "https://untrusted.example/download"])
    }

    @Test(arguments: [
        ("v0.3.10", "0.3.9", true), ("v0.4.0", "0.3.9.1", true),
        ("v0.3.9", "0.3.9", false), ("v0.3.9", "0.3.9.1", false),
        ("v0.3.9", "0.4.0", false), ("0.3.9.0", "0.3.9", false)
    ])
    func comparesNumericVersions(remote: String, current: String, available: Bool) throws {
        let result = try SoftwareUpdate.availableRelease(from: response(remote), currentVersion: current)
        #expect((result != nil) == available)
    }

    @Test func excludesDraftsAndPrereleases() throws {
        #expect(try SoftwareUpdate.availableRelease(from: response("v9.0", draft: true), currentVersion: "0.3.9") == nil)
        #expect(try SoftwareUpdate.availableRelease(from: response("v9.0", prerelease: true), currentVersion: "0.3.9") == nil)
    }

    @Test(arguments: ["", "v0..4", "v0.4-beta", "../download", "-1.2", "9999999999999999999999999"])
    func rejectsMalformedVersions(version: String) throws {
        let data = try response(version)
        #expect(throws: (any Error).self) {
            try SoftwareUpdate.availableRelease(from: data, currentVersion: "0.3.9")
        }
    }

    @Test func rejectsUnknownCurrentVersionAndInvalidResponse() throws {
        let data = try response("v0.4.0")
        #expect(throws: (any Error).self) {
            try SoftwareUpdate.availableRelease(from: data, currentVersion: "unknown")
        }
        #expect(throws: (any Error).self) {
            try SoftwareUpdate.availableRelease(from: Data("{}".utf8), currentVersion: "0.3.9")
        }
    }

    @Test func downloadPageStaysInOurRepository() throws {
        let release = try #require(try SoftwareUpdate.availableRelease(from: response("v0.4.0"), currentVersion: "0.3.9"))
        #expect(release.pageURL.absoluteString == "https://github.com/LittleSixNine/PhotoTrail/releases/tag/v0.4.0")
    }

    @Test func preferencePersistsAndOfflineChecksNeverStart() throws {
        let name = "PhotoTrail.UpdateTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let updates = SoftwareUpdate(defaults: defaults)
        #expect(updates.automaticChecks)
        updates.setAutomaticChecks(false)
        #expect(!SoftwareUpdate(defaults: defaults).automaticChecks)
        updates.setAutomaticChecks(true)
        #expect(SoftwareUpdate(defaults: defaults).automaticChecks)
        #expect(ProcessInfo.processInfo.environment["PHOTOTRAIL_OFFLINE_TESTS"] == "1")
        updates.start()
        updates.checkForUpdates()
        #expect(!updates.canCheck)
        #expect(!updates.checking)
        #expect(updates.lastCheck == nil)
    }
}
