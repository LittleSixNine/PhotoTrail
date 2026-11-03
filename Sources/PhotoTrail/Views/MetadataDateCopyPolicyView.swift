import Foundation
import ImageData
import SwiftUI

struct MetadataDateCopyPolicyView: View {
    @Binding var policy: MetadataDateCopyPolicy
    @State private var missingDate = Date()

    var body: some View {
        DisclosureGroup(L10n.text("缺值与时区")) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(L10n.text("为缺失的来源补填时间"), isOn: Binding(
                    get: { policy.missingTime != nil },
                    set: { policy.missingTime = $0 ? Self.text(missingDate) : nil }))
                if policy.missingTime != nil {
                    MetadataWallTimePicker(selection: $missingDate)
                        .onChange(of: missingDate) { policy.missingTime = Self.text(missingDate) }
                }
                Picker(L10n.text("补充缺失的拍摄时区"), selection: $policy.offset) {
                    Text(L10n.text("未指定（保留已有时区）")).tag("")
                    ForEach(MetadataDateTimeZoneOption.options) { option in
                        Text(option.label(locale: L10n.locale)).tag(option.offset)
                    }
                }
            }.padding(.top, 8)
        }.font(.callout)
        .onAppear {
            if let time = policy.missingTime, let date = try? MetadataDate(String(time.prefix(19))) { missingDate = date.date }
            else {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
                let local = formatter.string(from: Date())
                if let date = try? MetadataDate(local) { missingDate = date.date }
            }
        }
    }
    private static func text(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .gmt
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
