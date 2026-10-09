import AppKit
import Coords
import Foundation
import GpxTrackLog
import ImageData
import Metadata
import SwiftUI

// events that trigger a change of state

enum PhotoTrailEvent: Equatable {
    case renameStarted
    case renameFinished
    case filesRenamed([URL: URL])
    case renameRecoveryChanged(Set<URL>, Bool)
    case addImage(ImageData)
    case addImages([ImageData])
    case addressChanged(Set<ImageData.ID>, Place)
    case missingAddressesFilled([ImageData.ID: Place])
    case backupFolderSizeCheck
    case backupURLChanged(URL?)
    case badGpxFile(String)
    case catchUnexpectedError(String?, String?)
    case changeTimeZone
    case clearImagesRequest
    case clearPlaces
    case clearUniqueURLs
    case creatorDraftApplied([MetadataCreatorEditPlan.Item])
    case creatorDraftRemoved(ImageData.ID)
    case creatorSaved(ImageData.ID)
    case creatorSaveResult(ImageData.ID, MetadataCreatorSaveResult)
    case cancelMetadataSave
    case creatorSaveConflict
    case deleteRequest
    case removeImages(Set<ImageData.ID>)
    case discardChangesRequest
    case restoreTracks([GpxTrackLog])
    case removeTrack(URL)
    case discardTracksRequest
    case duplicateImages
    case findInMap(Bool)
    case finishedAddingTracks
    case goodGpxFile(String)
    case gpxLoadViewClosed
    case imageSaved(ImageData.ID, Metadata)
    case localSaveBatch([SaveHelper.LocalSaveResult])
    case initBackupURL
    case noBackupNotice
    case initPlaces([Place])
    case linkPairedImages
    case locationChanged(Coords)
    case locationForImageChanged(ImageData.ID, Coords)
    case locationFromPhoto(Coords, Double?)
    case confirmedWGS84Location(Coords)
    case locationFromTrack([LocationHelper.LocationById])
    case applyTrackMatches
    case mainWindowChange(NSWindow?)
    case mostSelectedChanged(ImageData.ID)
    case newThumbnail(ImageData.ID, Image)
    case newTimestamp(Date, TimeInterval)
    case openCommand
    case filesScanned([URL], ignored: Int, scoped: [URL])
    case openFiles([URL])
    case pasteRequest
    case placeSelection(Place)
    case quitRequested
    case readTrackLog(String, GpxTrackLog?)
    case removeOldFiles
    case saveComplete(SaveHelper.SaveStatus)
    case saveProgress(Int)
    case saveRequest
    case savePageRequest(MetadataSaveScope)
    case searchActiveChanged(Bool)
    case searchTextChanged(String)
    case selectAllRequest
    case selectionChanged(Set<ImageData.ID>)
    case selectionChangedTo(Set<ImageData.ID>, ImageData.ID?)
    case sheetDismissed
    case sidecarCreated(ImageData.ID)
    case sortOrderChanged([KeyPathComparator<ImageData>])
    case sortUsingCurrentComparator
    case terminateRequest
    case textfieldFocusChanged(Bool)
    case timeZoneChanged(TimeZone)
    case toggleLogWindow
}

// A description for each event

extension PhotoTrailEvent: CustomStringConvertible {
    var description: String {
        switch self {
        case .renameStarted: "renameStarted"
        case .renameFinished: "renameFinished"
        case .filesRenamed: "filesRenamed"
        case .renameRecoveryChanged: "renameRecoveryChanged"
        case .addImage: "addImage"
        case .addImages: "addImages"
        case .addressChanged: "addressChanged"
        case .missingAddressesFilled: "missingAddressesFilled"
        case .backupFolderSizeCheck: "backupFolderSizeCheck"
        case .backupURLChanged: "backupURLChanged"
        case .badGpxFile: "badGpxFile"
        case .catchUnexpectedError: "catchUnexpectedError"
        case .changeTimeZone: "changeTimeZone"
        case .clearImagesRequest: "clearImagesRequest"
        case .clearPlaces: "clearPlaces"
        case .clearUniqueURLs: "clearUniqueURLs"
        case .creatorDraftApplied: "creatorDraftApplied"
        case .creatorDraftRemoved: "creatorDraftRemoved"
        case .creatorSaved: "creatorSaved"
        case .creatorSaveResult: "creatorSaveResult"
        case .cancelMetadataSave: "cancelMetadataSave"
        case .creatorSaveConflict: "creatorSaveConflict"
        case .deleteRequest: "deleteRequest"
        case .removeImages: "removeImages"
        case .discardChangesRequest: "discardChangesRequest"
        case .restoreTracks: "restoreTracks"
        case .removeTrack: "removeTrack"
        case .discardTracksRequest: "discardTracksRequest"
        case .duplicateImages: "duplicateImages"
        case .findInMap: "findInMap"
        case .finishedAddingTracks: "finishedAddingTracks"
        case .goodGpxFile: "goodGpxFile"
        case .gpxLoadViewClosed: "gpxLoadViewClosed"
        case .imageSaved: "imageSaved"
        case .localSaveBatch: "localSaveBatch"
        case .initBackupURL: "initBackupURL"
        case .noBackupNotice: "noBackupNotice"
        case .initPlaces: "initPlaces"
        case .linkPairedImages: "linkPairedImages"
        case .locationChanged: "locationChanged"
        case .locationForImageChanged: "locationForImageChanged"
        case .locationFromPhoto: "locationFromPhoto"
        case .confirmedWGS84Location: "confirmedWGS84Location"
        case .locationFromTrack: "locationFromTrack"
        case .applyTrackMatches: "applyTrackMatches"
        case .mainWindowChange: "mainWindowChange"
        case .mostSelectedChanged: "mostSelectedChanged"
        case .newThumbnail: "newThumbnail"
        case .newTimestamp: "newTimestamp"
        case .openCommand: "openCommand"
        case .filesScanned: "filesScanned"
        case .openFiles: "openFiles"
        case .pasteRequest: "pasteRequest"
        case .placeSelection: "placeSelection"
        case .quitRequested: "quitRequested"
        case .readTrackLog: "readTrackLog"
        case .removeOldFiles: "removeOldFiles"
        case .saveComplete: "saveComplete"
        case .saveProgress: "saveProgress"
        case .saveRequest: "saveReqest"
        case .savePageRequest: "savePageRequest"
        case .searchActiveChanged: "searchActiveChanged"
        case .searchTextChanged: "searchTextChanged"
        case .selectAllRequest: "selectAllRequest"
        case .selectionChanged: "selectionChanged"
        case .selectionChangedTo: "selectionChangedTo"
        case .sheetDismissed: "sheetDismissed"
        case .sidecarCreated: "sidecarCreated"
        case .sortOrderChanged: "sortOrderChanged"
        case .sortUsingCurrentComparator: "sortUsingCurrentComparator"
        case .terminateRequest: "terminateRequest"
        case .textfieldFocusChanged: "textfieldFocusChanged"
        case .timeZoneChanged: "timeZoneChanged"
        case .toggleLogWindow: "toggleLogWindow"
        }
    }
}
