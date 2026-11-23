import Coords
import Exiftool
import Foundation
import Imagetool
import Metadata
import OSLog
import PhotosUI
import Phototool
import SwiftUI

private extension MetadataTag {
    var catalogRegionKey: WritableKeyPath<Metadata, String?>? {
        switch self {
        case .city: \.city
        case .regionState: \.state
        case .country: \.country
        default: nil
        }
    }
}

public extension Metadata {
    mutating func applyCatalogRegions(_ changes: [MetadataTag: MetadataTagChange]) {
        for (tag, change) in changes {
            guard let key = tag.catalogRegionKey else { continue }
            let value: String?
            switch change {
            case .set(.text(let text)): value = text
            case .remove: value = nil
            default: continue
            }
            self[keyPath: key] = value
        }
    }
}

public struct ImageData: Identifiable, Sendable {
    public let id: Int
    public private(set) var name: String
    public var metadata: Metadata
    public private(set) var videoInfo: QuickTimeVideoInfo?
    public var isLocalMovie: Bool {
        guard case .image(let url) = metadata.source else { return false }
        return QuickTimeVideoInfo.acceptsExtension(url)
    }
    public private(set) var metadataTargetWritable = true
    public private(set) var movieVersion: MetadataInspectionFileVersion?
    public mutating func supersedeMovieLocationDraft() {
        guard isLocalMovie, var draft = creatorDraft, draft.changes.removeValue(forKey: .captureLocation) != nil else { return }
        creatorDraft = draft.changes.isEmpty ? nil : draft
    }

    public mutating func restoreCatalogDraft() {
        guard let draft = creatorDraft else { return }
        for key in draft.changes.keys.compactMap(\.catalogRegionKey) {
            metadata[keyPath: key] = original?[keyPath: key]
        }
    }

    public mutating func finishMetadataSave(_ changes: [MetadataTag: MetadataTagChange]) {
        metadata.applyCatalogRegions(changes)
        original?.applyCatalogRegions(changes)
        videoInfo?.applySavedChanges(changes)
        refreshMovieVersion()
    }

    public mutating func refreshMovieVersion() {
        if isLocalMovie { movieVersion = MetadataInspectionFileVersion.read(metadataCreatorImageURL) }
    }

    public var original: Metadata?
    public var creatorDraft: MetadataCreatorEditPlan.Item?
    public var pairedID: ImageData.ID?
    public var thumbnail: Image?
    public var fileRenameRecoveryRequired = false

    // a copy of the metadata before any changes will only exist if
    // the metadata is updatable. Use it's presence to determine
    // if this instance can be updated.

    public var updatable: Bool {
        original != nil && !fileRenameRecoveryRequired
    }

    public var hasPendingChanges: Bool {
        updatable && (metadata != original || creatorDraft?.changes.isEmpty == false)
    }

    // File operations keep the stable photo ID, selection and pairing. Drafts must be saved/discarded first.
    public mutating func applyFileRenames(_ mappings: [URL: URL]) {
        guard !hasPendingChanges, let source = metadataCreatorImageURL,
              let target = mappings[source.standardizedFileURL] else { return }
        let newSource: MetadataSource
        switch metadata.source {
        case .image: newSource = .image(target)
        case .xmp: newSource = .xmp(target)
        case .photos, .copy: return
        }
        let wasSidecar = name.hasSuffix("*")
        metadata = Metadata(converting: metadata, to: newSource)
        if let baseline = original { original = Metadata(converting: baseline, to: newSource) }
        refreshMovieVersion()
        name = target.lastPathComponent + (wasSidecar ? "*" : "")
    }

    // The effective shooting date is projected into the existing map/track model.
    // Do not route that projection through the legacy writer a second time.
    public mutating func applyMetadataDraft(_ item: MetadataCreatorEditPlan.Item) {
        if let change = item.changes[.captureLocation] {
            metadata.location = change.coordinate
            metadata.gpsMapDatum = metadata.location == nil ? original?.gpsMapDatum : "WGS-84"
        }
        restoreCatalogDraft()
        metadata.applyCatalogRegions(item.changes)
        creatorDraft = item.changes.isEmpty ? nil : item
        if item.captureDateChange != nil { metadata.dateTimeCreated = item.captureDateValue }
    }

    public var hasLegacyChanges: Bool {
        guard updatable else { return false }
        var comparison = metadata
        if let draft = creatorDraft, draft.captureDateChange != nil,
           metadata.dateTimeCreated == draft.captureDateValue {
            comparison.dateTimeCreated = original?.dateTimeCreated
        }
        if let change = creatorDraft?.changes[.captureLocation], metadata.location == change.coordinate {
            comparison.location = original?.location
            comparison.gpsMapDatum = original?.gpsMapDatum
        }
        if let changes = creatorDraft?.changes {
            for key in changes.keys.compactMap(\.catalogRegionKey) {
                comparison[keyPath: key] = original?[keyPath: key]
            }
        }
        return comparison != original
    }

