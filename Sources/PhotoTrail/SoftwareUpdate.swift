import AppKit
import Combine

@MainActor
final class SoftwareUpdate: ObservableObject {
    static let shared = SoftwareUpdate()
    static let preferenceKey = "PhotoTrailAutomaticallyChecksForUpdates"
    nonisolated static let releasesURL = URL(string: "https://github.com/LittleSixNine/PhotoTrail/releases")!

    @Published private(set) var automaticChecks: Bool
    @Published private(set) var checking = false
    @Published private(set) var latestRelease: Release?
    @Published private(set) var lastCheck: Date?
    @Published private(set) var status = ""

    private let defaults: UserDefaults
    private let offline = ProcessInfo.processInfo.environment["PHOTOTRAIL_OFFLINE_TESTS"] == "1"
    private var started = false
    var canCheck: Bool { !checking && !offline }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Self.preferenceKey: true])
        automaticChecks = defaults.bool(forKey: Self.preferenceKey)
        lastCheck = defaults.object(forKey: "PhotoTrailLastUpdateCheck") as? Date
    }

    func start() {
        guard !started, !offline else { return }
        started = true
        if automaticChecks { Task { await check(manual: false) } }
    }

    func setAutomaticChecks(_ enabled: Bool) {
        automaticChecks = enabled
        defaults.set(enabled, forKey: Self.preferenceKey)
    }

    func checkForUpdates() {
        guard canCheck else { return }
        Task { await check(manual: true) }
    }

    func openRelease() {
        NSWorkspace.shared.open(latestRelease?.pageURL ?? Self.releasesURL)
    }

    private func check(manual: Bool) async {
        guard canCheck else { return }
        checking = true
        status = "正在检查更新…"
        defer { checking = false }
        do {
            let url = URL(string: "https://api.github.com/repos/LittleSixNine/PhotoTrail/releases/latest")!
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("PhotoTrail", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
            latestRelease = try Self.availableRelease(from: data, currentVersion: current)
            let checkedAt = Date()
            lastCheck = checkedAt
            defaults.set(checkedAt, forKey: "PhotoTrailLastUpdateCheck")
            if let release = latestRelease {
                status = "发现新版本 \(release.tagName)，可前往 GitHub 下载。"
                if manual || automaticChecks {
                    let notes = release.body.map { String($0.prefix(2_000)) } ?? ""
                    showNotice(title: "PhotoTrail \(release.tagName) 可供下载",
                               message: "下载 DMG 后，将 PhotoTrail 拖入应用程序文件夹完成替换。\n\n" + notes,
                               offersDownload: true)
                }
            } else {
                status = "当前没有可用的新版本。"
                if manual { showNotice(title: "当前没有可用的新版本", message: "当前版本：\(current)") }
            }
        } catch {
            status = "暂时无法检查更新，请稍后重试，也可直接查看 GitHub 发布页。"
            if manual { showNotice(title: "暂时无法检查更新", message: status, offersDownload: true) }
        }
    }

    private func showNotice(title: String, message: String, offersDownload: Bool = false) {
        // Do not interrupt the setup wizard, file dialogs or unsaved-change confirmation.
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              NSApp.modalWindow == nil, window.attachedSheet == nil, !window.isSheet else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: offersDownload ? "前往下载" : "好")
        if offersDownload { alert.addButton(withTitle: "稍后") }
        alert.beginSheetModal(for: window) { [weak self] response in
            if offersDownload && response == .alertFirstButtonReturn { self?.openRelease() }
        }
    }

    struct Release: Decodable, Sendable {
        let tagName: String
        let draft: Bool
        let prerelease: Bool
        let body: String?

        // Never open an arbitrary html_url supplied by the response.
        var pageURL: URL {
            SoftwareUpdate.releasesURL.appendingPathComponent("tag").appendingPathComponent(tagName)
        }
    }

    static func availableRelease(from data: Data, currentVersion: String) throws -> Release? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let release = try decoder.decode(Release.self, from: data)
        guard !release.draft, !release.prerelease else { return nil }
        guard let remote = versionComponents(release.tagName),
              let local = versionComponents(currentVersion) else { throw URLError(.cannotParseResponse) }
        for index in 0..<max(remote.count, local.count) {
            let lhs = index < remote.count ? remote[index] : 0
            let rhs = index < local.count ? local[index] : 0
            if lhs != rhs { return lhs > rhs ? release : nil }
        }
        return nil
    }

    private static func versionComponents(_ version: String) -> [Int]? {
        let value = version.hasPrefix("v") ? String(version.dropFirst()) : version
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count) else { return nil }
        let numbers = parts.compactMap { part -> Int? in
            guard !part.isEmpty, part.allSatisfy({ $0 >= "0" && $0 <= "9" }) else { return nil }
            return Int(part)
        }
        return numbers.count == parts.count ? numbers : nil
    }
}
