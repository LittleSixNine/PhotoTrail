@testable import Exiftool
import Foundation
import Testing
@testable import ImageData

struct VideoReadTests {
    func fixture(_ name: String, _ ext: String) throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "VideoFixtures"))
    }

    @Test func movieIgnoresSameStemPhotoSidecar() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let video = folder.appendingPathComponent("shared.MOV")
        let photo = folder.appendingPathComponent("shared.jpg")
        let xmp = folder.appendingPathComponent("shared.xmp")
        let fm = FileManager.default
        try fm.copyItem(at: fixture("tagged", "mov"), to: video)
        try fm.copyItem(at: #require(Bundle.module.url(forResource: "alldata", withExtension: "jpg")), to: photo)
        try fm.copyItem(at: #require(Bundle.module.url(forResource: "262M1559", withExtension: "xmp")), to: xmp)
        let files = [video, photo, xmp]
        let before = try files.map { try Data(contentsOf: $0) }
        let item = ImageData(from: video)
        let info = try #require(item.videoInfo)
        #expect(item.metadata.readable && item.updatable && item.supportsMetadataEditing(.captureLocation) && item.supportsMetadataEditing(.lens))
        #expect(item.metadataInspectionURL == video)
        #expect(item.name == "shared.MOV")
        #expect(info.duration == 1 && info.frameRate == 5)
        #expect(info.width == 160 && info.height == 90 && info.codec == "avc1")
        #expect(info.creationDate == "2026:11:23 08:00:00+08:00" && info.model == "TestCam")
        #expect(item.metadata.location?.latitude == 12.5 && item.metadata.location?.longitude == 34.25)
        #expect(ImageData(from: photo).metadataInspectionURL == xmp)
        #expect(try files.map { try Data(contentsOf: $0) } == before)
    }

    @Test func plainVideoAndAudioOnlyContainer() throws {
        let item = ImageData(from: try fixture("plain", "mp4"))
        let info = try #require(item.videoInfo)
        #expect(info.width == 160 && info.height == 90)
        #expect(info.containerDate == nil && info.creationDate == nil && info.location == nil)
        #expect(item.supportsMetadataEditing(.captureDate))
        let audio = ImageData(from: try fixture("audio", "mp4"))
        #expect(audio.videoInfo == nil && !audio.metadata.readable && !audio.updatable)
    }

    @Test func photoWithVideoSuffixIsRejected() throws {
        let fake = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        try FileManager.default.copyItem(at: #require(Bundle.module.url(forResource: "alldata", withExtension: "jpg")), to: fake)
        defer { try? FileManager.default.removeItem(at: fake) }
        let item = ImageData(from: fake)
        #expect(item.videoInfo == nil && !item.metadata.readable && !item.updatable)
    }
}

extension VideoReadTests {
    @Test func mixedLocationsAndLensUsePerRuleTargets() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let backup = folder.appendingPathComponent("backups")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var readings: [(image: ImageData, snapshot: MetadataInspectionSnapshot)] = []
        let tags: Set<MetadataTag> = [.captureLocation, .lens, .captureDate]
        for index in 0..<10 {
            let source = try index < 8 ? #require(Bundle.module.url(forResource: "alldata", withExtension: "jpg"))
                : fixture(index == 8 ? "tagged" : "plain", index == 8 ? "mov" : "mp4")
            let url = folder.appendingPathComponent("\(index)." + source.pathExtension)
            try FileManager.default.copyItem(at: source, to: url)
            readings.append((ImageData(from: url), try MetadataInspectionSnapshot.read(tags, from: url)))
        }
        let target = "-12.375 34.54321"
        let ops = [MetadataOperation(tag: .captureLocation, action: .setText(target)),
                   MetadataOperation(tag: .lens, action: .setText("Test lens"), photosOnly: true),
                   MetadataOperation(tag: .captureDate, action: .setText("2026:11:23 14:30:00+08:00"))]
        let preview = try MetadataWorkflowPreview.prepare(readings, operations: ops)
        #expect(preview.items.count == 10 && preview.skipDetails.count == 2)
        for (reading, item) in zip(readings, preview.items) {
            let original = try Data(contentsOf: item.target)
            var draft = reading.image
            draft.applyMetadataDraft(item)
            #expect(draft.metadata.location?.latitude == -12.375 && !draft.hasLegacyChanges)
            #expect(item.changes.count == (draft.isLocalMovie ? 2 : 3))
            #expect(await item.save(backup: .folder(backup)) == .saved)
            #expect(try Data(contentsOf: backup.appendingPathComponent(item.target.lastPathComponent)) == original)
            let reopened = ImageData(from: item.target)
            #expect(abs((reopened.metadata.location?.longitude ?? 0) - 34.54321) < 0.000002)
            let values = try Exiftool.helper.metadataTags(tags, from: item.target)
            #expect(values[.captureDate] == .text("2026:11:23 14:30:00+08:00"))
            #expect(values[.lens] == (draft.isLocalMovie ? nil : .text("Test lens")))
        }
    }

    @Test func videoDraftRejectsChangedSource() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        try FileManager.default.copyItem(at: fixture("plain", "mp4"), to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let image = ImageData(from: file)
        let snapshot = try MetadataInspectionSnapshot.read([.captureLocation], from: file)
        let plan = try MetadataWorkflowPreview.prepare([(image, snapshot)], operations: [
            MetadataOperation(tag: .captureLocation, action: .setText("1, 2"))])
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: file.path)
        let item = try #require(plan.items.first)
        #expect(await item.save(backup: .disabled) == .staleSource)
        #expect(ImageData(from: file).metadata.location == nil)
    }
}

