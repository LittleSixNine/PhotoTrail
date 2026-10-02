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
        var targets: [String: Int] = [:]
        for index in images.indices {
            let image = images[index]
            guard image.updatable else { continue }
            let metadataChanged = image.hasLegacyChanges
            let creatorChanged = image.creatorDraft?.changes.isEmpty == false
            if metadataChanged || creatorChanged, let url = image.metadataInspectionURL {
                let key: String
                if case .file(let device, let inode, _, _, _, _, _) = MetadataInspectionFileVersion.read(url) {
                    key = "\(device):\(inode)"
                } else {
                    key = url.standardizedFileURL.path
                }
                if let previous = targets[key] {
                    conflicts.append(contentsOf: [previous, index])
                } else {
                    targets[key] = index
                }
            }
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

    func clearCreatorDraft(_ state: inout PhotoTrailState, id: ImageData.ID, discard: Bool) {
        guard state.imageData.contains(where: { $0.id == id }) else { return }
        if state[id].creatorDraft?.captureDateChange != nil {
            if discard { state[id].metadata.dateTimeCreated = state[id].original?.dateTimeCreated }
            else {
                let savedDate = state[id].metadata.dateTimeCreated
                state[id].original?.dateTimeCreated = savedDate
            }
        }
        state[id].creatorDraft = nil
        if discard {
            state.creatorSaveResults[id] = nil
            state.unsavedChanges = state.imageData.contains { $0.hasPendingChanges }
        }
    }

    // save the indices of all updatable images that have changed.
    // The save process continues in a future step.

    func save(_ state: inout PhotoTrailState) {
        state.saveInProgress = true
        state.metadataSaveCancelled = false
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
