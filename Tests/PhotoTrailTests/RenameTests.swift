import Foundation
import CryptoKit
import Darwin
import Coords
import Exiftool
import ImageData
import Imagetool
import Metadata
@testable import PhotoTrail
import Testing
import UDF

struct RenameTests {
    @Test @MainActor func initialScopeUsesAllPhotosWithoutOverridingLaterChoices() {
        let image = ImageData(metadata: Metadata(source: .image(URL(fileURLWithPath: "/tmp/scope.jpg"))), name: "scope.jpg")
        let workspace = RenameWorkspace()
        workspace.initializeScope(selection: [image.id])
        #expect(!workspace.onlySelected)
        workspace.onlySelected = true
        workspace.initializeScope(selection: [image.id])
        #expect(workspace.onlySelected)
    }

    @Test @MainActor func draggingRulesPreservesOtherRulesAndRejectsStaleDrops() {
        let workspace = RenameWorkspace()
        let rules = [RenameRule(action: 1), RenameRule(action: 40), RenameRule(action: 48), RenameRule(action: 61)]
        workspace.rules = rules
        workspace.moveRule(rules[0].id, to: rules[3].id)
        #expect(workspace.rules.map(\.id) == [rules[1].id, rules[2].id, rules[3].id, rules[0].id])
        workspace.moveRule(rules[0].id, to: rules[1].id)
        #expect(workspace.rules == rules)
        workspace.moveRule(rules[1].id, to: rules[1].id)
        workspace.moveRule(UUID(), to: rules[2].id)
        workspace.moveRule(rules[1].id, to: UUID())
        #expect(workspace.rules == rules)
        workspace.executing = true
        workspace.moveRule(rules[0].id, to: rules[3].id)
        #expect(workspace.rules == rules)
    }

    private func input(_ name: String = "IMG_001.JPG", directory: String = "/tmp/rename") -> RenameInput {
        RenameInput(url: URL(fileURLWithPath: directory).appendingPathComponent(name), tags: [
            "ExifIFD:DateTimeOriginal": "2024:03:01 06:30:00", "ExifIFD:OffsetTimeOriginal": "+09:00",
            "IFD0:Model": "Camera", "File:ImageWidth": "4000", "File:ImageHeight": "3000"])
    }
    private func rename(_ name: String, rule: RenameRule) throws -> String {
        try RenameEngine.transform(name, input: input(name), rule: rule, index: 0, settings: RenameSettings()).0
    }

    @Test func fragmentsAndUnicode() throws {
        #expect(RenameEngine.split("archive.tar.gz").stem == "archive.tar")
        #expect(RenameEngine.split(".hidden").ext == "")
        #expect(RenameEngine.split("photo").ext == "")
        #expect(try rename("a👨‍👩‍👧‍👦é.JPG", rule: RenameRule(action: 26, position: 1, length: 1)) == "aé.JPG")
        #expect(try rename("a.JPG", rule: RenameRule(action: 31, part: .extensionOnly)) == "a.JPG")
        #expect(try rename("a.JPG", rule: RenameRule(action: 28, part: .extensionOnly)) == "a.jpg")
        #expect(!RenameEngine.validName("../x"))
        #expect(!RenameEngine.validName(String(repeating: "中", count: 86)))
        #expect(RenameEngine.key("é") == RenameEngine.key("É"))
    }

    @Test func textOccurrencesAndPositions() throws {
        #expect(try rename("a.a.a.jpg", rule: RenameRule(action: 11, text: "a", replacement: "b", occurrence: .last)) == "a.a.b.jpg")
        #expect(try rename("a.a.a.jpg", rule: RenameRule(action: 3, text: "X", anchor: "a", occurrence: .nth, matchNumber: 2)) == "a.Xa.a.jpg")
        #expect(try rename("abca.jpg", rule: RenameRule(action: 13, text: "a", occurrence: .all)) == "bcaa.jpg")
        #expect(try rename("abcd.jpg", rule: RenameRule(action: 27, position: 1, length: 2, start: 2)) == "adbc.jpg")
        #expect(try rename("abba.jpg", rule: RenameRule(action: 17, text: "ab", replacement: "xy")) == "xyyx.jpg")
        #expect(try rename("a😀2.jpg", rule: RenameRule(action: 23)) == "a2.jpg")
    }

