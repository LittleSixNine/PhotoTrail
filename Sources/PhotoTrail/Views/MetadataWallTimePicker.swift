import AppKit
import SwiftUI

// An explicit wall-clock picker includes seconds and never infers a capture offset.
struct MetadataWallTimePicker: NSViewRepresentable {
    @Binding var selection: Date
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = [.yearMonthDay, .hourMinuteSecond]
        picker.calendar = Calendar(identifier: .gregorian)
        picker.timeZone = TimeZone(secondsFromGMT: 0)
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.changed(_:))
        return picker
    }
    func updateNSView(_ picker: NSDatePicker, context: Context) {
        context.coordinator.parent = self
        picker.dateValue = selection
    }
    final class Coordinator: NSObject {
        var parent: MetadataWallTimePicker
        init(_ parent: MetadataWallTimePicker) { self.parent = parent }
        @objc func changed(_ sender: NSDatePicker) { parent.selection = sender.dateValue }
    }
}
