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

extension GeoTagState {
    var visibleImages: [ImageData] {
        imageData.filter { $0.pairedID == nil || $0.isJPEG }
    }

    mutating func linkPairedImages() {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "GeoTag",
                            category: "GeoTagState")
        let rawExtensions: Set<String> = [
            "3fr", "arw", "cr2", "cr3", "dng", "erf", "fff", "iiq", "kdc", "mef",
            "mos", "mrw", "nef", "nrw", "orf", "pef", "raf", "raw", "rwl", "rw2",
            "srw", "x3f"
        ]

        struct URLBase {
            let id: ImageData.ID
            let url: URL
            let base: String
        }

        let jpegBase =
            imageData.compactMap {
                if case let .image(url) = $0.metadata.source  {
                    let ext = url.pathExtension.lowercased()
                    if ext == "jpg" || ext == "jpeg" {
                        return URLBase(id: $0.id,
                                       url: url,
                                       base: url.deletingPathExtension().path)
                    }
                } else if case let .xmp(url) = $0.metadata.source, $0.isJPEG {
                    return URLBase(id: $0.id, url: url, base: url.deletingPathExtension().path)
                }
                return nil
            }
        let rawBase =
            imageData.compactMap {
                if case .image(let url) = $0.metadata.source  {
                    let ext = url.pathExtension.lowercased()
                    if rawExtensions.contains(ext) {
                        return URLBase(id: $0.id,
                                       url: url,
                                       base: url.deletingPathExtension().path)
                    }
                } else if case .xmp(let url) = $0.metadata.source,
                          rawExtensions.contains(url.pathExtension.lowercased()) {
                    return URLBase(id: $0.id, url: url, base: url.deletingPathExtension().path)
                }
                return nil
            }
        let rawByBase = Dictionary(rawBase.map { ($0.base, $0) }, uniquingKeysWith: { first, _ in first })

        for jpeg in jpegBase {
            if self[jpeg.id].pairedID == nil, let raw = rawByBase[jpeg.base],
               self[raw.id].pairedID == nil,
               pairingEligibleIDs.map({ $0.contains(jpeg.id) && $0.contains(raw.id) }) ?? true {
                logger.notice("""
                    Pairing \(jpeg.url.lastPathComponent, privacy: .public) \
                    <> \(raw.url.lastPathComponent, privacy: .public)"
                    """ )
                self[jpeg.id].pairedID = raw.id
                self[raw.id].pairedID = jpeg.id
                if selection.remove(raw.id) != nil { selection.insert(jpeg.id) }
                if mostSelected == raw.id { mostSelected = jpeg.id }
            }
        }
    }
}