    @Test func datesTimezonesNightAndMissing() throws {
        #expect(RenameEngine.parseDate("2024:02:29 23:59:59") != nil)
        #expect(RenameEngine.parseDate("2023:02:29 12:00:00") == nil)
        let rule = RenameRule(action: 40, dateFormat: "yyyy-MM-dd_HH-mm", timeZone: "Asia/Shanghai", nightHour: 6)
        #expect(try rename("IMG_001.JPG", rule: rule) == "2024-02-29_05-30.JPG")
        #expect(try rename("IMG_001.JPG", rule: RenameRule(action: 40)) == "20240301_063000.JPG")
        let noDate = RenameInput(url: URL(fileURLWithPath: "/tmp/NO_EXIF.jpg"))
        let rows = try RenameEngine.preview(inputs: [noDate], rules: [RenameRule(action: 40), RenameRule(action: 48)], settings: RenameSettings(), occupied: [:])
        #expect(rows[0].target.lastPathComponent == "NO_EXIF.jpg")
        #expect(rows[0].issues.contains(.missingDate))
    }

    @Test func sequencesTemplatesRegularExpressionsAndLists() throws {
        #expect(RenameEngine.roman(3999) == "MMMCMXCIX")
        #expect(RenameEngine.roman(0) == nil)
        #expect(RenameEngine.alphabet(26) == "Z")
        #expect(RenameEngine.alphabet(27) == "AA")
        #expect(try rename("IMG_001.JPG", rule: RenameRule(action: 46, start: 1000, padding: 2)) == "1000.JPG")
        #expect(try rename("IMG_001.JPG", rule: RenameRule(action: 52, numberValue: 9)) == "IMG_010.JPG")
        #expect(try rename("IMG_001.JPG", rule: RenameRule(action: 66, text: "<ShootingDate4DigitYear>_<CameraModel>")) == "2024_Camera.JPG")
        #expect(try rename("IMG_001.JPG", rule: RenameRule(action: 95, text: "([0-9]+)", replacement: "N$1")) == "IMG_N001.JPG")
        #expect(try rename("AbCd.JPG", rule: RenameRule(action: 95, text: "(Ab)(Cd)", replacement: #"\L$1\E\U$2\E"#)) == "abCD.JPG")
        #expect(try rename("IMG_001.JPG", rule: RenameRule(action: 96, text: "([0-9]+)", replacement: "R$1")) == "R001.JPG")
        #expect(try rename("IMG_001.JPG", rule: RenameRule(action: 96, text: "([0-9]+)", replacement: "R$1", fullMatch: true)) == "IMG_001.JPG")
        #expect(try rename("IMG_001.JPG", rule: RenameRule(action: 94, text: "IMG_001.JPG\tnew")) == "new.JPG")
        let music = RenameInput(url: URL(fileURLWithPath: "/tmp/song.mp3"), tags: ["ID3:Track": "3/12", "ID3:DiscNumber": "1/2", "Audio:Duration": "1:02:03"])
        #expect(RenameEngine.tag("TrackNum", input: music) == "3")
        #expect(RenameEngine.tag("0NumTracks", input: music) == "12")
        #expect(RenameEngine.tag("0CDNum", input: music) == "01")
        #expect(RenameEngine.tag("Duration_HH_MM_SS", input: music) == "01_02_03")
    }

    @Test func all97ActionsHaveRunnableCore() throws {
        #expect(RenameAction.all.count == 111)
        for action in 1...97 {
            let rule = RenameRule(action: action, text: action == 94 ? "new" : "0", replacement: "x", anchor: "IMG",
                                  position: 0, length: 1, start: 1)
            _ = try RenameEngine.transform("IMG_001.JPG", input: input(), rule: rule, index: 0, settings: RenameSettings())
        }
    }

    @Test func filtersResetAndSequencePerDirectory() throws {
        let inputs = [input("a.jpg"), input("b.jpg"), input("c.jpg", directory: "/tmp/other")]
        var filter = RenameRule(action: 98)
        filter.filters[0].value = "a"
        var reset = RenameRule(action: 98)
        reset.filters[0].value = ".jpg"
        let rules = [filter, RenameRule(action: 2, text: "X"), reset, RenameRule(action: 48, perDirectory: true)]
        var settings = RenameSettings(); settings.pair = false
        let result = try RenameEngine.preview(inputs: inputs, rules: rules, settings: settings, occupied: [:])
        #expect(result.map { $0.target.lastPathComponent } == ["aX001.jpg", "b002.jpg", "c001.jpg"])
    }

    @Test func pairedFinalConflictsShareStem() throws {
        let inputs = [input("IMG_001.JPG"), input("IMG_001.ARW"), input("IMG_001.xmp"), input("IMG_002.JPG")]
        let occupied = ["/tmp/rename": Set(["same.jpg"])]
        let result = try RenameEngine.preview(inputs: inputs, rules: [RenameRule(action: 97, text: "same")], settings: RenameSettings(), occupied: occupied)
        #expect(result[0].target.lastPathComponent == "same_001.JPG")
        #expect(result[1].target.lastPathComponent == "same_001.ARW")
        #expect(result[2].target.lastPathComponent == "same_001.xmp")
        #expect(result[3].target.lastPathComponent == "same_002.JPG")
    }