extension VideoReadTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PHOTOTRAIL_TIMED_GPS_FIXTURE"] != nil))
    func deviceMovieKeepsTimedLocationsOnSave() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["PHOTOTRAIL_TIMED_GPS_FIXTURE"])
        let source = URL(fileURLWithPath: path)
        let file = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + source.pathExtension)
        try FileManager.default.copyItem(at: source, to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let points = try Exiftool.helper.timedVideoLocations(from: file)
        #expect(points.count > 1)
        let image = ImageData(from: file)
        let snapshot = try MetadataInspectionSnapshot.read(Set(movieOperations.map(\.tag) + [.captureLocation]), from: file)
        let result = try MetadataWorkflowPreview.prepare([(image, snapshot)], operations: [
            MetadataOperation(tag: .captureLocation, action: .setText("12.5, 34.25"))] + movieOperations)
        let item = try #require(result.items.first)
        #expect(await item.save(backup: .disabled) == .saved)
        let after = try Exiftool.helper.timedVideoLocations(from: file)
        #expect(points.map(\.seconds) == after.map(\.seconds))
        #expect(points.map(\.location) == after.map(\.location))
        #expect(points.map(\.gpsDate) == after.map(\.gpsDate))
        #expect(ImageData(from: file).metadata.location?.longitude == 34.25)
        try keepVerificationCopy(file, named: source.lastPathComponent)
    }
}

