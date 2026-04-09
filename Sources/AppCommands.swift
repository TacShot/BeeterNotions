import SwiftUI

struct AppCommands: Commands {
    var body: some Commands {
        CommandMenu("Beeter") {
            Text("Use the in-window toolbar for note creation, import, and export.")
        }
    }
}