    private func fixture() throws -> URL {
        let url = URL.temporaryDirectory.appendingPathComponent("PhotoTrail-rename-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
    private func plan(_ mappings: [(URL, URL)]) throws -> RenamePlan {
        let rows = mappings.map { RenamePreview(source: $0.0, target: $0.1, steps: [], issues: [], group: $0.0.path) }
        let versions = try Dictionary(uniqueKeysWithValues: mappings.map { ($0.0, try RenameFileIdentity.read($0.0)) })
        return RenamePlan(rows: rows, versions: versions)
    }

    @Test func swapsHashesJournalAndActualUndo() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("a"), b = root.appendingPathComponent("b")
        try Data("first".utf8).write(to: a); try Data("second".utf8).write(to: b)
        let history = root.appendingPathComponent("history")
        let result = try RenameExecutor.execute(plan([(a,b),(b,a)]), directory: history)
        #expect(result.error == nil)
        #expect(try String(contentsOf: b, encoding: .utf8) == "first")
        #expect(try String(contentsOf: a, encoding: .utf8) == "second")
        var journal = try #require(RenameExecutor.journals(directory: history).first)
        try RenameExecutor.restore(&journal, directory: history)
        #expect(try String(contentsOf: a, encoding: .utf8) == "first")
        #expect(try String(contentsOf: b, encoding: .utf8) == "second")
        #expect(journal.state == "restored")
    }

    @Test func stalePreviewAndOccupiedTargetNeverOverwrite() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("a"), b = root.appendingPathComponent("b")
        try Data("source".utf8).write(to: a)
        let frozen = try plan([(a,b)])
        try Data("changed".utf8).write(to: a)
        #expect(throws: RenameError.self) { try RenameExecutor.execute(frozen, directory: root.appendingPathComponent("history")) }
        try Data("external".utf8).write(to: b)
        let result = try RenameExecutor.execute(plan([(a,b)]), directory: root.appendingPathComponent("history"))
        #expect(result.error != nil)
        #expect(!result.needsRecovery)
        #expect(try String(contentsOf: a, encoding: .utf8) == "changed")
        #expect(try String(contentsOf: b, encoding: .utf8) == "external")
    }