extension VideoReadTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PHOTOTRAIL_LIVE_MOV_FIXTURE"] != nil))
    func companionMovieKeepsItsIdentifierOnSave() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["PHOTOTRAIL_LIVE_MOV_FIXTURE"])
        let file = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let tag = "Keys:ContentIdentifier"
        let identifier = try #require(Exiftool.helper.inspectionTags(from: file)[tag])
        let image = ImageData(from: file)
        #expect(image.videoInfo?.hasContentIdentifier == true)
        let snapshot = try MetadataInspectionSnapshot.read(Set(movieOperations.map(\.tag) + [.captureLocation]), from: file)
        let preview = try MetadataWorkflowPreview.prepare([(image, snapshot)], operations: [
            .init(tag: .captureLocation, action: .setText("-10, -34"))] + movieOperations)
        let item = try #require(preview.items.first)
        #expect(await item.save(backup: .disabled) == .saved)
        #expect(try Exiftool.helper.inspectionTags(from: file)[tag] == identifier)
        #expect(ImageData(from: file).metadata.location?.longitude == -34)
        try keepVerificationCopy(file, named: URL(fileURLWithPath: path).lastPathComponent)
    }

    private func keepVerificationCopy(_ file: URL, named name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["PHOTOTRAIL_VIDEO_PROOF_DIRECTORY"] else { return }
        try FileManager.default.copyItem(at: file, to: URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent(name))
    }

    @Test func settingSidecarLocationPreservesSameStemMovieAndImage() throws {
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let photo = folder.appendingPathComponent("same.jpg")
        let video = folder.appendingPathComponent("same.mov")
        let sidecar = folder.appendingPathComponent("same.xmp")
        try FileManager.default.copyItem(at: #require(Bundle.module.url(forResource: "alldata", withExtension: "jpg")), to: photo)
        try FileManager.default.copyItem(at: fixture("tagged", "mov"), to: video)
        try FileManager.default.copyItem(at: #require(Bundle.module.url(forResource: "262M1559", withExtension: "xmp")), to: sidecar)
        let original = try [photo, video].map { try Data(contentsOf: $0) }
        #expect(ImageData(from: photo).metadataInspectionURL == sidecar)
        let values = try Exiftool.helper.update(image: sidecar, changes: [.captureLocation: .set(.text("-12.25, -54.5"))])
        #expect(MetadataTag.captureLocation.matches(values[.captureLocation], .text("-12.25 -54.5")))
        let cleared = try Exiftool.helper.update(image: sidecar, changes: [.captureLocation: .remove])
        #expect(cleared[.captureLocation] == nil)
        #expect(try [photo, video].map { try Data(contentsOf: $0) } == original)
    }
}

extension VideoReadTests {
    private var movieOperations: [MetadataOperation] {
        [.init(tag: .captureDate, action: .setText("2024:12:31 23:59:58.123+08:00")),
         .init(tag: .titleDefault, action: .setText("海边")),
         .init(tag: .descriptionDefault, action: .setText("第一行\n第二行")),
         .init(tag: .rightsDefault, action: .setText("© 六九")),
         .init(tag: .creator, action: .replaceAuthors(["甲,乙", "六九"])),
         .init(tag: .subject, action: .replaceKeywords(["海边", "A; B"])),
         .init(tag: .make, action: .setText("品牌")),
         .init(tag: .model, action: .setText("设备")),
         .init(tag: .city, action: .setText("杭州")), .init(tag: .regionState, action: .setText("浙江")),
         .init(tag: .country, action: .setText("中国")), .init(tag: .lensMake, action: .setText("Lens maker")),
         .init(tag: .lens, action: .setText("Prime 35")), .init(tag: .rating, action: .setText("4")),
         .init(tag: .director, action: .setText("陈某")), .init(tag: .producer, action: .setText("赵某"))]
    }

    @Test(arguments: ["mov", "mp4"]) func editableMovieFieldsRoundTripAndClear(ext: String) async throws {
        let source = try fixture(ext == "mov" ? "tagged" : "plain", ext)
        let file = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
        try FileManager.default.copyItem(at: source, to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let tags = Set(movieOperations.map(\.tag))
        let before = try Exiftool.helper.quickTimeVideoInfo(from: file)
        let snapshot = try MetadataInspectionSnapshot.read(tags, from: file)
        let preview = try MetadataWorkflowPreview.prepare([(ImageData(from: file), snapshot)], operations: movieOperations)
        let item = try #require(preview.items.first)
        #expect(await item.save(backup: .disabled) == .saved)
        let info = try Exiftool.helper.quickTimeVideoInfo(from: file)
        for (tag, change) in item.changes {
            if case .set(let expected) = change { #expect(tag.matches(info.editableValues[tag], expected)) }
        }
        #expect(info.containerDate == before.containerDate && info.duration == before.duration && info.location == before.location)
        let newSnapshot = try MetadataInspectionSnapshot.read(tags, from: file)
        let bad = try MetadataWorkflowPreview.prepare([(ImageData(from: file), newSnapshot)], operations: [
            .init(tag: .captureDate, action: .setText("2024:01:10 12:00:00"))])
        #expect(bad.items.isEmpty && bad.skipDetails.first?.reason == .missingVideoTimeZone)
        let clear = try MetadataWorkflowPreview.prepare([(ImageData(from: file), newSnapshot)],
            operations: tags.map { .init(tag: $0, action: .remove) })
        let removal = try #require(clear.items.first)
        #expect(await removal.save(backup: .disabled) == .saved)
        #expect(try Exiftool.helper.metadataTags(tags, from: file).isEmpty)
    }
}

extension VideoReadTests {
    @Test func nativeAuthorsAndLocalizedTitlesSurviveEditing() async throws {
        let file = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        try FileManager.default.copyItem(at: fixture("tagged", "mov"), to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        try Exiftool.helper.run(["-overwrite_original", "-Keys:Author=Original", "-Keys:Title-und=Hello", "-Keys:Title-fra=Bonjour", file.path])
        let tags: Set<MetadataTag> = [.titleDefault, .creator, .model]
        let before = try MetadataInspectionSnapshot.read(tags, from: file)
        #expect(before.values[.creator] == .list(["Original"]))
        let edit = try MetadataWorkflowPreview.prepare([(ImageData(from: file), before)], operations: [
            .init(tag: .titleDefault, action: .setText("123")), .init(tag: .model, action: .setText("007")),
            .init(tag: .creator, action: .replaceAuthors(["New", "Other"]))])
        let item = try #require(edit.items.first)
        #expect(await item.save(backup: .disabled) == .saved)
        let after = try MetadataInspectionSnapshot.read(tags, from: file)
        #expect(after.values[.creator] == .list(["New", "Other"]) && after.values[.titleDefault] == .text("123") && after.values[.model] == .text("007"))
        let localized = try Exiftool.helper.run(["-s3", "-Keys:Title-fra", file.path])
        #expect(String(decoding: localized, as: UTF8.self).trimmingCharacters(in: .newlines) == "Bonjour")
        let remove = try MetadataWorkflowPreview.prepare([(ImageData(from: file), after)], operations: [
            .init(tag: .titleDefault, action: .remove), .init(tag: .creator, action: .remove)])
        #expect(remove.skipDetails.first?.reason == .localizedMovieField)
        let removal = try #require(remove.items.first)
        #expect(await removal.save(backup: .disabled) == .saved)
        #expect(try Exiftool.helper.metadataTags([.creator], from: file).isEmpty)
    }
}

extension VideoReadTests {
    @Test func mixedCityAndDirectorCountsAndDiskValues() async throws {
        let parent = ProcessInfo.processInfo.environment["PHOTOTRAIL_CATALOG_TEST_DIRECTORY"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? URL.temporaryDirectory
        let folder = parent.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let tags: Set<MetadataTag> = [.city, .director]
        let operations = [MetadataOperation(tag: .city, action: .setText("杭州")),
                          MetadataOperation(tag: .director, action: .setText("陈某"))]
        var urls = [URL]()
        for index in 0..<10 {
            let src = try index < 8 ? #require(Bundle.module.url(forResource: "alldata", withExtension: "jpg"))
                : fixture(index == 8 ? "tagged" : "plain", index == 8 ? "mov" : "mp4")
            let url = folder.appendingPathComponent("\(index)." + src.pathExtension)
            try FileManager.default.copyItem(at: src, to: url)
            urls.append(url)
        }
        func preview() throws -> MetadataWorkflowPreview {
            let readings = try urls.map { (ImageData(from: $0), try MetadataInspectionSnapshot.read(tags, from: $0)) }
            return try MetadataWorkflowPreview.prepare(readings, operations: operations)
        }
        let changes = try preview()
        #expect(changes.items.count == 10)
        #expect(changes.operationResults.map { $0.changed.count } == [10, 2])
        #expect(changes.operationResults.map { $0.skipped.count } == [0, 8])
        for item in changes.items {
            var pending = ImageData(from: item.target)
            pending.applyMetadataDraft(item)
            #expect(pending.metadata.city == "杭州" && !pending.hasLegacyChanges)
            #expect(await item.save(backup: .disabled) == .saved)
            #expect(ImageData(from: item.target).metadata.city == "杭州")
            let reopened = try Exiftool.helper.metadataTags(tags, from: item.target)
            #expect(reopened[.city] == .text("杭州"))
            #expect(reopened[.director] == (QuickTimeVideoInfo.acceptsExtension(item.target) ? .text("陈某") : nil))
        }
        let unchanged = try preview()
        #expect(unchanged.items.isEmpty && unchanged.operationResults.map { $0.unchanged.count } == [10, 2])
    }

    @Test(arguments: ["jpg", "heic", "xmp"])
    func catalogFieldsInPhotoFormats(ext: String) throws {
        let stem = ["jpg": "alldata", "heic": "blank", "xmp": "262M1559"][ext]!
        let source = try #require(Bundle.module.url(forResource: stem, withExtension: ext))
        let file = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
        try FileManager.default.copyItem(at: source, to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let fields: [MetadataTag: String] = [.city: "杭州", .regionState: "浙江", .country: "中国",
            .lensMake: "Maker", .lens: "35 mm", .rating: "4"]
        let sets = fields.mapValues { MetadataTagChange.set(.text($0)) }
        let written = try Exiftool.helper.update(image: file, changes: sets)
        #expect(written == fields.mapValues { .text($0) })
        #expect(throws: Exiftool.ExiftoolError.self) {
            try Exiftool.helper.update(image: file, changes: [.director: .set(.text("no"))])
        }
        _ = try Exiftool.helper.update(image: file, changes: fields.mapValues { _ in .remove })
        #expect(try Exiftool.helper.metadataTags(Set(fields.keys), from: file).isEmpty)
    }
}

extension VideoReadTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PHOTOTRAIL_LARGE_MOVIE_FIXTURE"] != nil))
    func catalogSaveInLargeContainer() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["PHOTOTRAIL_LARGE_MOVIE_FIXTURE"])
        let source = URL(fileURLWithPath: path)
        let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize
        #expect((size ?? 0) > Int(UInt32.max))
        let file = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + source.pathExtension)
        try FileManager.default.copyItem(at: source, to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let image = ImageData(from: file)
        let tags: Set<MetadataTag> = [.city, .director]
        let snapshot = try MetadataInspectionSnapshot.read(tags, from: file)
        let changes = try MetadataWorkflowPreview.prepare([(image, snapshot)], operations: [
            .init(tag: .city, action: .setText("杭州")), .init(tag: .director, action: .setText("Chen"))
        ])
        let item = try #require(changes.items.first)
        #expect(await item.save(backup: .disabled) == .saved)
        let reopened = try Exiftool.helper.quickTimeVideoInfo(from: file)
        #expect(reopened.editableValues[.director] == .text("Chen") && reopened.editableValues[.city] == .text("杭州"))
        #expect(reopened.duration == image.videoInfo?.duration)
    }
}
