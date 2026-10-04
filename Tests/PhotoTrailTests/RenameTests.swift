import Foundation
import Coords
import Exiftool
import ImageData
import Imagetool
import Metadata
@testable import PhotoTrail
import Testing
import UDF

struct RenameTests {
    @Test @MainActor func initialScopeFollowsPhotoSelectionWithoutOverridingLaterChoices() {
        let image = ImageData(metadata: Metadata(source: .image(URL(fileURLWithPath: "/tmp/scope.jpg"))), name: "scope.jpg")
        let workspace = RenameWorkspace()
        workspace.initializeScope(selection: [image.id])
        #expect(workspace.onlySelected)
        workspace.initializeScope(selection: [])
        #expect(workspace.onlySelected)
        workspace.onlySelected = false
        workspace.initializeScope(selection: [image.id])
        #expect(!workspace.onlySelected)
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
        #expect(RenameAction.all.count == 99)
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
        let source = root.appendingPathComponent("source.txt")
        try Data("sample".utf8).write(to: source)
        let key = "PhotoTrailRenameCounter.10", old = UserDefaults.standard.object(forKey: "PhotoTrailRenameCounter.10")
        UserDefaults.standard.set(7, forKey: key)
        defer { UserDefaults.standard.set(old, forKey: key) }
        let workspace = RenameWorkspace()
        workspace.includeImportedPhotos = false
        workspace.addFiles([source,source])
        workspace.authorizeDirectory(root)
        workspace.rules = [RenameRule(action: 46, counter: 10)]
        workspace.settings.pair = false
        for _ in 0..<2 {
            workspace.refresh(images: [], selection: [])
            for _ in 0..<400 where workspace.busy { try await Task.sleep(for: .milliseconds(25)) }
            #expect(!workspace.busy)
            #expect(workspace.rows.count == 1)
            #expect(workspace.directoriesAuthorized)
            #expect(workspace.rows.first?.target.lastPathComponent == "007.txt")
            #expect(RenameWorkspace.counters()[10] == 7)
        }
        let store = Store(initialState: PhotoTrailState(), reduce: PhotoTrailReducer())
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
        #expect(workspace.extraURLs == [root.appendingPathComponent("007.txt")])
        if let journal = workspace.history.first(where: { $0.entries.first?.original == source }) {
            try FileManager.default.removeItem(at: RenameExecutor.storage.appendingPathComponent(journal.id.uuidString + ".json"))
        }
    }
}
