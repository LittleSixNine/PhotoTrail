import AppKit
import CryptoKit
import Exiftool
import ImageData
import Observation
import UDF

@Observable @MainActor
final class RenameWorkspace {
    var rules: [RenameRule] = [RenameRule(action: 40), RenameRule(action: 48, prefix: "_")]
    var settings = RenameSettings()
    var onlySelected = false
    private var scopeInitialized = false
    var includeImportedPhotos = true
    var extraURLs: [URL] = []
    var authorizedDirectories = Set<URL>()
    @ObservationIgnored private var extraScopes: [URL] = []
    var rows: [RenamePreview] = []
    var plan: RenamePlan?
    var busy = false
    var executing = false
    var restoring = false
    var notice = ""
    var selectedRows = Set<URL>()
    var presets: [RenamePreset] = []
    var presetName = ""
    var counterRevision = 0
    var history: [RenameJournal] = []
    private static var operationActive = false
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var cache: [URL: (RenameFileIdentity, RenameInput)] = [:]
    @ObservationIgnored private var worker: Task<Void, Never>?

    var inputs: [RenameInput] { cache.values.map { $0.1 }.sorted { $0.url.path < $1.url.path } }

    var actionable: Int { rows.filter(\.changes).count }
    var blocked: Bool { rows.contains { $0.issues.contains(.invalidName) || $0.issues.contains(.conflict) } }
    var directoriesAuthorized: Bool {
        guard let plan else { return false }
        return plan.rows.allSatisfy { authorizedDirectories.contains($0.source.deletingLastPathComponent().standardizedFileURL) }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: "PhotoTrailRenamePresets.v1"),
           let saved = try? JSONDecoder().decode([RenamePreset].self, from: data) { presets = saved }
        history = RenameExecutor.journals()
    }

    deinit { for url in extraScopes { url.stopAccessingSecurityScopedResource() } }

    func initializeScope(selection: Set<ImageData.ID>) {
        guard !scopeInitialized else { return }
        onlySelected = !selection.isEmpty
        scopeInitialized = true
    }

    func addFiles(_ urls: [URL]) {
        guard !executing else { return }
        for url in urls where url.isFileURL && !extraURLs.contains(url.standardizedFileURL) {
            if url.startAccessingSecurityScopedResource() { extraScopes.append(url) }
            extraURLs.append(url.standardizedFileURL)
        }
    }

    func removeFile(_ url: URL) { extraURLs.removeAll { $0 == url } }

    func authorizeDirectory(_ url: URL) {
        let parent = URL(fileURLWithPath: url.standardizedFileURL.path, isDirectory: true)
        if url.startAccessingSecurityScopedResource() { extraScopes.append(url) }
        authorizedDirectories.insert(parent)
    }

    func savePreset() {
        let name = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        presets.append(RenamePreset(name: name, rules: rules, settings: settings))
        persistPresets()
        presetName = ""
    }

    func persistPresets() {
        if let data = try? JSONEncoder().encode(presets) { UserDefaults.standard.set(data, forKey: "PhotoTrailRenamePresets.v1") }
    }

    func importPreset(_ url: URL) {
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= 2_000_000 else { throw RenameError.invalidPreset }
            let preset = try JSONDecoder().decode(RenamePreset.self, from: data)
            guard preset.version == 1, preset.rules.count <= 200,
                  Set(preset.rules.map(\.id)).count == preset.rules.count,
                  preset.rules.allSatisfy({ (1...99).contains($0.action) }) else { throw RenameError.invalidPreset }
            rules = preset.rules; settings = preset.settings
        } catch { notice = RenameCopy.error(error) }
    }

    func exportPreset(_ url: URL) {
        do {
            let preset = RenamePreset(name: presetName.isEmpty ? "PhotoTrail" : presetName, rules: rules, settings: settings)
            try JSONEncoder().encode(preset).write(to: url, options: .atomic)
        } catch { notice = RenameCopy.error(error) }
    }

    func refresh(images: [ImageData], selection: Set<ImageData.ID>, directoryScopes: [URL] = []) {
        guard !executing else { return }
        for url in directoryScopes where (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            authorizedDirectories.insert(URL(fileURLWithPath: url.standardizedFileURL.path, isDirectory: true))
        }
        revision += 1
        let token = revision
        worker?.cancel()
        plan = nil
        busy = true
        let selected = images.filter { !onlySelected || selection.contains($0.id) }
        let urls = (includeImportedPhotos ? selected.compactMap(\.metadataCreatorImageURL) : []) + extraURLs
        var rules = self.rules
        let counterValues = Self.counters()
        for index in rules.indices where rules[index].counter > 0 {
            rules[index].start = counterValues[rules[index].counter] ?? 1
        }
        let frozenRules = rules
        let settings = self.settings, cached = cache
        let directories = authorizedDirectories
        worker = Task {
            do {
                try await Task.sleep(for: .milliseconds(180))
                let reader = Task.detached(priority: .userInitiated) {
                    try Self.prepare(urls: urls, rules: frozenRules, settings: settings, cache: cached,
                                     counters: counterValues, directories: directories)
                }
                let result = try await withTaskCancellationHandler {
                    try await reader.value
                } onCancel: { reader.cancel() }
                guard !Task.isCancelled, token == self.revision else { return }
                self.rows = result.plan.rows
                self.plan = result.plan
                self.cache = result.cache
                if !self.directoriesAuthorized { self.notice = L10n.text("请授权文件所在目录后重新预览，才能扫描配对文件并检查重名。") }
                else if self.notice == L10n.text("请授权文件所在目录后重新预览，才能扫描配对文件并检查重名。") { self.notice = "" }
            } catch {
                guard !Task.isCancelled, token == self.revision else { return }
                self.rows = []; self.notice = RenameCopy.error(error)
            }
            if token == self.revision { self.busy = false }
        }
    }

    private struct Prepared: Sendable {
        let plan: RenamePlan
        let cache: [URL: (RenameFileIdentity, RenameInput)]
    }

    nonisolated private static func prepare(urls: [URL], rules: [RenameRule], settings: RenameSettings,
                                           cache: [URL: (RenameFileIdentity, RenameInput)], counters: [Int: Int], directories: Set<URL>) throws -> Prepared {
        let urls = try RenameExecutor.pairedSources(urls, settings: settings, directories: directories)
        let referenceDate = Date()
        var inputs: [RenameInput] = []
        var versions: [URL: RenameFileIdentity] = [:]
        var updated: [URL: (RenameFileIdentity, RenameInput)] = [:]
        let needsTags = rules.contains { $0.enabled && ((40...45).contains($0.action) || (66...83).contains($0.action) || $0.action == 98) } || settings.sort == .shooting
        for url in urls {
            try Task.checkCancellation()
            let before = try RenameFileIdentity.read(url)
            let input = try Self.readInput(url: url, version: before, cached: cache[url], needsTags: needsTags)
            guard try RenameFileIdentity.read(url) == before else { throw RenameError.stalePlan }
            var prepared = input
            prepared.referenceDate = referenceDate
            inputs.append(prepared); versions[url] = before; updated[url] = (before, input)
        }
        let occupied = try RenameExecutor.occupied(Set(urls.map { $0.deletingLastPathComponent() }).intersection(directories))
        let rows = try RenameEngine.preview(inputs: inputs, rules: rules, settings: settings, occupied: occupied)
        var plan = RenamePlan(rows: rows, versions: versions)
        let usingCounters = rules.filter { $0.enabled && $0.counter > 0 }
        guard Set(usingCounters.map(\.counter)).count == usingCounters.count else { throw RenameError.invalidPreset }
        for rule in usingCounters {
            guard (1...10).contains(rule.counter), (46...51).contains(rule.action) else { throw RenameError.invalidRule(rule.action) }
            plan.counterValues[rule.counter] = counters[rule.counter]
            plan.counterAdvances[rule.counter] = try RenameEngine.nextCounter(rule, rows: rows)
        }
        return Prepared(plan: plan, cache: updated)
    }

    nonisolated private static func readInput(url: URL, version: RenameFileIdentity,
                                             cached: (RenameFileIdentity, RenameInput)?, needsTags: Bool) throws -> RenameInput {
        let input: RenameInput
        if let saved = cached, saved.0 == version, !needsTags || saved.1.tagsRead {
            input = saved.1
        } else {
            let values = try url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            var tags: [String: String] = [:]
            var failed = false
            if needsTags {
                do {
                    let key = MetadataInspectorReadCache.Key(url: url, imageURL: url, kind: .additional)
                    let versions = [MetadataInspectionFileVersion.read(url)]
                    if case .display(let cached) = MetadataInspectorReadCache.shared.value(for: key, versions: versions) {
                        tags = cached
                    } else { tags = try Exiftool.helper.inspectionTags(from: url) }
                }
                catch { failed = true }
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let seed = try encoder.encode(version)
            tags["PhotoTrail:RenameUUID"] = SHA256.hash(data: seed).map { String(format: "%02x", $0) }.joined()
            if let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber {
                tags["FileSizeInBytes"] = size.stringValue
                tags["FileSize"] = ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file)
            }
            if needsTags, let item = NSMetadataItem(url: url),
               let values = item.values(forAttributes: item.attributes) {
                for (attribute, value) in values where attribute.hasPrefix("kMDItem") {
                    let field = attribute == "kMDItemTitle" ? "ItemTitle" : String(attribute.dropFirst(7))
                    if let texts = value as? [String] { tags["Spotlight" + field] = texts.joined(separator: ", ") }
                    else if let date = value as? Date { tags["Spotlight" + field] = ISO8601DateFormatter().string(from: date) }
                    else { tags["Spotlight" + field] = String(describing: value) }
                }
            }
            input = RenameInput(url: url, tags: tags, created: values.creationDate,
                                modified: values.contentModificationDate, metadataFailure: failed, tagsRead: needsTags)
        }
        return input
    }

    static func counters(defaults: UserDefaults = .standard) -> [Int: Int] {
        Dictionary(uniqueKeysWithValues: (1...10).map { index in
            let key = "PhotoTrailRenameCounter.\(index)"
            return (index, defaults.object(forKey: key) == nil ? 1 : defaults.integer(forKey: key))
        })
    }

    func resetCounter(_ rule: RenameRule) {
        guard !Self.operationActive, (1...10).contains(rule.counter) else { return }
        UserDefaults.standard.set(rule.start, forKey: "PhotoTrailRenameCounter.\(rule.counter)")
        counterRevision += 1
    }

    static func sidecarsStayAttached(images: [ImageData], plan: RenamePlan) -> Bool {
        for image in images {
            guard case .xmp(let source) = image.metadata.source else { continue }
            let oldSidecar = source.deletingPathExtension().appendingPathExtension("xmp")
            let photo = plan.rows.first { $0.source == source.standardizedFileURL }
            let sidecar = plan.rows.first { $0.source == oldSidecar.standardizedFileURL }
            guard photo?.changes == true || sidecar?.changes == true else { continue }
            let photoTarget = photo?.target ?? source
            let sidecarTarget = sidecar?.target ?? oldSidecar
            guard sidecarTarget == photoTarget.deletingPathExtension().appendingPathExtension("xmp") else { return false }
        }
        return true
    }

    func execute(store: Store<PhotoTrailState, PhotoTrailEvent>) {
        guard let plan, !busy, !executing, !blocked, actionable > 0,
              !store.saveInProgress, !store.imageData.contains(where: \.hasPendingChanges) else { return }
        guard directoriesAuthorized else {
            notice = L10n.text("请授权文件所在目录后重新预览，才能扫描配对文件并检查重名。")
            return
        }
        guard !Self.operationActive else { notice = L10n.text("另一个窗口正在操作文件，请稍后重试。"); return }
        guard plan.counterValues.allSatisfy({ Self.counters()[$0.key] == $0.value }) else {
            notice = L10n.text("计数器已变化，请重新预览。")
            return
        }
        guard Self.sidecarsStayAttached(images: store.imageData, plan: plan) else {
            notice = L10n.text("照片有 XMP 旁车，请启用配对并保留旁车扩展名后重新预览。")
            return
        }
        executing = true
        Self.operationActive = true
        store.send(.renameStarted, undoable: false)
        let cancellation = RenameCancellation()
        worker = Task {
            let result: RenameExecutionResult?
            do {
                result = try await Task.detached(priority: .userInitiated) {
                    try RenameExecutor.execute(plan, cancelled: { cancellation.isCancelled })
                }.value
                if let result {
                    if result.error == nil {
                        for (index, value) in plan.counterAdvances {
                            UserDefaults.standard.set(value, forKey: "PhotoTrailRenameCounter.\(index)")
                        }
                    }
                    extraURLs = extraURLs.map { result.mappings[$0] ?? $0 }
                    store.send(.filesRenamed(result.mappings), undoable: false)
                    if result.needsRecovery {
                        let urls = Set(result.journal.entries.flatMap { [$0.original, $0.temporary, $0.target] })
                        store.send(.renameRecoveryChanged(urls, true), undoable: false)
                    }
                    if !result.mappings.isEmpty { store.discardAllUndo() }
                    notice = result.error.map { _ in result.needsRecovery ? L10n.text("部分文件需要恢复，请查看执行记录。") : L10n.text("执行中止，已恢复原文件名。") }
                        ?? L10n.text("已重命名 %1$@ 个文件，文件内容已核对。", result.mappings.count)
                }
            } catch { result = nil; notice = RenameCopy.error(error) }
            store.send(.renameFinished, undoable: false)
            executing = false
            Self.operationActive = false
            self.plan = nil
            cache = [:]
            history = RenameExecutor.journals()
        }
        cancelOperation = { cancellation.cancel() }
    }

    @ObservationIgnored private var cancelOperation: (() -> Void)?
    func cancel() { cancelOperation?() }

    func restore(_ journal: RenameJournal, store: Store<PhotoTrailState, PhotoTrailEvent>) {
        guard !executing, !store.saveInProgress, !store.imageData.contains(where: \.hasPendingChanges) else { return }
        guard !Self.operationActive else { notice = L10n.text("另一个窗口正在操作文件，请稍后重试。"); return }
        executing = true
        restoring = true
        Self.operationActive = true
        store.send(.renameStarted, undoable: false)
        Task {
            let before = await Task.detached { RenameExecutor.currentMappings(journal) }.value
            let outcome = await Task.detached { () -> (RenameJournal, String?) in
                var journal = journal
                do { try RenameExecutor.restore(&journal); return (journal, nil) }
                catch { return (journal, error.localizedDescription) }
            }.value
            let after = await Task.detached { RenameExecutor.currentMappings(outcome.0) }.value
            var mappings: [URL: URL] = [:]
            for entry in journal.entries {
                let from = before[entry.original] ?? entry.original
                let to = after[entry.original] ?? entry.original
                if from != to { mappings[from] = to }
            }
            extraURLs = extraURLs.map { mappings[$0] ?? $0 }
            store.send(.filesRenamed(mappings), undoable: false)
            let urls = Set(journal.entries.flatMap { [$0.original, $0.temporary, $0.target] })
            store.send(.renameRecoveryChanged(urls, outcome.1 != nil), undoable: false)
            if !mappings.isEmpty { store.discardAllUndo() }
            store.send(.renameFinished, undoable: false)
            notice = outcome.1.map { L10n.text("恢复未完成：%1$@。原文件未被覆盖。", $0) } ?? L10n.text("已恢复原文件名。")
            executing = false; restoring = false; Self.operationActive = false; plan = nil; cache = [:]
            history = RenameExecutor.journals()
        }
    }
}

