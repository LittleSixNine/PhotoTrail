import AppKit
import Foundation
import ImageData
import Metadata
import OSLog
import UDF

// Update state given an event

struct PhotoTrailReducer: Reducer, Sendable {
    let logger =
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "PhotoTrail",
               category: "reducer")

    // swiftlint:disable:next function_body_length
    func reduce(_ state: PhotoTrailState,
                _ event: PhotoTrailEvent) -> PhotoTrailState {
        if state.saveInProgress || state.importProgress.isActive {
            switch event {
            case .addressChanged, .clearImagesRequest, .deleteRequest, .removeImages, .discardChangesRequest,
                 .creatorDraftApplied, .creatorDraftRemoved, .locationChanged, .applyTrackMatches,
                 .newTimestamp, .pasteRequest,
                 .placeSelection, .timeZoneChanged, .openCommand, .openFiles, .saveRequest:
                return state
            default: break
            }
        }
        var newState = state
        newState.version &+= 1
        switch event {
        case .saveProgress, .imageSaved, .localSaveBatch, .sidecarCreated, .creatorSaved, .creatorSaveResult: break
        default: newState.mapRevision &+= 1
        }
        // logger.debug("event: \(event)")

        switch event {
        case .renameStarted:
            beginRename(&newState)

        case .renameFinished:
            newState.renameInProgress = false
            newState.saveInProgress = false

        case .filesRenamed(let mappings):
            applyRenames(&newState, mappings: mappings)

        case .renameRecoveryChanged(let urls, let required):
            applyRecovery(&newState, urls: urls, required: required)

        case .addImage(let imageData):
            newState.imageData.append(imageData)

        case .addImages(let imageDatas):
            newState.imageData.append(contentsOf: imageDatas)
            if UserDefaults.standard.object(forKey: SettingsPreferences.pairJPGRAWKey) as? Bool != false {
                newState.pairingEligibleIDs = (newState.pairingEligibleIDs ?? []).union(imageDatas.map(\.id))
            } else if newState.pairingEligibleIDs == nil {
                newState.pairingEligibleIDs = []
            }

        case .addressChanged(let selected, let address):
            update(&newState, selected: selected, address: address)

        case .backupFolderSizeCheck:
            checkBackupFolderSize(&newState)

        case .backupURLChanged(let backupURL):
            newBackupFolder(&newState, url: backupURL)

        case .badGpxFile(let filename):
            newState.gpxBadFileNames.append(filename)

        case .catchUnexpectedError(let error, let message):
            newState.addSheet(type: .unexpectedErrorSheet,
                              error: error,
                              message: message)

        case .changeTimeZone:
            newState.showTimeZoneWindow.toggle()

        case .clearImagesRequest:
            clearImages(&newState)

        case .clearPlaces:
            clearPlaces(&newState)

        case .clearUniqueURLs:
            newState.uniqueURLs = nil

        case .creatorDraftApplied(let items):
            let ids = Set(items.map(\.id))
            guard ids.count == items.count,
                  items.allSatisfy({ item in
                      newState.imageData.contains {
                          $0.id == item.id && $0.metadataInspectionURL == item.target && $0.updatable
                              && newState.creatorSaveResults[item.id] != .resultUnknown
                      }
                  }) else { return state }
            for item in items {
                newState[item.id].applyMetadataDraft(item)
                newState.creatorSaveResults[item.id] = nil
            }
            newState.unsavedChanges = newState.imageData.contains { $0.hasPendingChanges }

        case .creatorDraftRemoved(let id), .creatorSaved(let id):
            clearCreatorDraft(&newState, id: id, discard: event == .creatorDraftRemoved(id))

        case .creatorSaveResult(let id, let result):
            newState.creatorSaveResults[id] = result

        case .cancelMetadataSave:
            newState.metadataSaveCancelled = true

        case .creatorSaveConflict:
            newState.addSheet(type: .saveErrorSheet)

        case .removeImages(let ids):
            let removed = ids.union(state.imageData.filter { ids.contains($0.id) }.compactMap(\.pairedID))
            newState.imageData.removeAll { removed.contains($0.id) }
            newState.pairingEligibleIDs?.subtract(removed)
            newState.locationSavedPhotoIDs.subtract(removed)
            newState.creatorSaveResults = newState.creatorSaveResults.filter {
                !removed.contains($0.key)
            }
            selectionChanged(&newState, selection: state.selection.subtracting(removed))
            newState.unsavedChanges = newState.imageData.contains { $0.hasPendingChanges }

        case .deleteRequest:
            delete(&newState)

        case .discardChangesRequest:
            discardChanges(&newState)

        case .restoreTracks(let tracks):
            for track in tracks {
                newState.gpxTracks.removeAll { $0.sourceURL == track.sourceURL }
                newState.gpxTracks.append(track)
            }
            newState.gpxTracks.sort { $0.firstTimestamp < $1.firstTimestamp }

        case .removeTrack(let url):
            newState.gpxTracks.removeAll { $0.sourceURL == url }

        case .discardTracksRequest:
            newState.gpxTracks = []

        case .duplicateImages:
            newState.addSheet(type: .duplicateImageSheet)

        case .findInMap(let value):
            newState.mapSearchActive = value

        case .finishedAddingTracks:
            newState.gpxImportRevision += 1 // Also notify for an unchanged, reimported file.

        case .goodGpxFile(let filename):
            newState.gpxGoodFileNames.append(filename)

        case .gpxLoadViewClosed:
            newState.gpxGoodFileNames = []
            newState.gpxBadFileNames = []

        case .imageSaved(let id, let metadata):
            if newState[id].original?.location != metadata.location {
                newState.locationSavedPhotoIDs.insert(id)
            }
            newState[id].original = Metadata(copying: metadata)

        case .localSaveBatch(let results):
            applyLocalSaveBatch(&newState, results)

        case .initBackupURL:
            getBackupURL(&newState)

        case .noBackupNotice:
            newState.addSheet(type: .noBackupFolderSheet)

        case .initPlaces(let places):
            newState.places = places

        case .linkPairedImages:
            newState.linkPairedImages()

        case .locationChanged(let coords):
            update(&newState, coords: coords)

        case .locationForImageChanged(let id, let coords):
            guard !state.saveInProgress, state[id].updatable else { return state }
            update(&newState, id: id, location: coords)

        case .locationFromPhoto(let coords, let elevation):
            guard !state.saveInProgress else { return state }
            for id in state.selection where state[id].updatable {
                update(&newState, id: id, location: coords, elevation: elevation)
                newState[id].metadata.gpsMapDatum = "WGS-84"
                newState[id].metadata.gpsProcessingMethod = "MANUAL"
                if let pairedID = state[id].pairedID, state[pairedID].updatable {
                    newState[pairedID].metadata.gpsMapDatum = "WGS-84"
                    newState[pairedID].metadata.gpsProcessingMethod = "MANUAL"
                }
            }

        case .confirmedWGS84Location(let coords):
            guard !state.saveInProgress else { return state }
            update(&newState, coords: coords)
            for id in state.selection {
                newState[id].metadata.gpsMapDatum = "WGS-84"
                newState[id].metadata.gpsProcessingMethod = "MANUAL"
                if let pairedID = state[id].pairedID, state[pairedID].updatable {
                    newState[pairedID].metadata.gpsMapDatum = "WGS-84"
                    newState[pairedID].metadata.gpsProcessingMethod = "MANUAL"
                }
            }

        case .locationFromTrack(let updates):
            newState.trackMatches = updates

        case .applyTrackMatches:
            for entry in state.trackMatches where entry.status == .matched {
                update(&newState, id: entry.id,
                       location: entry.coords, elevation: entry.elevation)
            }
            newState.trackMatches = []

        case .mainWindowChange(let window):
            newState.mainWindow = window

        case .mostSelectedChanged(let mostSelected):
            mostSelectedChanged(&newState, mostSelected: mostSelected)

        case .newThumbnail(let id, let image):
            if newState.imageData.contains(where: { $0.id == id }) {
                newState[id].thumbnail = image
            }

        case .newTimestamp(let date, let adjustment):
                update(&newState, date: date, adjustment: adjustment)

        case .openCommand:
            newState.importFiles.toggle()

        case .filesScanned(let urls, let ignored, let scoped):
            newState.scopedURLs.append(contentsOf: scoped)
            newState.ignoredFileCount = ignored
            selectUniqueFiles(&newState, imageURLs: urls)

        case .openFiles(let urls):
            openFiles(&newState, urls: urls)

        case .pasteRequest:
            paste(&newState)

        case .placeSelection(let place):
            savePlace(&newState, place)

        case .quitRequested:
            quitRequested(&newState)

        case .readTrackLog(let path, let tracklog):
            addTrackLog(&newState, path: path, tracklog: tracklog)

        case .removeOldFiles:
            checkBackupFolderSize(&newState)
            removeFiles(filesToRemove: newState.oldFiles,
                        from: newState.backupURL)
            newState.oldFiles = []

        case .saveComplete(let saveStatus):
            newState.saveInProgress = false
            newState.libraryImages = []
            newState.fileImages = []
            newState.xmpImages = []
            newState.creatorImages = []
            switch saveStatus {
            case .saveOK:
                break
            case .saveError:
                newState.addSheet(type: .saveErrorSheet)
            case .saveErrorSupressWarning:
                break
            case .saveTagError:
                newState.addSheet(type: .unexpectedErrorSheet,
                                  message: L10n.text("The metadata was saved, but the Finder tag could not be added."))
            }
            newState.unsavedChanges = newState.imageData.contains { $0.hasPendingChanges }

        case .saveProgress(let completed):
            newState.saveCompleted = min(newState.saveTotal, newState.saveCompleted + max(0, completed))

        case .saveRequest:
            save(&newState)

        case .searchActiveChanged(let searchActive):
            newState.searchActive = searchActive

        case .searchTextChanged(let text):
            newState.searchText = text

        case .selectAllRequest:
            selectAll(&newState)

        case .selectionChanged(let selection):
            selectionChanged(&newState, selection: selection)

        case .selectionChangedTo(let selection, let current):
            selectionChanged(&newState, selection: selection)
            if let current, newState.selection.contains(current) {
                newState.mostSelected = current
            }

        case .sheetDismissed:
            if newState.sheetStack.isEmpty {
                newState.sheetMessage = nil
                newState.sheetError = nil
                newState.sheetType = nil
            } else {
                let sheetInfo = newState.sheetStack.removeFirst()
                newState.sheetMessage = sheetInfo.sheetMessage
                newState.sheetError = sheetInfo.sheetError
                newState.sheetType = sheetInfo.sheetType
            }

        case .sidecarCreated(let id):
            if case .image = newState[id].metadata.source {
                newState[id].metadata = newState[id].metadata.xmp()
            }

        case .sortOrderChanged(let comparator):
            newState.sortOrder = comparator
            newState.imageData.sort(using: comparator)

        case .sortUsingCurrentComparator:
            newState.imageData.sort(using: newState.sortOrder)

        case .terminateRequest:
            newState.unsavedChanges = false

        case .textfieldFocusChanged(let focus):
            newState.textfieldActive = focus

        case .timeZoneChanged(let newTimeZone):
            newState.timeZone = newTimeZone

        case .toggleLogWindow:
            newState.showLogWindow.toggle()

        }

        // update the window document edited indicator when the
        // unsavedChanges is modified.

        if state.unsavedChanges != newState.unsavedChanges {
            newState.mainWindow?.isDocumentEdited = newState.unsavedChanges
        }

        return newState
    }
}

