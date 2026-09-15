import SwiftUI
import UDF

struct AdjustTimezoneView: View {
    @Environment(Store<GeoTagState, GeoTagEvent>.self) var store

    @State private var timeZone: TimeZone = TimeZone.current
    @State private var currentZone: TimeZoneName = .zero
    @State private var selectedZone: TimeZoneName = .zero

    var body: some View {
        VStack {
            Text("Specify Camera Time Zone")
                .font(.largeTitle)
                .padding(.top)

            Text("匹配照片和轨迹时，请选择相机拍摄时所用的时区。默认使用本机时区。\n\n开启更新 GPS 时间后，程序也会用此时区将拍摄时间转换为 UTC，再保存到照片。")
            .fixedSize(horizontal: false, vertical: true)
            .padding()

            Divider()

            Form {
                LabeledContent("Current Camera Time Zone:") {
                    VStack(alignment: .leading) {
                        Text(currentZone.rawValue)
                        Text(currentZone.timeZone.identifier)
                    }
                }
                .padding(.bottom)

                LabeledContent("Desired Camera Time Zone:") {
                    VStack(alignment: .leading) {
                        Picker("Desired Camera Time Zone",
                               selection: $selectedZone) {
                            ForEach(TimeZoneName.allCases) { zone in
                                Text(zone.rawValue)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 100)
                        .accessibilityIdentifier(TestIDs.AdjustTimeZoneView.cameraTimeZoneID)
                        Text(selectedZone.timeZone.identifier)
                    }
                }

            }
            .padding(30)

            Divider()

            HStack(alignment: .bottom) {
                Spacer()
                Button("Cancel") {
                    NSApplication.shared.keyWindow?.close()
                }
                .keyboardShortcut(.cancelAction)

                Button("Change") {
                    if currentZone != selectedZone {
                        currentZone = selectedZone
                        timeZone = selectedZone.timeZone
                        store.send(.timeZoneChanged(timeZone),
                                   description: "time zone change")
                    }
                    NSApplication.shared.keyWindow?.close()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .onAppear {
            timeZone = store.timeZone
            currentZone = TimeZoneName.timeZoneCase(zone: timeZone)
            selectedZone = currentZone
        }
    }
}

#Preview(traits: .store) {
    AdjustTimezoneView()
        .frame(height: 570)
}
