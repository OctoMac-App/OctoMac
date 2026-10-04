import SwiftUI

extension FocusedValues {
    /// The main window's printer selection, so the Printer menu can switch printers and act on the one on screen.
    @Entry var printerSelection: Binding<UUID?>?
}

/// The Printer menu: jump between printers with ⌥⌘0 to ⌥⌘9, and pause, resume or pop out the camera of the
/// printer on screen. (⌘1 to ⌘6 already switch tabs.)
struct PrinterCommands: View {
    let store: InstanceStore
    @FocusedValue(\.printerSelection) private var selection

    var body: some View {
        Button("All Printers") { selection?.wrappedValue = AllPrinters.id }
            .keyboardShortcut("0", modifiers: [.command, .option])
            .disabled(selection == nil || store.instances.isEmpty)
        ForEach(Array(store.instances.enumerated()), id: \.element.id) { index, instance in
            let button = Button(instance.name) { selection?.wrappedValue = instance.id }
                .disabled(selection == nil)
            if index < 9 {
                button.keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.command, .option])
            } else {
                button
            }
        }

        Divider()

        let session = store.session(for: selection?.wrappedValue)
        let flags = session?.flags
        if flags?.paused == true {
            Button("Resume Print") { session?.jobCommand(.resume) }
                .keyboardShortcut("p", modifiers: [.command, .option])
        } else {
            Button("Pause Print") { session?.jobCommand(.pause) }
                .keyboardShortcut("p", modifiers: [.command, .option])
                .disabled(!(flags?.printing ?? false) || flags?.cancelling == true)
        }

        let popped = session.map { PictureInPicture.shared.sessionID == $0.instance.id } ?? false
        Button(popped ? "Close Picture in Picture" : "Camera in Picture in Picture") {
            guard let session else { return }
            if popped {
                PictureInPicture.shared.close()
            } else {
                PictureInPicture.shared.show(session, filament: store.filament(for: session.instance))
            }
        }
        .keyboardShortcut("c", modifiers: [.command, .option])
        .disabled(session?.webcamStreamURL == nil)
    }
}
