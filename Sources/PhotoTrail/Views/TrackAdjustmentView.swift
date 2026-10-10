import Coords
import GpxTrackLog
import SwiftUI

struct TrackAdjustmentView: View {
    let record: TrackRecord
    let apply: (GpxTrackLog) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var days = "0"
    @State private var hours = "0"
    @State private var minutes = "0"
    @State private var seconds = "0"
    @State private var later = true
    @State private var east = "0"
    @State private var north = "0"
    @State private var eastward = true
    @State private var northward = true
    @State private var preview: GpxTrackLog?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("调整轨迹…")).font(.title2)
            Text(record.name).textSelection(.enabled)
            Form {
                Section(L10n.text("时间偏移")) {
                    Picker(L10n.text("方向"), selection: $later) {
                        Text(L10n.text("延后")).tag(true)
                        Text(L10n.text("提前")).tag(false)
                    }
                    HStack {
                        input(L10n.text("天"), text: $days)
                        input(L10n.text("时"), text: $hours)
                        input(L10n.text("分"), text: $minutes)
                        input(L10n.text("秒"), text: $seconds)
                    }
                }.disabled(!record.log.hasRecordedTimes)
                Section(L10n.text("位置偏移")) {
                    HStack {
                        Picker(L10n.text("东西方向"), selection: $eastward) {
                            Text(L10n.text("向东")).tag(true)
                            Text(L10n.text("向西")).tag(false)
                        }
                        input(L10n.text("米"), text: $east)
                    }
                    HStack {
                        Picker(L10n.text("南北方向"), selection: $northward) {
                            Text(L10n.text("向北")).tag(true)
                            Text(L10n.text("向南")).tag(false)
                        }
                        input(L10n.text("米"), text: $north)
                    }
                }
            }.formStyle(.grouped)
            Text(L10n.text("原文件保留。位置校正使用球面距离，合成距离最多 100 公里，纬度须在南北 85° 以内；无时间的点不补造时间。"))
                .font(.caption).foregroundStyle(.secondary)
            if let preview {
                let adjustedSegments = TrackRecord(log: preview, bookmark: nil).segments
                let framing = record.segments + adjustedSegments
                HStack {
                    VStack {
                        Text(L10n.text("原始轨迹"))
                        TrackThumbnail(segments: record.segments, framingSegments: framing).frame(height: 70)
                    }
                    VStack {
                        Text(L10n.text("调整后"))
                        TrackThumbnail(segments: adjustedSegments, framingSegments: framing).frame(height: 70)
                    }
                }
                Text(record.timeRange + " → " + TrackRecord(log: preview, bookmark: nil).timeRange)
                    .font(.caption).textSelection(.enabled)
            }
            if let error { Text(error).foregroundStyle(.orange).font(.callout) }
            HStack {
                Button(L10n.text("取消")) { dismiss() }
                Spacer()
                Button(L10n.text("预览")) { updatePreview() }
                Button(L10n.text("应用调整")) {
                    guard let preview else { return }
                    do { try apply(preview); dismiss() }
                    catch { self.error = L10n.text("轨迹已变化或保存失败，未应用调整：%1$@", error.localizedDescription) }
                }.disabled(preview == nil || preview == record.log).keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 580)
        .onChange(of: parameters) { preview = nil; error = nil }
    }

    private var parameters: String { [days, hours, minutes, seconds, east, north, String(later), String(eastward), String(northward)].joined(separator: "|") }

    private func input(_ title: String, text: Binding<String>) -> some View {
        HStack {
            TextField(title, text: text).textFieldStyle(.roundedBorder).frame(minWidth: 45)
            Text(title).foregroundStyle(.secondary)
        }
    }

    private func updatePreview() {
        do {
            let values = try [days, hours, minutes, seconds, east, north].map { value -> Double in
                guard let number = Double(value), number.isFinite, number >= 0 else { throw TrackAdjustmentError.invalidOffset }
                return number
            }
            let time = record.log.hasRecordedTimes ?
                (values[0] * 86_400 + values[1] * 3_600 + values[2] * 60 + values[3]) * (later ? 1 : -1) : 0
            preview = try record.log.adjusted(seconds: time, east: values[4] * (eastward ? 1 : -1),
                                             north: values[5] * (northward ? 1 : -1))
            error = nil
        } catch {
            preview = nil
            self.error = L10n.text("偏移值或轨迹点无效，请检查距离、时间与纬度范围。")
        }
    }
}
