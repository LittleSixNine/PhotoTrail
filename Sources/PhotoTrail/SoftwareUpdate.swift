import AppKit
import Combine
import CryptoKit
import Foundation

@MainActor
final class SoftwareUpdate: ObservableObject {
    static let shared = SoftwareUpdate()
    static let preferenceKey = "PhotoTrailAutomaticallyChecksForUpdates"
    static let automaticDownloadsPreferenceKey = "PhotoTrailAutomaticallyDownloadsUpdates"
    static let downloadedVersionKey = "PhotoTrailDownloadedUpdateVersion"
    static let downloadedDigestKey = "PhotoTrailDownloadedUpdateSHA256"
    nonisolated static let releasesURL = URL(string: "https://github.com/LittleSixNine/PhotoTrail/releases")!

    @Published private(set) var automaticChecks: Bool
    @Published private(set) var automaticDownloads: Bool
    @Published private(set) var checking = false
    @Published private(set) var downloading = false
    @Published private(set) var latestRelease: Release?
    @Published private(set) var downloadedVersion: String?
    @Published private(set) var lastCheck: Date?
    @Published private(set) var status = ""

    private let defaults: UserDefaults
    private let updatesDirectory: URL
    private let offline = ProcessInfo.processInfo.environment["PHOTOTRAIL_OFFLINE_TESTS"] == "1"
    private var downloadedDigest: String?
    private var downloadTask: Task<Void, Never>?
    private var started = false
    private var showedDownloadedNotice = false

    var canCheck: Bool { !checking && !downloading && !offline }

    init(defaults: UserDefaults = .standard, updatesDirectory: URL? = nil) {
        self.defaults = defaults
        self.updatesDirectory = updatesDirectory ?? URL.applicationSupportDirectory
            .appending(path: "PhotoTrail/Updates", directoryHint: .isDirectory)
        defaults.register(defaults: [Self.preferenceKey: true,
                                     Self.automaticDownloadsPreferenceKey: false])
        automaticChecks = defaults.bool(forKey: Self.preferenceKey)
        automaticDownloads = defaults.bool(forKey: Self.automaticDownloadsPreferenceKey)
        lastCheck = defaults.object(forKey: "PhotoTrailLastUpdateCheck") as? Date
        restoreDownloadedUpdate()
    }

    func start() {
        guard !started, !offline else { return }
        started = true
        if automaticChecks { Task { await check(manual: false) } }
    }

    func presentDownloadedUpdateIfNeeded() {
        guard !showedDownloadedNotice, let version = downloadedVersion else { return }
        let message = "新版已下载。打开磁盘映像后，请先退出 PhotoTrail，再将 PhotoTrail 拖到“应用程序”文件夹中完成更新。"
        guard showNotice(title: "PhotoTrail \(version) 已下载", message: message,
                         primaryTitle: "打开安装镜像", primaryAction: { [weak self] in
                             self?.openDownloadedUpdate()
                         }) else { return }
        showedDownloadedNotice = true
    }

    func setAutomaticChecks(_ enabled: Bool) {
        automaticChecks = enabled
        defaults.set(enabled, forKey: Self.preferenceKey)
    }

    func setAutomaticDownloads(_ enabled: Bool) {
        automaticDownloads = enabled
        defaults.set(enabled, forKey: Self.automaticDownloadsPreferenceKey)
        if enabled, let latestRelease {
            startDownload(latestRelease)
        } else if !enabled, downloading {
            downloadTask?.cancel()
        }
    }

    func checkForUpdates() {
        guard canCheck else { return }
        Task { await check(manual: true) }
    }

    func openRelease() {
        NSWorkspace.shared.open(latestRelease?.pageURL ?? Self.releasesURL)
    }

