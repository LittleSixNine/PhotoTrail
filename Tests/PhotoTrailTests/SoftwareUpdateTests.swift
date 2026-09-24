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

    @Test func automaticDownloadAcceptsOnlyTheExpectedGitHubAsset() throws {
        let digest = String(repeating: "a", count: 64)
        let json = try JSONSerialization.data(withJSONObject: [
            "tag_name": "v0.4.0", "draft": false, "prerelease": false,
            "assets": [[
                "name": "PhotoTrail-0.4.0-macOS.dmg", "size": 1024,
                "digest": "sha256:\(digest)",
                "browser_download_url": "https://github.com/LittleSixNine/PhotoTrail/releases/download/v0.4.0/PhotoTrail-0.4.0-macOS.dmg"
            ]]
        ])
        let release = try #require(try SoftwareUpdate.availableRelease(from: json, currentVersion: "0.3.9"))
        let asset = try #require(release.assets?.first)
        #expect(SoftwareUpdate.dmgFileName(tagName: release.tagName) == "PhotoTrail-0.4.0-macOS.dmg")
        #expect(SoftwareUpdate.validatedAssetURL(asset, release: release,
                                                 fileName: "PhotoTrail-0.4.0-macOS.dmg")?.host == "github.com")

        let untrusted = SoftwareUpdate.ReleaseAsset(name: asset.name, size: asset.size, digest: asset.digest,
                                                    browserDownloadUrl: "https://example.com/PhotoTrail.dmg")
        #expect(SoftwareUpdate.validatedAssetURL(untrusted, release: release, fileName: asset.name) == nil)
        #expect(SoftwareUpdate.validatedAssetURL(asset, release: release, fileName: "other.dmg") == nil)
    }

    @Test func verifiesPublishedChecksums() throws {
        let digest = String(repeating: "b", count: 64)
        let manifest = Data("\(digest)  PhotoTrail-0.4.0-macOS.dmg\n\(String(repeating: "c", count: 64))  other.dmg\n".utf8)
        #expect(SoftwareUpdate.checksum(in: manifest, for: "PhotoTrail-0.4.0-macOS.dmg") == digest)
        #expect(SoftwareUpdate.checksum(in: manifest, for: "missing.dmg") == nil)
        #expect(SoftwareUpdate.normalizedSHA256("sha256:\(digest)") == digest)
        #expect(SoftwareUpdate.normalizedSHA256("bad") == nil)
    }

    @Test func preferencePersistsAndOfflineChecksNeverStart() throws {
        let name = "PhotoTrail.UpdateTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let updates = SoftwareUpdate(defaults: defaults)
        #expect(updates.automaticChecks)
        #expect(!updates.automaticDownloads)
        updates.setAutomaticChecks(false)
        #expect(!SoftwareUpdate(defaults: defaults).automaticChecks)
        updates.setAutomaticChecks(true)
        #expect(SoftwareUpdate(defaults: defaults).automaticChecks)
        updates.setAutomaticDownloads(true)
        #expect(SoftwareUpdate(defaults: defaults).automaticDownloads)
        updates.setAutomaticDownloads(false)
        #expect(!SoftwareUpdate(defaults: defaults).automaticDownloads)
        #expect(ProcessInfo.processInfo.environment["PHOTOTRAIL_OFFLINE_TESTS"] == "1")
        updates.start()
        updates.checkForUpdates()
        #expect(!updates.canCheck)
        #expect(!updates.checking)
        #expect(updates.lastCheck == nil)
    }
}
