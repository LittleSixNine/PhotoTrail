import AppKit
import XCTest

@MainActor
final class LocalizationUITests: XCTestCase {
    func testSevenLanguagesAndOnboardingMapDefaults() async throws {
        continueAfterFailure = false
        let appURL = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("PhotoTrail.app")
        let languages = [
            ("zh-Hans", "简体中文", "选择语言", "高德"),
            ("en", "English", "Choose Your Language", "Apple"),
            ("zh-Hant", "繁體中文", "選擇語言", "蘋果"),
            ("ja", "日本語", "言語を選択", "Apple"),
            ("ko", "한국어", "언어 선택", "Apple"),
            ("es", "Español", "Elige tu idioma", "Apple"),
            ("pt-BR", "Português do Brasil", "Escolha seu idioma", "Apple")
        ]
        for (code, name, title, provider) in languages {
            let app = XCUIApplication()
            app.launchEnvironment["PHOTOTRAIL_OFFLINE_TESTS"] = "1"
            app.launchEnvironment["PHOTOTRAIL_TEST_LANGUAGE"] = "en"
            app.launchArguments = ["-UIINIT", "-NOBACKUP", "-LOCALIZATIONPREVIEW",
                                   "-PhotoTrailSetupCompleted", "NO"]
            app.launch()
            // XCTest may start the process without sending the window reopen event on macOS.
            _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
            let picker = app.popUpButtons["appLanguagePicker"]
            XCTAssertTrue(picker.waitForExistence(timeout: 15), app.debugDescription)
            picker.click()
            app.menuItems[name].click()
            let heading = app.staticTexts.matching(NSPredicate(
                format: "value CONTAINS %@ OR label CONTAINS %@", title, title)).firstMatch
            XCTAssertTrue(heading.waitForExistence(timeout: 5), app.debugDescription)
            attach(app.windows.firstMatch.screenshot(), name: "setup_\(code)")
            app.buttons["setupNext"].click()
            XCTAssertTrue(app.buttons["setupNext"].isEnabled)
            app.buttons["setupNext"].click()
            let map = app.popUpButtons["setupMapPicker"]
            XCTAssertTrue(map.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(String(describing: map.value).contains(provider), "\(code): \(String(describing: map.value))")
            attach(app.windows.firstMatch.screenshot(), name: "map_\(code)")
            // A manual map choice survives navigation through the remaining guide.
            if code == "ja" {
                map.click()
                app.menuItems.matching(NSPredicate(format: "title BEGINSWITH %@", "AMap")).firstMatch.click()
                app.buttons["setupNext"].click()
                app.buttons["setupBack"].click()
                XCTAssertTrue(String(describing: map.value).contains("AMap"))
            }
            app.buttons["setupNext"].click()
            attach(app.windows.firstMatch.screenshot(), name: "ready_\(code)")
            app.buttons["setupFinish"].click()
            app.typeKey(",", modifierFlags: .command)
            XCTAssertTrue(picker.waitForExistence(timeout: 5), app.debugDescription)
            attach(app.windows.firstMatch.screenshot(), name: "settings_\(code)")
            app.terminate()
        }
    }

    private func attach(_ screenshot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
