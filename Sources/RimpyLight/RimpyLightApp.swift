import AppKit
import SwiftUI

@main
struct RimpyLightApp: App {
    @State private var state = AppState()

    init() {
        if CommandLine.arguments.contains("--check") { CheckCommand.run() }
        // Lets `swift run` produce a normal foreground app as well as the bundled .app.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        Window("RimPy Light", id: "main") {
            ContentView()
                .environment(state)
                .task { await state.reload() }
                .frame(minWidth: 960, minHeight: 560)
        }
        .commands {
            CommandGroup(replacing: .saveItem) {
                Button("Save Mod List") { state.save() }
                    .keyboardShortcut("s")
            }
            CommandMenu("Mods") {
                Button("Sort") { state.autosort() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Add Missing Dependencies") { state.addMissingDependencies() }
                Divider()
                Button("Reload") { Task { await state.reload() } }
                    .keyboardShortcut("r")
                Button("Restore Saved List") { state.restore() }
                Button("Clear Active List") { state.clear() }
            }
        }

        Settings {
            SettingsView()
                .environment(state)
        }
    }
}
