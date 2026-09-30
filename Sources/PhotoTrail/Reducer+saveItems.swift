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
    var creator: [Int] = []
    var creatorFiles = 0
    var conflicts: [Int] = []

    init(images: [ImageData]) {
        for index in images.indices {
            let image = images[index]
            guard image.updatable else { continue }
            let metadataChanged = image.metadata != image.original
            let creatorChanged = image.creatorDraft?.change != nil
            if metadataChanged && creatorChanged {
                conflicts.append(index)
                continue
            }
            if creatorChanged {
                creator.append(index)
                if case .image = image.metadata.source { creatorFiles += 1 }
                continue
            }
            guard metadataChanged else { continue }
            switch image.metadata.source {
            case .photos: library.append(index)
            case .image: files.append(index)
            case .xmp: xmp.append(index)
            case .copy: break
            }
        }
    }

    var total: Int { library.count + files.count + xmp.count + creator.count }
}

extension PhotoTrailReducer {

    // save the indices of all updatable images that have changed.
    // The save process continues in a future step.

    func save(_ state: inout PhotoTrailState) {
        state.saveInProgress = true
        let targets = SaveTargets(images: state.imageData)
        state.libraryImages = targets.library
        state.fileImages = targets.files
        state.xmpImages = targets.xmp
        state.creatorImages = targets.creator
        state.saveCompleted = 0
        state.saveTotal = targets.total
    }

    func discardChanges(_ state: inout PhotoTrailState) {
        for ix in state.imageData.indices {
            if let original = state.imageData[ix].original {
                if state.imageData[ix].metadata != original {
                    state.imageData[ix].metadata.restore(from: original)
                }
            }
            state.imageData[ix].creatorDraft = nil
        }
        state.creatorSaveResults = [:]
        state.unsavedChanges = false
    }

    func clearImages(_ state: inout PhotoTrailState) {
        state.mostSelected = nil
        state.selection = []
        for url in state.scopedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        state.scopedURLs = []
        state.imageData = []
        state.pairingEligibleIDs = nil
        state.locationSavedPhotoIDs = []
        state.creatorSaveResults = [:]
    }
}
