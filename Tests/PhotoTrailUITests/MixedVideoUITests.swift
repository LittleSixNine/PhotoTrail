import AppKit
import XCTest

@MainActor final class MixedVideoUITests: XCTestCase {
    func testMovieImportFilterAndInspector() async throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["PHOTOTRAIL_OFFLINE_TESTS"] = "1"
        app.launchEnvironment["PHOTOTRAIL_TEST_LANGUAGE"] = "en"
        app.launchArguments = ["-LOCALIZATIONPREVIEW", "-PhotoTrailSetupCompleted", "YES", "-NOBACKUP"]
        app.launch()
        defer { app.terminate() }
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "tagged", withExtension: "mov"))
        let dir = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let movie = dir.appendingPathComponent("PhotoTrail-fixture.mov")
        try FileManager.default.copyItem(at: fixture, to: movie)
        let appURL = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("PhotoTrail.app")
        _ = try await NSWorkspace.shared.open([movie], withApplicationAt: appURL, configuration: .init())
        let row = app.outlines.staticTexts.matching(NSPredicate(format: "value == %@", movie.lastPathComponent)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 35))
        row.click()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", "TestCam", "TestCam")).firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["View video GPS track"].firstMatch.exists)
        let photos = app.radioButtons.matching(NSPredicate(format: "label BEGINSWITH 'Photos 0'")).firstMatch
        XCTAssertTrue(photos.exists)
        photos.click()
        XCTAssertTrue(row.waitForNonExistence(timeout: 10))
        let videos = app.radioButtons.matching(NSPredicate(format: "label BEGINSWITH 'Videos 1'")).firstMatch
        videos.click()
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.click()
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Video inspection and media filter"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