    @Test func undoRefusesChangedOrOccupiedFiles() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("a"), b = root.appendingPathComponent("b")
        try Data("source".utf8).write(to: a)
        var journal = try RenameExecutor.execute(plan([(a,b)]), directory: root.appendingPathComponent("history")).journal
        try Data("new".utf8).write(to: a)
        #expect(throws: RenameError.self) { try RenameExecutor.restore(&journal, directory: root.appendingPathComponent("history")) }
        #expect(try String(contentsOf: b, encoding: .utf8) == "source")
        #expect(try String(contentsOf: a, encoding: .utf8) == "new")
    }

    @Test func realPhotoRenameRetainsIDAndSavePath() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try #require(Bundle.main.url(forResource: "P1000658", withExtension: "JPG"))
        let source = root.appendingPathComponent("old.JPG"), target = root.appendingPathComponent("new.JPG")
        try FileManager.default.copyItem(at: fixture, to: source)
        var image = ImageData(from: source)
        let id = image.id, bytes = try Data(contentsOf: source)
        let result = try RenameExecutor.execute(plan([(source,target)]), directory: root.appendingPathComponent("history"))
        image.applyFileRenames(result.mappings)
        #expect(image.id == id)
        #expect(image.metadataCreatorImageURL == target)
        #expect(image.metadataInspectionURL == target)
        #expect(image.name == "new.JPG")
        #expect(image.original?.source == image.metadata.source)
        #expect(!image.hasPendingChanges)
        #expect(try Data(contentsOf: target) == bytes)
        #expect(Imagetool.metadata(from: target).dateTimeCreated == image.metadata.dateTimeCreated)
        var edited = image.metadata
        edited.location = Coords(latitude: 31.23, longitude: 121.48)
        edited.gpsMapDatum = "WGS-84"
        edited.gpsProcessingMethod = "MANUAL"
        try await Exiftool.helper.update(image: image.metadataInspectionURL!, from: edited, timeZone: nil)
        let readback = Imagetool.metadata(from: target)
        #expect(abs(try #require(readback.location).latitude - 31.23) < 0.000001)
        #expect(!FileManager.default.fileExists(atPath: source.path))
        var journal = result.journal
        #expect(throws: RenameError.self) { try RenameExecutor.restore(&journal, directory: root.appendingPathComponent("history")) }
    }

    @Test @MainActor func pairedSidecarRenameThenSave() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try #require(Bundle.main.url(forResource: "P1000658", withExtension: "JPG"))
        let source = root.appendingPathComponent("old.JPG"), xmp = root.appendingPathComponent("old.xmp")
        let target = root.appendingPathComponent("new.JPG"), targetXMP = root.appendingPathComponent("new.xmp")
        try FileManager.default.copyItem(at: fixture, to: source)
        try Exiftool.helper.xmpData(from: source).write(to: xmp)
        var image = ImageData(from: source)
        #expect(image.metadataInspectionURL == xmp)
        #expect(!RenameWorkspace.sidecarsStayAttached(images: [image], plan: try plan([(xmp,targetXMP)])))
        let renamePlan = try plan([(source,target),(xmp,targetXMP)])
        #expect(RenameWorkspace.sidecarsStayAttached(images: [image], plan: renamePlan))
        let result = try RenameExecutor.execute(renamePlan, directory: root.appendingPathComponent("history"))
        let photoBytes = try Data(contentsOf: target)
        image.applyFileRenames(result.mappings)
        #expect(image.metadataInspectionURL == targetXMP)
        _ = try Exiftool.helper.update(image: image.metadataInspectionURL!, changes: [.titleDefault: .set(.text("after rename"))])
        #expect(try Exiftool.helper.metadataTags([.titleDefault], from: targetXMP)[.titleDefault] == .text("after rename"))
        #expect(try Data(contentsOf: target) == photoBytes)
        #expect(!FileManager.default.fileExists(atPath: xmp.path))
    }

    @Test func cycleCancellationCrashRecoveryAndSymlinks() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let urls = (0...2).map { root.appendingPathComponent("\($0)") }
        for (index,url) in urls.enumerated() { try Data("\(index)".utf8).write(to: url) }
        let history = root.appendingPathComponent("history")
        let cycle = try RenameExecutor.execute(plan([(urls[0],urls[1]),(urls[1],urls[2]),(urls[2],urls[0])]), directory: history)
        var journal = cycle.journal
        // Simulate an interrupted restore with one file already at its recorded staging path.
        let entry = journal.entries[0]
        try RenameExecutor.move(entry.target, to: entry.temporary)
        journal.state = "restoring"
        try RenameExecutor.write(journal, directory: history)
        journal = try #require(RenameExecutor.journals(directory: history).first)
        try RenameExecutor.restore(&journal, directory: history)
        for (index,url) in urls.enumerated() { #expect(try String(contentsOf: url, encoding: .utf8) == "\(index)") }
        #expect(throws: RenameError.self) {
            try RenameExecutor.execute(plan([(urls[0],root.appendingPathComponent("cancelled"))]), directory: history, cancelled: { true })
        }
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: urls[0])
        #expect(throws: RenameError.self) { try RenameFileIdentity.read(link) }
    }

    @Test func pairingScansOnlyAuthorizedDirectories() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let photo = root.appendingPathComponent("pair.JPG"), sidecar = root.appendingPathComponent("pair.xmp")
        try Data("photo".utf8).write(to: photo); try Data("sidecar".utf8).write(to: sidecar)
        let settings = RenameSettings()
        #expect(try RenameExecutor.pairedSources([photo,photo], settings: settings, directories: []) == [photo])
        let authorized = Set([photo.deletingLastPathComponent().standardizedFileURL])
        #expect(Set(try RenameExecutor.pairedSources([photo], settings: settings, directories: authorized)) == Set([photo,sidecar]))
    }

    @Test func compatibilityRenameCanRestoreLegacyColonName() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("legacy:name"), target = root.appendingPathComponent("legacy_name")
        try Data("sample".utf8).write(to: source)
        let history = root.appendingPathComponent("history")
        var journal = try RenameExecutor.execute(plan([(source,target)]), directory: history).journal
        try RenameExecutor.restore(&journal, directory: history)
        #expect(try String(contentsOf: source, encoding: .utf8) == "sample")
        #expect(!FileManager.default.fileExists(atPath: target.path))
    }

    @Test func countersDoNotReuseLaterNumberAfterMissingTagSkipsAGroup() throws {
        let sequence = RenameRule(action: 46, start: 7, counter: 10)
        let inputs = [input("a.JPG"), RenameInput(url: URL(fileURLWithPath: "/tmp/rename/b.JPG")), input("c.JPG")]
        var settings = RenameSettings(); settings.pair = false
        let rows = try RenameEngine.preview(inputs: inputs, rules: [sequence, RenameRule(action: 68, text: "<CameraModel>")],
                                            settings: settings, occupied: [:])
        #expect(rows.map { $0.target.lastPathComponent } == ["007Camera.JPG", "b.JPG", "009Camera.JPG"])
        #expect(try RenameEngine.nextCounter(sequence, rows: rows) == 10)
    }

    @Test @MainActor func countersPreviewAndExecutionUseActualMapping() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.jpg")
        let sample = try #require(Bundle.main.url(forResource: "P1000658", withExtension: "JPG"))
        try FileManager.default.copyItem(at: sample, to: source)
        let image = ImageData(from: source)
        let key = "PhotoTrailRenameCounter.10", old = UserDefaults.standard.object(forKey: "PhotoTrailRenameCounter.10")
        UserDefaults.standard.set(7, forKey: key)
        defer { UserDefaults.standard.set(old, forKey: key) }
        let workspace = RenameWorkspace()
        workspace.authorizeDirectory(root)
        workspace.rules = [RenameRule(action: 46, counter: 10)]
        workspace.settings.pair = false
        for _ in 0..<2 {
            workspace.refresh(images: [image], selection: [])
            for _ in 0..<400 where workspace.busy { try await Task.sleep(for: .milliseconds(25)) }
            #expect(!workspace.busy)
            #expect(workspace.rows.count == 1)
            #expect(workspace.directoriesAuthorized)
            #expect(workspace.rows.first?.target.lastPathComponent == "007.jpg")
            #expect(RenameWorkspace.counters()[10] == 7)
        }
        var state = PhotoTrailState()
        state.imageData = [image]
        let store = Store(initialState: state, reduce: PhotoTrailReducer())
        var pending = ImageData(metadata: Metadata(source: .xmp(root.appendingPathComponent("pending.xmp"))), name: "pending.jpg")
        pending.metadata.location = Coords(latitude: 31.23, longitude: 121.48)
        var pendingState = PhotoTrailState()
        pendingState.imageData = [pending]
        pendingState.unsavedChanges = true
        let pendingStore = Store(initialState: pendingState, reduce: PhotoTrailReducer())
        workspace.execute(store: pendingStore)
        #expect(!workspace.executing)
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(RenameWorkspace.counters()[10] == 7)
        UserDefaults.standard.set(9, forKey: key)
        workspace.execute(store: store)
        #expect(!workspace.executing)
        #expect(FileManager.default.fileExists(atPath: source.path))
        UserDefaults.standard.set(7, forKey: key)
        workspace.execute(store: store)
        for _ in 0..<400 where workspace.executing { try await Task.sleep(for: .milliseconds(25)) }
        #expect(!workspace.executing)
        #expect(RenameWorkspace.counters()[10] == 8)
        #expect(store.imageData.first?.metadataCreatorImageURL == root.appendingPathComponent("007.jpg"))
        if let journal = workspace.history.first(where: { $0.entries.first?.original == source }) {
            try FileManager.default.removeItem(at: RenameExecutor.storage.appendingPathComponent(journal.id.uuidString + ".json"))
        }
    }
}

