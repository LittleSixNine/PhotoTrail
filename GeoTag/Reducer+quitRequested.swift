// Quit (or last window close) requested when there was a save
// in progress or there are unsaved changes.

extension GeoTagReducer {
    func quitRequested(_ state: inout GeoTagState) {
        if state.saveInProgress {
            state.addSheet(type: .savingUpdatesSheet)
            return
        }

        if state.unsavedChanges {
            state.confirmationMessage = "仍有未保存的修改，退出后会丢失。确认退出？"
            state.confirmationEvent = .terminateRequest
            state.presentConfirmation.toggle()
        }
    }
}
