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
        let photo = dir.appendingPathComponent("PhotoTrail-fixture.jpg")
        let image = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
            NSColor.blue.setFill()
            rect.fill()
            return true
        }
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        try XCTUnwrap(bitmap.representation(using: .jpeg, properties: [:])).write(to: photo)
        let movie = dir.appendingPathComponent("PhotoTrail-fixture.mov")
        try FileManager.default.copyItem(at: fixture, to: movie)
        let appURL = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("PhotoTrail.app")
        _ = try await NSWorkspace.shared.open([photo, movie], withApplicationAt: appURL, configuration: .init())
        let row = app.outlines.staticTexts.matching(NSPredicate(format: "value == %@", movie.lastPathComponent)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 35))
        row.click()
        let search = app.textFields["metadataFieldSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        attachWindow(app, "Video fields")
        search.click()
        search.typeText("TestCam")
        let model = app.staticTexts.matching(NSPredicate(format: "value == %@ OR label == %@", "TestCam", "TestCam")).firstMatch
        XCTAssertTrue(model.waitForExistence(timeout: 10))
        search.typeKey("a", modifierFlags: .command)
        search.typeKey(.delete, modifierFlags: [])
        let track = app.buttons["View video GPS track"].firstMatch
        XCTAssertTrue(track.waitForExistence(timeout: 10))
        let photos = app.radioButtons.matching(NSPredicate(format: "label BEGINSWITH 'Photos 1'")).firstMatch
        photos.click()
        XCTAssertTrue(row.waitForNonExistence(timeout: 10))
        let photoRow = app.outlines.staticTexts.matching(NSPredicate(format: "value == %@", photo.lastPathComponent)).firstMatch
        photoRow.click()
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        XCTAssertFalse(track.exists)
        attachWindow(app, "Photo fields")
        let videos = app.radioButtons.matching(NSPredicate(format: "label BEGINSWITH 'Videos 1'")).firstMatch
        videos.click()
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.click()
        XCTAssertTrue(track.waitForExistence(timeout: 10))
    }

    private func attachWindow(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.windows["main"].screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