// a simple, fast enough search. Return true if the string characters match
// "pattern" characters in the given order ignoring case.

extension String {
    func fuzzy(_ pattern: String) -> Bool {
        // an empty pattern matches anything
        guard !pattern.isEmpty else { return true }
        var remainder = pattern[...]
        for char in self
        where char.lowercased() == remainder[remainder.startIndex].lowercased() {
            remainder.removeFirst()
            if remainder.isEmpty { return true }
        }
        return false
    }
}

private extension PhotoTrailReducer {
    func beginRename(_ state: inout PhotoTrailState) {
        guard !state.saveInProgress, !state.imageData.contains(where: \.hasPendingChanges) else { return }
        state.renameInProgress = true
        state.saveInProgress = true
    }

    func applyRenames(_ state: inout PhotoTrailState, mappings: [URL: URL]) {
        for index in state.imageData.indices { state.imageData[index].applyFileRenames(mappings) }
        state.uniqueURLs = state.uniqueURLs?.map { mappings[$0.standardizedFileURL] ?? $0 }
        MetadataInspectorReadCache.shared.invalidate(urls: Set(mappings.keys).union(mappings.values))
    }

    func applyRecovery(_ state: inout PhotoTrailState, urls: Set<URL>, required: Bool) {
        for index in state.imageData.indices {
            let image = state.imageData[index]
            if image.metadataCreatorImageURL.map(urls.contains) == true || image.metadataInspectionURL.map(urls.contains) == true {
                state.imageData[index].fileRenameRecoveryRequired = required
            }
        }
    }
}