    func openDownloadedUpdate() {
        guard let version = downloadedVersion,
              let downloadedDigest,
              let fileURL = Self.downloadURL(directory: updatesDirectory, tagName: version) else {
            status = "没有找到已下载的安装镜像，请重新检查更新。"
            return
        }
        Task {
            do {
                guard try Self.sha256(fileAt: fileURL) == downloadedDigest else {
                    throw UpdateError.checksumMismatch
                }
                guard NSWorkspace.shared.open(fileURL) else { throw UpdateError.openFailed }
            } catch {
                status = "无法打开已下载的安装镜像：\(error.localizedDescription)"
            }
        }
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
                if downloadedVersion == release.tagName {
                    status = "新版已下载，下次启动时可打开安装镜像。"
                } else if automaticDownloads {
                    startDownload(release)
                } else {
                    status = "发现新版本 \(release.tagName)，可前往 GitHub 下载。"
                    if manual || automaticChecks {
                        let notes = release.body.map { String($0.prefix(2_000)) } ?? ""
                        showNotice(title: "PhotoTrail \(release.tagName) 可供下载",
                                   message: "请先下载并打开 DMG，退出 PhotoTrail，再将应用拖到“应用程序”文件夹完成更新。\n\n" + notes,
                                   primaryTitle: "前往下载", primaryAction: { [weak self] in
                                       self?.openRelease()
                                   })
                    }
                }
            } else {
                status = "当前没有可用的新版本。"
                if manual { showNotice(title: "当前没有可用的新版本", message: "当前版本：\(current)") }
            }
        } catch {
            status = "暂时无法检查更新，请稍后重试，也可直接查看 GitHub 发布页。"
            if manual {
                showNotice(title: "暂时无法检查更新", message: status,
                           primaryTitle: "前往发布页", primaryAction: { [weak self] in
                               NSWorkspace.shared.open(Self.releasesURL)
                               self?.status = ""
                           })
            }
        }
    }

    private func startDownload(_ release: Release) {
        guard automaticDownloads, !downloading else { return }
        guard downloadedVersion != release.tagName else { return }
        guard let fileName = Self.dmgFileName(tagName: release.tagName),
              let asset = release.assets?.first(where: { $0.name == fileName }),
              Self.validatedAssetURL(asset, release: release, fileName: fileName) != nil else {
            status = "找不到有效的 DMG 下载项，可前往 GitHub 发布页下载。"
            return
        }
        downloading = true
        status = "正在自动下载 PhotoTrail \(release.tagName)…"
        downloadTask = Task { await download(release, asset: asset, fileName: fileName) }
    }

    private func download(_ release: Release, asset: ReleaseAsset, fileName: String) async {
        defer {
            downloading = false
            downloadTask = nil
        }
        do {
            guard let url = Self.validatedAssetURL(asset, release: release, fileName: fileName) else {
                throw UpdateError.invalidAsset
            }
            let request = Self.request(for: url, timeout: 300)
            let (temporaryURL, response) = try await URLSession.shared.download(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw UpdateError.badResponse
            }
            let actualSize = try FileManager.default.attributesOfItem(atPath: temporaryURL.path)[.size] as? Int64
            if let expectedSize = asset.size, let actualSize, expectedSize != actualSize {
                throw UpdateError.sizeMismatch
            }
            let expectedDigest = try await expectedDigest(for: asset, release: release, fileName: fileName)
            guard try Self.sha256(fileAt: temporaryURL) == expectedDigest else {
                throw UpdateError.checksumMismatch
            }
            try Task.checkCancellation()
            try FileManager.default.createDirectory(at: updatesDirectory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let finalURL = updatesDirectory.appending(path: fileName)
            try? FileManager.default.removeItem(at: finalURL)
            try FileManager.default.moveItem(at: temporaryURL, to: finalURL)
            if downloadedVersion != nil { removeDownloadedFile() }
            downloadedVersion = release.tagName
            downloadedDigest = expectedDigest
            defaults.set(release.tagName, forKey: Self.downloadedVersionKey)
            defaults.set(expectedDigest, forKey: Self.downloadedDigestKey)
            status = "PhotoTrail \(release.tagName) 已下载；下次启动时可打开安装镜像。"
        } catch is CancellationError {
            status = "已取消自动下载。"
        } catch {
            status = "自动下载失败：\(error.localizedDescription)。可前往 GitHub 手动下载。"
        }
    }

    private func expectedDigest(for asset: ReleaseAsset, release: Release, fileName: String) async throws -> String {
        if let digest = Self.normalizedSHA256(asset.digest) { return digest }
        guard let checksumAsset = release.assets?.first(where: { $0.name == "SHA256SUMS.txt" }),
              let url = Self.validatedAssetURL(checksumAsset, release: release, fileName: "SHA256SUMS.txt") else {
            throw UpdateError.missingChecksum
        }
        let (data, response) = try await URLSession.shared.data(for: Self.request(for: url, timeout: 30))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let checksum = Self.checksum(in: data, for: fileName) else {
            throw UpdateError.missingChecksum
        }
        return checksum
    }

    private func restoreDownloadedUpdate() {
        guard let version = defaults.string(forKey: Self.downloadedVersionKey),
              let digest = Self.normalizedSHA256(defaults.string(forKey: Self.downloadedDigestKey)),
              Self.isNewerVersion(version, than: Self.currentVersion),
              let url = Self.downloadURL(directory: updatesDirectory, tagName: version),
              FileManager.default.fileExists(atPath: url.path) else {
            removeDownloadedFile()
            return
        }
        downloadedVersion = version
        downloadedDigest = digest
    }

    private func removeDownloadedFile() {
        if let version = downloadedVersion ?? defaults.string(forKey: Self.downloadedVersionKey),
           let url = Self.downloadURL(directory: updatesDirectory, tagName: version) {
            try? FileManager.default.removeItem(at: url)
        }
        downloadedVersion = nil
        downloadedDigest = nil
        defaults.removeObject(forKey: Self.downloadedVersionKey)
        defaults.removeObject(forKey: Self.downloadedDigestKey)
    }

    @discardableResult
    private func showNotice(title: String, message: String,
                            primaryTitle: String? = nil, primaryAction: (() -> Void)? = nil) -> Bool {
        // Do not interrupt the setup wizard, file dialogs or unsaved-change confirmation.
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              NSApp.modalWindow == nil, window.attachedSheet == nil, !window.isSheet else { return false }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: primaryTitle ?? "好")
        if primaryAction != nil { alert.addButton(withTitle: "稍后") }
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { primaryAction?() }
        }
        return true
    }

}