    public var hasLegacyDateChanges: Bool {
        guard updatable else { return false }
        if let draft = creatorDraft, draft.captureDateChange != nil {
            return metadata.dateTimeCreated != draft.captureDateValue
        }
        return metadata.dateTimeCreated != original?.dateTimeCreated
    }

    // init given a Metadata and a String name.

    public init(metadata: Metadata, name: String) {
        id = ImageData.nextId()
        self.name = name
        self.metadata = metadata
        switch metadata.source {
        case .image(let url):
            if metadata.readable && !QuickTimeVideoInfo.acceptsExtension(url) &&
               url.pathExtension.lowercased() != xmpExtension &&
               Exiftool.helper.fileTypeIsWritable(for: url) {
                original = Metadata(copying: metadata)
            }
        case .xmp(let url):
            if !QuickTimeVideoInfo.acceptsExtension(url) { original = Metadata(copying: metadata) }
        case .photos(_, let assets):
            if assets != nil {
                original = Metadata(copying: metadata)
            }
        default:
            break
        }
    }

    // init given a URL. A URL to the image or, if present, a sidecar
    // file url will be used to create a Metadata initialized from
    // the data in the image then initialize an ImageData with
    // metadata and name.

    public init(from url: URL) {
        let interval = Self.markStart(#function)
        defer {
            Self.markEnd(#function, interval: interval)
        }
        if QuickTimeVideoInfo.acceptsExtension(url) {
            var metadata = Metadata(source: .image(url))
            let version = MetadataInspectionFileVersion.read(url)
            let read = Imagetool.readVideoInfo(from: url)
            let info = version == MetadataInspectionFileVersion.read(url) ? read : nil
            metadata.readable = info != nil
            metadata.applyCatalogRegions((info?.editableValues ?? [:]).mapValues { .set($0) })
            metadata.location = info?.location
            metadata.gpsMapDatum = info?.location == nil ? nil : "WGS-84"
            metadata.dateTimeCreated = info?.zonedCreationDate
            self.init(metadata: metadata, name: url.lastPathComponent)
            videoInfo = info
            metadataTargetWritable = FileManager.default.isWritableFile(atPath: url.path)
            if info != nil && metadataTargetWritable {
                original = Metadata(copying: metadata)
                movieVersion = version
            }
            return
        }
        let sidecarURL = url.deletingPathExtension()
            .appendingPathExtension(xmpExtension)
        let hasSidecar = url != sidecarURL &&
            FileManager.default.fileExists(atPath: sidecarURL.path)
        let name = url.lastPathComponent + (hasSidecar ? "*" : "")

        var metadata: Metadata
        if hasSidecar {
            metadata = Imagetool.metadata(from: url, xmp: sidecarURL)
        } else {
            metadata = Imagetool.metadata(from: url)
        }
        self.init(metadata: metadata, name: name)
        metadataTargetWritable = FileManager.default.isWritableFile(atPath: (hasSidecar ? sidecarURL : url).path)
    }

    // init given a PhotosPickerItem and an asset

    public init(from item: PhotosPickerItem, asset: PHAsset?) {
        let name = Phototool.name(from: asset)
        let metadata = Phototool.metadata(from: item, asset: asset)
        self.init(metadata: metadata, name: name)
    }

    // fake data synthesized to allow lookup of images by an ID
    // that no longer exists.

    public init() {
        let fakeURL = URL(string: "file:///unknown.img")!
        let fakeName = "unknown.img"
        var metadata = Metadata(source: .image(fakeURL))
        metadata.readable = false // Placeholder data must not launch ExifTool while drawing an empty UI.
        self.init(metadata: metadata, name: fakeName)
    }
}

extension ImageData {
    static let id = Bundle.main.bundleIdentifier ?? "ImageData"
    static let logger = Logger(subsystem: id, category: "ImageData")
    static let signposter = OSSignposter(logger: logger)

    static func markStart(_ desc: StaticString) -> OSSignpostIntervalState {
        let signpostID = Self.signposter.makeSignpostID()
        let interval = Self.signposter.beginInterval(desc, id: signpostID)
        return interval
    }

    static func markEnd(_ desc: StaticString, interval: OSSignpostIntervalState) {
        Self.signposter.endInterval(desc, interval)
    }
}

extension ImageData: Equatable {}

extension ImageData: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// The full path to the image for display only. A fake path is created
// for images in a Photos library.

extension ImageData {
    public var fullPath: String {
        switch metadata.source {
        case let .image(url):
            return url.path
        case let .xmp(url):
            return url.path
        case .photos:
            return "photos://\(name)"
        case .copy:
            Self.logger.error("Requested fullPath of metadata copy")
            return "unknown"
        }
    }
}