private final class RenameProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var updates: [RenameProgress] = []
    var values: [RenameProgress] { lock.withLock { updates } }
    func record(_ value: RenameProgress) { lock.withLock { updates.append(value) } }
}

private final class RenameReadCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var checks: Int { lock.withLock { count } }
    func shouldCancel() -> Bool { lock.withLock { count += 1; return count >= 3 } }
}

extension RenameTests {
    @Test func streamingDigestMatchesAndStopsBetweenBlocks() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("large.JPG")
        let bytes = Data(repeating: 0x5a, count: 3 * 1_048_576 + 17)
        try bytes.write(to: file)
        let expected = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        #expect(try RenameExecutor.digest(file) == expected)
        let cancellation = RenameReadCancellation()
        #expect(throws: CancellationError.self) {
            try RenameExecutor.digest(file, cancelled: { cancellation.shouldCancel() })
        }
        #expect(cancellation.checks == 3)
    }

    @Test func stoppingAfterStagingRestoresAllFiles() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("IMG.JPG")
        let target = root.appendingPathComponent("renamed.JPG")
        let data = Data(repeating: 0x5a, count: 2 * 1_048_576)
        try data.write(to: original)
        let recorder = RenameProgressRecorder()
        let result = try RenameExecutor.execute(plan([(original, target)]), directory: root.appendingPathComponent("journal"),
            cancelled: { recorder.values.contains { $0.phase == .renaming } },
            progress: { recorder.record($0) })
        #expect(result.error != nil)
        #expect(!result.needsRecovery)
        #expect(result.journal.state == "restored")
        #expect(result.mappings.isEmpty)
        #expect(try Data(contentsOf: original) == data)
        #expect(!FileManager.default.fileExists(atPath: target.path))
        #expect(recorder.values.last?.phase == .restoring)
    }

    @Test func batchOf3000FilesRenamesAndRestoresWithProgress() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let data = Data(repeating: 0x5a, count: 256 * 1024)
        var mappings: [(URL, URL)] = []
        for index in 0..<3000 {
            let original = root.appendingPathComponent("IMG_\(index).JPG")
            try data.write(to: original)
            mappings.append((original, root.appendingPathComponent("renamed_\(index).JPG")))
        }
        let recorder = RenameProgressRecorder()
        let result = try RenameExecutor.execute(plan(mappings), directory: root.appendingPathComponent("journal"),
                                                progress: { recorder.record($0) })
        #expect(result.error == nil)
        #expect(result.mappings.count == 3000)
        #expect(result.journal.state == "completed")
        let updates = recorder.values
        #expect(updates.first?.phase == .checking)
        #expect(updates.last?.phase == .verifying)
        #expect(updates.last?.completed == 3000)
        #expect(zip(updates, updates.dropFirst()).allSatisfy { $0.fraction <= $1.fraction })
        var journal = result.journal
        try RenameExecutor.restore(&journal, directory: root.appendingPathComponent("journal"),
                                   progress: { recorder.record($0) })
        #expect(journal.state == "restored")
        #expect(recorder.values.last?.phase == .restoring)
        #expect(recorder.values.last?.completed == 3000)
        for (original, target) in mappings {
            #expect(FileManager.default.fileExists(atPath: original.path))
            #expect(!FileManager.default.fileExists(atPath: target.path))
        }
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        print("Rename 3000 files: peak RSS MiB=\(usage.ru_maxrss / 1_048_576)")
    }

}