extension SoftwareUpdate {
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

    static func dmgFileName(tagName: String) -> String? {
        guard let version = normalizedVersion(tagName) else { return nil }
        return "PhotoTrail-\(version)-macOS.dmg"
    }

    static func validatedAssetURL(_ asset: ReleaseAsset, release: Release, fileName: String) -> URL? {
        guard asset.name == fileName,
              let version = normalizedVersion(release.tagName),
              fileName == "PhotoTrail-\(version)-macOS.dmg" || fileName == "SHA256SUMS.txt",
              let suppliedURL = URL(string: asset.browserDownloadUrl),
              suppliedURL == URL(string: "https://github.com/LittleSixNine/PhotoTrail/releases/download/\(release.tagName)/\(fileName)")
        else { return nil }
        return suppliedURL
    }

    static func checksum(in data: Data, for fileName: String) -> String? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count == 2, fields[1] == Substring(fileName),
                  let digest = normalizedSHA256(String(fields[0])) else { continue }
            return digest
        }
        return nil
    }

    static func normalizedSHA256(_ digest: String?) -> String? {
        guard let digest else { return nil }
        let value = digest.hasPrefix("sha256:") ? String(digest.dropFirst(7)) : digest
        guard value.count == 64, value.allSatisfy(\.isHexDigit) else { return nil }
        return value.lowercased()
    }

    static func sha256(fileAt url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    private static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    private static func downloadURL(directory: URL, tagName: String) -> URL? {
        guard let fileName = dmgFileName(tagName: tagName) else { return nil }
        return directory.appending(path: fileName)
    }

    private static func request(for url: URL, timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.setValue("PhotoTrail", forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func normalizedVersion(_ version: String) -> String? {
        let value = version.hasPrefix("v") ? String(version.dropFirst()) : version
        return versionComponents(value) == nil ? nil : value
    }

    private static func isNewerVersion(_ candidate: String, than current: String) -> Bool {
        guard let remote = versionComponents(candidate), let local = versionComponents(current) else { return false }
        for index in 0..<max(remote.count, local.count) {
            let lhs = index < remote.count ? remote[index] : 0
            let rhs = index < local.count ? local[index] : 0
            if lhs != rhs { return lhs > rhs }
        }
        return false
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

    struct Release: Decodable, Sendable {
        let tagName: String
        let draft: Bool
        let prerelease: Bool
        let body: String?
        let assets: [ReleaseAsset]?

        var pageURL: URL {
            SoftwareUpdate.releasesURL.appendingPathComponent("tag").appendingPathComponent(tagName)
        }
    }

    struct ReleaseAsset: Decodable, Sendable {
        let name: String
        let size: Int64?
        let digest: String?
        let browserDownloadUrl: String
    }

    private enum UpdateError: LocalizedError {
        case invalidAsset
        case missingChecksum
        case badResponse
        case sizeMismatch
        case checksumMismatch
        case openFailed

        var errorDescription: String? {
            switch self {
            case .invalidAsset: "发布信息中的安装镜像无效"
            case .missingChecksum: "缺少有效的 SHA-256 校验值"
            case .badResponse: "下载服务器返回异常"
            case .sizeMismatch: "下载文件大小不匹配"
            case .checksumMismatch: "下载文件校验失败"
            case .openFailed: "macOS 未能打开磁盘映像"
            }
        }
    }
}
