import CoreLocation
import Foundation
import ImageData
import Metadata
import Photos
import Phototool
import SwiftUI

struct SaveTargets {
    var library: [Int] = []
    var files: [Int] = []
    var xmp: [Int] = []

    init(images: [ImageData]) {
        for index in images.indices {
            let image = images[index]
            guard image.updatable, image.metadata != image.original else { continue }
            switch image.metadata.source {
            case .photos: library.append(index)
            case .image: files.append(index)
            case .xmp: xmp.append(index)
            case .copy: break
            }
        }
    }

    var total: Int { library.count + files.count + xmp.count }
}

extension GeoTagReducer {

    // save the indices of all updatable images that have changed.
    // The save process continues in a future step.

    func save(_ state: inout GeoTagState) {
        state.saveInProgress = true
        let targets = SaveTargets(images: state.imageData)
        state.libraryImages = targets.library
        state.fileImages = targets.files
        state.xmpImages = targets.xmp
        state.saveCompleted = 0
        state.saveTotal = targets.total
    }

    func discardChanges(_ state: inout GeoTagState) {
        for ix in state.imageData.indices {
            if let original = state.imageData[ix].original {
                if state.imageData[ix].metadata != original {
                    state.imageData[ix].metadata.restore(from: original)
                }
            }
        }
        state.unsavedChanges = false
    }

    func clearImages(_ state: inout GeoTagState) {
        state.mostSelected = nil
        state.selection = []
        for url in state.scopedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        state.scopedURLs = []
        state.imageData = []
        state.pairingEligibleIDs = nil
        state.locationSavedPhotoIDs = []
    }
}