extension RenameTests {
    @Test func conflictSuffixFormatsAndLegacySettings() throws {
        let legacy = try JSONDecoder().decode(RenameSettings.self, from: JSONEncoder().encode(RenameSettings()))
        #expect(legacy.numberSuffixFormat == nil && legacy.conflictDigits == nil)
        for width in 2...5 {
            for format in RenameSettings.SuffixFormat.allCases {
                var settings = legacy
                settings.keepFirst = false
                settings.conflictDigits = width
                settings.numberSuffixFormat = format
                let rows = try RenameEngine.preview(inputs: [input()], rules: [RenameRule(action: 97, text: "new")], settings: settings, occupied: [:])
                #expect(rows[0].target.lastPathComponent == "new" + format.format(RenameEngine.padded(1, width: width)) + ".JPG")
                settings.conflict = .letters
                settings.letterSuffixFormat = format
                let letters = try RenameEngine.preview(inputs: [input()], rules: [RenameRule(action: 97, text: "new")], settings: settings, occupied: [:])
                #expect(letters[0].target.lastPathComponent == "new" + format.format("A") + ".JPG")
            }
        }
    }
}

struct RenamePresetTests {
    @Test @MainActor func defaultPrefixPlaceholderMigratesOnlyUntouchedSchemes() throws {
        let domain = "PhotoTrail.PrefixPlaceholderTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let workspace = RenameWorkspace(defaults: defaults)
        let original = try #require(workspace.presets.last)
        #expect(original.rules.last?.text == L10n.text("请自定义文字") + "_")
        #expect(original.example == L10n.text("请自定义文字") + "_0001.jpg")
        var legacy = original
        legacy.rules = [RenameRule(action: 46, padding: 4), RenameRule(action: 1, text: "哈尔滨之旅_")]
        legacy.example = "哈尔滨之旅_0001.jpg"
        var custom = legacy
        custom.id = UUID()
        custom.rules[1].text = "我的旅行_"
        defaults.set(try JSONEncoder().encode([legacy, custom]), forKey: "PhotoTrailRenamePresets.v1")
        defaults.set(try JSONEncoder().encode(legacy), forKey: "PhotoTrailRenameLastPreset.v1")
        let reopened = RenameWorkspace(defaults: defaults)
        #expect(reopened.presetExample == L10n.text("请自定义文字") + "_0001.jpg")
        #expect(reopened.rules.last?.text == L10n.text("请自定义文字") + "_")
        #expect(reopened.presets.last?.rules.last?.text == "我的旅行_")
        #expect(reopened.presets.last?.example == "哈尔滨之旅_0001.jpg")
    }

