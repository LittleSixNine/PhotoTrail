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

    var isPairedJPEG: Bool { isJPEG && pairedID != nil }
}

extension PhotoTrailState {
    var visibleImages: [ImageData] {
        imageData.filter { $0.pairedID == nil || $0.isJPEG }
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
            guard jpeg.pairedID == nil, jpeg.isJPEG, let url = jpeg.metadataCreatorImageURL,
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