private final class RenameCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isCancelled: Bool { lock.withLock { value } }
    func cancel() { lock.withLock { value = true } }
}

enum RenameCopy {
    static func issue(_ issue: RenameIssue) -> String {
        switch issue {
        case .missingDate: L10n.text("缺少拍摄时间")
        case .missingTag: L10n.text("缺少模板字段")
        case .missingAnchor: L10n.text("未找到定位文字")
        case .listMismatch: L10n.text("命名列表未匹配")
        case .excluded: L10n.text("被筛选排除")
        case .unchanged: L10n.text("保持不变")
        case .invalidName: L10n.text("文件名无效或过长")
        case .conflict: L10n.text("目标文件名冲突")
        case .metadataFailure: L10n.text("元数据读取失败")
        }
    }
    static func error(_ error: Error) -> String {
        switch error {
        case RenameError.invalidRule(let n): L10n.text("规则 R%1$@ 参数无效，请检查输入。", n)
        case RenameError.stalePlan: L10n.text("源文件已变化，请重新预览。")
        case RenameError.occupied: L10n.text("目标被占用，未覆盖文件。")
        case RenameError.invalidSource: L10n.text("源文件不可用、重复或为符号链接。")
        case RenameError.invalidPreset: L10n.text("预设格式或版本不受支持。")
        default: L10n.text("重命名失败：%1$@", error.localizedDescription)
        }
    }
}