    @Test @MainActor func ruleChangesRefreshExamplesWithoutSavingDraftRulesOrReplacingManualExamples() async throws {
        let domain = "PhotoTrail.ExampleTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.jpg")
        let sample = try #require(Bundle.main.url(forResource: "P1000658", withExtension: "JPG"))
        try FileManager.default.copyItem(at: sample, to: source)
        let image = ImageData(from: source)
        let workspace = RenameWorkspace(defaults: defaults)
        workspace.authorizeDirectory(root)
        workspace.rules = [RenameRule(action: 1, text: "old_")]
        workspace.settings.pair = false
        workspace.presetExample = "手动示例.jpg"
        workspace.presetName = "示例更新"
        workspace.savePreset()
        workspace.rules[0].text = "trip_"
        workspace.refresh(images: [], selection: [])
        for _ in 0..<400 where workspace.busy { try await Task.sleep(for: .milliseconds(25)) }
        #expect(!workspace.busy && workspace.presetExample == "手动示例.jpg")
        workspace.refresh(images: [image], selection: [])
        workspace.rules[0].text = "film_"
        workspace.refresh(images: [image], selection: [])
        for _ in 0..<400 where workspace.busy { try await Task.sleep(for: .milliseconds(25)) }
        #expect(!workspace.busy && workspace.presetExample == "film_source.jpg")
        #expect(RenameWorkspace(defaults: defaults).presetExample == "手动示例.jpg")
        workspace.updateCurrentPreset()
        #expect(RenameWorkspace(defaults: defaults).presetExample == "film_source.jpg")
        workspace.presetExample = "新的手动示例.jpg"
        workspace.refresh(images: [image], selection: [])
        for _ in 0..<400 where workspace.busy { try await Task.sleep(for: .milliseconds(25)) }
        #expect(!workspace.busy && workspace.presetExample == "新的手动示例.jpg")
        workspace.rules[0].text = "travel_"
        workspace.refresh(images: [image], selection: [])
        workspace.presetExample = "计算期间手动编辑.jpg"
        for _ in 0..<400 where workspace.busy { try await Task.sleep(for: .milliseconds(25)) }
        #expect(!workspace.busy && workspace.presetExample == "计算期间手动编辑.jpg")
        workspace.rules[0].text = "saved_"
        workspace.refresh(images: [image], selection: [])
        workspace.updateCurrentPreset()
        for _ in 0..<400 where workspace.busy { try await Task.sleep(for: .milliseconds(25)) }
        #expect(!workspace.busy && workspace.presetExample == "saved_source.jpg")
        #expect(RenameWorkspace(defaults: defaults).presetExample == "saved_source.jpg")
    }

    @Test @MainActor func defaultSchemesAreEditablePersistExamplesAndStayDeleted() throws {
        let domain = "PhotoTrail.SchemeTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let workspace = RenameWorkspace(defaults: defaults)
        #expect(workspace.presets.count == 5)
        let input = RenameInput(url: URL(fileURLWithPath: "/tmp/DSC_1234.jpg"), tags: [
            "ExifIFD:DateTimeOriginal": "2026:10:06 17:16:49", "IFD0:Model": "NIKON D750",
            "IPTC:City": "旧城市", "XMP-photoshop:City": "上海市"])
        for preset in workspace.presets {
            var name = input.name
            for rule in preset.rules {
                name = try RenameEngine.transform(name, input: input, rule: rule, index: 0, settings: preset.settings).0
            }
            #expect(name == preset.example)
        }
        let first = try #require(workspace.presets.first)
        let token = workspace.presetActivationID
        workspace.activatePreset(first)
        #expect(workspace.presetActivationID != token)
        workspace.presetExample = "手动示例.jpg"
        #expect(workspace.presetModified)
        workspace.updateCurrentPreset()
        let reopened = RenameWorkspace(defaults: defaults)
        #expect(reopened.presetExample == "手动示例.jpg")
        for preset in reopened.presets { reopened.deletePreset(preset.id) }
        let empty = RenameWorkspace(defaults: defaults)
        #expect(empty.presets.isEmpty && empty.rules.isEmpty)
        #expect(empty.currentPresetID == nil)
    }

    @MainActor @Test func executionHistoryLoadsOnlyWhenRequested() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = RenameJournal(state: "completed", entries: [])
        try RenameExecutor.write(journal, directory: directory)
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let workspace = RenameWorkspace(defaults: defaults)
        #expect(workspace.history.isEmpty)
        await workspace.loadHistory(directory: directory)
        #expect(workspace.history.map(\.id) == [journal.id])
        #expect(!workspace.historyLoading)
    }

    @Test @MainActor func restartingRestoresTheLastCommonPresetWithoutSavingDraftRulesOrScope() {
        let domain = "PhotoTrailRenameTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let workspace = RenameWorkspace(defaults: defaults)
        let rules = [RenameRule(action: 11)]
        workspace.activateCommonPreset(name: "查找并替换", rules: rules)
        workspace.rules[0].text = "未保存的修改"
        workspace.onlySelected = true
        let reopened = RenameWorkspace(defaults: defaults)
        #expect(reopened.currentPresetName == "查找并替换")
        #expect(reopened.rules == rules)
        #expect(!reopened.presetModified)
        #expect(!reopened.onlySelected)
    }

    @Test @MainActor func restartingRestoresUpdatedSavedPresetAndHandlesDeletion() {
        let domain = "PhotoTrailRenameTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let workspace = RenameWorkspace(defaults: defaults)
        workspace.presetName = "旅行"
        workspace.savePreset()
        let id = workspace.currentPresetID!
        workspace.rules[0].prefix = "trip_"
        workspace.updateCurrentPreset()
        workspace.renamePreset(id, name: "胶片")
        let reopened = RenameWorkspace(defaults: defaults)
        #expect(reopened.currentPresetID == id)
        #expect(reopened.currentPresetName == "胶片")
        #expect(reopened.rules == workspace.rules)
        reopened.deletePreset(id)
        let afterDeletion = RenameWorkspace(defaults: defaults)
        #expect(afterDeletion.currentPresetID == afterDeletion.presets.first?.id)
        #expect(afterDeletion.rules == afterDeletion.presets.first?.rules)
    }

    @Test @MainActor func presetsTrackChangesAndKeepTheirIdentityWhenUpdated() {
        let domain = "PhotoTrailRenameTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let workspace = RenameWorkspace(defaults: defaults)
        workspace.presets = []
        #expect(!workspace.presetModified)
        workspace.rules[0].prefix = "trip_"
        #expect(workspace.presetModified)
        workspace.presetName = "旅行"
        workspace.savePreset()
        let id = workspace.currentPresetID!
        #expect(workspace.presets.count == 1)
        #expect(!workspace.presetModified)
        workspace.rules[0].prefix = "film_"
        workspace.updateCurrentPreset()
        #expect(workspace.currentPresetID == id)
        #expect(workspace.presets[0].rules == workspace.rules)
        #expect(!workspace.presetModified)
        workspace.renamePreset(id, name: "胶片")
        #expect(workspace.currentPresetName == "胶片")
        workspace.presetName = "胶片"
        workspace.savePreset()
        #expect(workspace.presets.map(\.name) == ["胶片", "胶片 (2)"])
        let rules = workspace.rules
        workspace.deletePreset(workspace.currentPresetID!)
        #expect(workspace.presets.count == 1)
        #expect(workspace.currentPresetID == nil)
        #expect(workspace.rules == rules)
        #expect(workspace.presetModified)
    }

    @Test @MainActor func importedRenamePresetsRemainCompatibleAndDoNotOverwriteSavedPresets() throws {
        let domain = "PhotoTrailRenameTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let workspace = RenameWorkspace(defaults: defaults)
        workspace.presets = []
        workspace.presetName = "测试"
        workspace.savePreset()
        workspace.exportPreset(url)
        let exported = try JSONDecoder().decode(RenamePreset.self, from: Data(contentsOf: url))
        #expect(exported.version == 1)
        #expect(exported.name == "测试")
        workspace.importPreset(url)
        #expect(workspace.presets.count == 2)
        #expect(Set(workspace.presets.map(\.id)).count == 2)
        #expect(workspace.currentPresetName == "测试 (2)")
        #expect(workspace.rules == exported.rules)
        #expect(workspace.settings == exported.settings)
        #expect(!workspace.presetModified)
    }

}

extension RenameTests {
    @Test func deviceAndRegionFieldsUseReadableActionsAndKeepMissingValuesSafe() throws {
        let input = RenameInput(url: URL(fileURLWithPath: "/tmp/source.jpg"), tags: [
            "IFD0:Model": "D750", "IPTC:Sub-location": "旧区", "XMP-iptcCore:Location": "新区"])
        #expect(try RenameEngine.transform(input.name, input: input, rule: RenameRule(action: 100),
            index: 0, settings: RenameSettings()).0 == "D750.jpg")
        #expect(try RenameEngine.transform(input.name, input: input,
            rule: RenameRule(action: 106, metadataField: "IPTCSubLocation"), index: 0, settings: RenameSettings()).0 == "新区.jpg")
        let missing = try RenameEngine.preview(inputs: [input], rules: [RenameRule(action: 106)],
            settings: RenameSettings(), occupied: [:])
        #expect(missing[0].target == input.url)
        #expect(missing[0].issues.contains(.missingTag))
    }
}
