import Foundation
import ImageData
import OSLog
import SwiftUI
import UDF

// Link JPG and RAW files with the same path stem. Both remain in imageData
// so saving can update both files; only the JPG is presented in the UI.

extension ImageData {
    var isJPEG: Bool {
        switch metadata.source {
        case .image(let url), .xmp(let url):
            return ["jpg", "jpeg"].contains(url.pathExtension.lowercased())
        default:
            return false
        }
    }

    var isPairedJPEG: Bool { isJPEG && pairedID != nil && !isLivePhotoPair }
}

extension PhotoTrailState {
    var visibleImages: [ImageData] {
        imageData.filter { $0.pairedID == nil || ($0.isLivePhotoPair ? !$0.isLocalMovie : $0.isJPEG) }
    }

    func members(of selection: Set<ImageData.ID>) -> [ImageData] {
        imageData.filter { selection.contains($0.id) || ($0.isLivePhotoPair && selection.contains($0.livePhotoAssetID)) }
    }

    mutating func linkLivePhotos() {
        struct GroupKey: Hashable { let folder: URL; let identifier: String }
        var groups: [GroupKey: [Int]] = [:]
        for i in imageData.indices {
            guard let identifier = imageData[i].livePhotoIdentifier,
                  let url = imageData[i].metadataCreatorImageURL else { continue }
            let key = GroupKey(folder: url.standardizedFileURL.deletingLastPathComponent(), identifier: identifier)
            groups[key, default: []].append(i)
        }
        for indices in groups.values {
            let stills = indices.filter { !imageData[$0].isLocalMovie }
            let movies = indices.filter { imageData[$0].isLocalMovie }
            let ambiguous = stills.count > 1 || movies.count > 1
            for i in indices {
                imageData[i].livePhotoAmbiguous = ambiguous
                if ambiguous && imageData[i].isLivePhotoPair {
                    imageData[i].pairedID = nil
                    imageData[i].isLivePhotoPair = false
                    imageData[i].livePairReadOnly = false
                }
            }
            guard !ambiguous, let still = stills.first, let movie = movies.first,
                  [still, movie].allSatisfy({ imageData[$0].pairedID == nil && !imageData[$0].hasPendingChanges }) else { continue }
            let stillID = imageData[still].id, movieID = imageData[movie].id
            let readOnly = [still, movie].contains { i in
                let image = imageData[i]
                return !image.updatable || !image.metadataTargetWritable || image.metadataInspectionURL != image.metadataCreatorImageURL
            }
            imageData[still].livePairReadOnly = readOnly; imageData[movie].livePairReadOnly = readOnly
            imageData[still].pairedID = movieID; imageData[movie].pairedID = stillID
            imageData[still].isLivePhotoPair = true; imageData[movie].isLivePhotoPair = true
            if selection.remove(movieID) != nil { selection.insert(stillID) }
            if mostSelected == movieID { mostSelected = stillID }
        }
    }

    mutating func linkPairedImages() {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PhotoTrail",
                            category: "PhotoTrailState")
        let rawExtensions: Set<String> = [
            "3fr", "arw", "cr2", "cr3", "dng", "erf", "fff", "iiq", "kdc", "mef",
            "mos", "mrw", "nef", "nrw", "orf", "pef", "raf", "raw", "rwl", "rw2",
            "srw", "x3f"
        ]

        var rawByBase: [String: Int] = [:]
        for index in imageData.indices {
            guard let url = imageData[index].metadataCreatorImageURL,
                  rawExtensions.contains(url.pathExtension.lowercased()) else { continue }
            let base = url.deletingPathExtension().path
            if rawByBase[base] == nil { rawByBase[base] = index }
        }
        guard !rawByBase.isEmpty else { return }

        for index in imageData.indices {
            let jpeg = imageData[index]
            guard jpeg.pairedID == nil, jpeg.livePhotoIdentifier == nil, jpeg.isJPEG, let url = jpeg.metadataCreatorImageURL,
                  let rawIndex = rawByBase[url.deletingPathExtension().path] else { continue }
            let raw = imageData[rawIndex]
            guard raw.pairedID == nil,
                  pairingEligibleIDs.map({ $0.contains(jpeg.id) && $0.contains(raw.id) }) ?? true else { continue }
            let rawName = raw.metadataCreatorImageURL?.lastPathComponent ?? raw.name
            logger.notice("Pairing \(url.lastPathComponent, privacy: .public) <> \(rawName, privacy: .public)")
            imageData[index].pairedID = raw.id
            imageData[rawIndex].pairedID = jpeg.id
            if selection.remove(raw.id) != nil { selection.insert(jpeg.id) }
            if mostSelected == raw.id { mostSelected = jpeg.id }
        }
    }
}
