import GpxTrackLog
import Foundation

extension PhotoTrailReducer {
    func addTrackLog(_ state: inout PhotoTrailState, path: String, tracklog: GpxTrackLog?) {
        if let tracklog {
            state.gpxGoodFileNames.append(path)
            state.gpxTracks.removeAll { $0.sourceURL == tracklog.sourceURL }
            state.gpxTracks.append(tracklog)
            if state.gpxTracks.count > 1 {
                state.gpxTracks.sort { $0.firstTimestamp < $1.firstTimestamp }
            }
        } else {
            state.gpxBadFileNames.append(path)
        }
    }
}
