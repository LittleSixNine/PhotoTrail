import CoreLocation
import Exiftool
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
    var combined: [Int] = []
    var creatorFiles = 0
    private var editConflicts: [Int] = []
    private var changedFiles: [(index: Int, url: URL)] = []

    // File identities must be current when checking conflicts, including after a confirmation dialog.
    var conflicts: [Int] {
        var result = editConflicts
        guard changedFiles.count > 1 else { return result }
        var targets: [String: Int] = [:]
        for (index, url) in changedFiles {
            let key: String
            if case .file(let device, let inode, _, _, _, _, _) = MetadataInspectionFileVersion.read(url) {
                key = "\(device):\(inode)"
            } else {
                key = url.standardizedFileURL.path
            }
            if let previous = targets[key] {
                result.append(contentsOf: [previous, index])
            } else {
                targets[key] = index
            }
        }
        return result
    }

    init(images: [ImageData], scope: MetadataSaveScope = .all) {
        for index in images.indices {
            let image = images[index]
            guard image.updatable else { continue }
            let hasMap = image.hasLegacyChanges
            let hasFields = image.creatorDraft?.changes.isEmpty == false
            let metadataChanged = hasMap && scope != .metadata
            let creatorChanged = hasFields && scope != .map
            if hasMap || hasFields, let url = image.metadataInspectionURL {
                changedFiles.append((index, url))
            }
            if let change = image.creatorDraft?.changes[.captureLocation], change.coordinate != image.metadata.location {
                editConflicts.append(index)
                continue
            }
            if creatorChanged, image.creatorDraft?.captureDateChange != nil, image.hasLegacyDateChanges {
                editConflicts.append(index)
                continue
            }
            if hasMap && hasFields && (metadataChanged || creatorChanged) {
                // Map-only writes would invalidate the pending field snapshot; save both via All.
                if image.hasLegacyDateChanges || scope == .map {
                    editConflicts.append(index)
                    continue
                }
                if scope == .all { combined.append(index) }
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

    var enablesSaveButton: Bool {
        total > 0 || !editConflicts.isEmpty || !conflicts.isEmpty
    }
}

extension PhotoTrailReducer {

    func applyLocalSaveBatch(_ newState: inout PhotoTrailState, _ results: [SaveHelper.LocalSaveResult]) {
        for result in results {
            guard let index = newState.imageIndex(for: result.id) else { continue }
            if result.sidecarCreated, case .image = newState.imageData[index].metadata.source {
                newState.imageData[index].metadata = newState.imageData[index].metadata.xmp()
            }
            if let failure = result.failure {
                newState.saveFailures.append(newState.imageData[index].name + ": " + failure)
            }
            if result.outcome.metadataSaved {
                if newState.imageData[index].original?.location != result.metadata.location {
                    newState.locationSavedPhotoIDs.insert(result.id)
                }
                // Saving can resolve region fields that were not present in the editable snapshot.
                newState.imageData[index].metadata.restore(from: result.metadata)
                newState.imageData[index].original = Metadata(copying: result.metadata)
                if newState.imageData[index].isLocalMovie {
                    let change = result.metadata.location.map { MetadataTagChange.set(.text(CaptureLocationField.text($0))) } ?? .remove
                    newState.imageData[index].finishMetadataSave([.captureLocation: change])
                }
            }
        }
        newState.saveCompleted = min(newState.saveTotal, newState.saveCompleted + results.count)
    }

    func clearCreatorDraft(_ state: inout PhotoTrailState, id: ImageData.ID, discard: Bool) {
        guard let index = state.imageIndex(for: id) else { return }
        if state.imageData[index].creatorDraft?.captureDateChange != nil {
            if discard { state.imageData[index].metadata.dateTimeCreated = state.imageData[index].original?.dateTimeCreated }
            else {
                let savedDate = state.imageData[index].metadata.dateTimeCreated
                state.imageData[index].original?.dateTimeCreated = savedDate
            }
        }
        if state.imageData[index].creatorDraft?.changes[.captureLocation] != nil {
            if discard {
                state.imageData[index].metadata.location = state.imageData[index].original?.location
                state.imageData[index].metadata.gpsMapDatum = state.imageData[index].original?.gpsMapDatum
            } else {
                let snapshot = state.imageData[index].metadata
                state.imageData[index].original?.location = snapshot.location
                state.imageData[index].original?.gpsMapDatum = snapshot.gpsMapDatum

            }
        }
        if discard { state.imageData[index].restoreCatalogDraft() }
        if !discard, let changes = state.imageData[index].creatorDraft?.changes {
            state.imageData[index].finishMetadataSave(changes)
        }
        state.imageData[index].creatorDraft = nil
        if discard {
            state.creatorSaveResults[id] = nil
            state.unsavedChanges = state.imageData.contains { $0.hasPendingChanges }
        }
    }

    // save the indices of all updatable images that have changed.
    // The save process continues in a future step.

    func save(_ state: inout PhotoTrailState, scope: MetadataSaveScope = .all) {
        state.saveFailures = []
        state.saveInProgress = true
        state.metadataSaveCancelled = false
        let targets = SaveTargets(images: state.imageData, scope: scope)
        state.saveImageIndices = [:]
        for indices in [targets.library, targets.files, targets.xmp, targets.creator] {
            for index in indices { state.saveImageIndices[state.imageData[index].id] = index }
        }
        state.libraryImages = targets.library
        state.fileImages = targets.files
        state.xmpImages = targets.xmp
        state.creatorImages = targets.creator
        state.combinedImages = targets.combined
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
