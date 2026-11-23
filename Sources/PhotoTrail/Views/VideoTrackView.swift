import Exiftool
import ImageData
import MapKit
import SwiftUI

struct VideoTrackButton: View {
    let url: URL
    @State private var presented = false

    var body: some View {
        Button(L10n.text("查看视频 GPS 轨迹"), systemImage: "point.topleft.down.to.point.bottomright.curvepath") { presented = true }
            .sheet(isPresented: $presented) { VideoTrackView(url: url) }
    }
}

private struct VideoTrackView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var points: [VideoTrackPoint] = []
    @State private var index = 0.0
    @State private var loaded = false
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(url.lastPathComponent).font(.headline).lineLimit(1)
                Spacer()
                Button(L10n.text("关闭")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if !loaded {
                ProgressView(L10n.text("正在读取元数据…"))
            } else if let failure {
                Text(failure).textSelection(.enabled)
            } else if points.isEmpty {
                Text(L10n.text("未读到带播放时间的 GPS 样本。"))
            } else {
                let sample = points[Int(index)]
                Map {
                    MapPolyline(coordinates: points.map(\.location)).stroke(.blue, lineWidth: 3)
                    Marker(Duration.seconds(sample.seconds).formatted(.time(pattern: .minuteSecond)), coordinate: sample.location)
                }
                if points.count > 1 { Slider(value: $index, in: 0...Double(points.count - 1), step: 1) }
                Text("\(Duration.seconds(sample.seconds).formatted(.time(pattern: .hourMinuteSecond))) · \(sample.location.latitude), \(sample.location.longitude)")
                    .monospacedDigit().textSelection(.enabled)
                if let gpsDate = sample.gpsDate { Text("GPS · " + gpsDate).font(.caption) }
            }
        }.padding(20).frame(minWidth: 540, minHeight: 360)
        .task(id: url) {
            loaded = false; failure = nil; points = []; index = 0
            let source = url
            let version = MetadataInspectionFileVersion.read(source)
            do {
                let result = try await Task.detached(priority: .utility) { try Exiftool.helper.timedVideoLocations(from: source) }.value
                try Task.checkCancellation()
                guard MetadataInspectionFileVersion.read(source) == version else { throw MetadataInspectionError.sourceChanged }
                points = result
            } catch { if Task.isCancelled { return }; failure = OperationFailure.message(L10n.text("元数据读取失败"), error: error) }
            loaded = true
        }
    }
}
