import SwiftUI

@main
struct BeeterNotionsApp: App {
    @StateObject private var store = NotesStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .task {
                    await store.load()
                }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1480, height: 920)
        .commands {
            AppCommands()
        }
    }
}
