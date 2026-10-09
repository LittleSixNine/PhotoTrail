import Coords
import ImageData
import Metadata
import SwiftUI
import UDF

extension PhotoTrailReducer {
    // Update all selected images with the given coords

    func update(_ state: inout PhotoTrailState, coords: Coords) {
        for id in state.selection {
            update(&state, id: id, location: coords)
        }
    }

    // update a specific image with the given location

    func update(_ state: inout PhotoTrailState, id: ImageData.ID,
                location: Coords?, elevation: Double? = nil) {
        func logFormat(_ location: Coords?, elevation: Double?) -> String {
            var formatted = "none"
            if let location {
                formatted = "\(location.latitude), \(location.longitude)"
                if let elevation {
                    formatted += ", \(elevation)"
                }
            }
            return formatted
        }

        let logImg = state[id]
        logger.notice("""
            \(logImg.name, privacy: .public)
                \(logFormat(logImg.metadata.location,
                            elevation: logImg.metadata.elevation), privacy: .public) -> \
            \(logFormat(location, elevation: elevation), privacy: .public)
            """)

        state[id].metadata.location = location
        state[id].metadata.gpsMapDatum = nil
        state[id].metadata.gpsProcessingMethod = nil
        state[id].metadata.elevation = elevation
        if let pairedID = state[id].pairedID, state[pairedID].updatable {
            state[pairedID].metadata.location = location
            state[pairedID].metadata.gpsMapDatum = nil
            state[pairedID].metadata.gpsProcessingMethod = nil
            state[pairedID].metadata.elevation = elevation
        }
        state.unsavedChanges = true
    }

    // update a specific image with reverse geocode information

    func update(_ state: inout PhotoTrailState, selected: Set<ImageData.ID>,
                address: Place) {
        guard UserDefaults.standard.object(forKey: SettingsPreferences.writeRegionKey) as? Bool != false else { return }
        for id in selected {
            guard state[id].updatable, state[id].metadata.location == Coords(
                latitude: address.coordinate.latitude, longitude: address.coordinate.longitude) else { continue }
            state[id].metadata.sublocation = address.sublocation
            state[id].metadata.city = address.city
            state[id].metadata.state = address.state
            state[id].metadata.country = address.country
            state[id].metadata.countryCode = address.countryCode
            if let pairedID = state[id].pairedID, state[pairedID].updatable {
                state[pairedID].metadata.sublocation = address.sublocation
                state[pairedID].metadata.city = address.city
                state[pairedID].metadata.state = address.state
                state[pairedID].metadata.country = address.country
                state[pairedID].metadata.countryCode = address.countryCode
            }
        }
    }

    func fillMissingAddresses(_ state: inout PhotoTrailState, addresses: [ImageData.ID: Place]) {
        for (id, address) in addresses {
            guard LocationHelper.canFillRegion(state[id]),
                  state[id].metadata.location == Coords(latitude: address.coordinate.latitude,
                                                           longitude: address.coordinate.longitude) else { continue }
            var metadata = state[id].metadata
            if metadata.city?.isEmpty != false { metadata.city = address.city }
            if metadata.state?.isEmpty != false { metadata.state = address.state }
            if metadata.sublocation?.isEmpty != false { metadata.sublocation = address.sublocation }
            if metadata.country?.isEmpty != false { metadata.country = address.country }
            if metadata.countryCode?.isEmpty != false { metadata.countryCode = address.countryCode }
            state[id].metadata = metadata
        }
        state.unsavedChanges = state.imageData.contains { $0.hasPendingChanges }
    }

    // adjust the timestamp of all selected images by the given amount
    // If the image did not have an original timestamp assign the given date

    func update(_ state: inout PhotoTrailState,
                date: Date, adjustment: TimeInterval) {
        for id in state.selection {
            let updatedDate: Date
            if state[id].metadata.dateTimeCreated == nil {
                updatedDate = date
            } else {
                let originalDate = state[id].metadata.date(timeZone: state.timeZone)
                updatedDate = Date(timeInterval: adjustment,
                                   since: originalDate)
            }
            let timestamp = Metadata.timestamp(from: updatedDate)
            state[id].metadata.dateTimeCreated = timestamp
            if let pairedID = state[id].pairedID, state[pairedID].updatable {
                state[pairedID].metadata.dateTimeCreated = timestamp
            }
        }
        state.unsavedChanges = true
    }
}
