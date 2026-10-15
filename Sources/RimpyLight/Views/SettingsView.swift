import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @State private var draft = GamePaths()

    var body: some View {
        Form {
            Section("Folders") {
                pathField("Game folder", \.gameFolder, help: "Folder containing RimWorldMac.app and Data")
                pathField("Config folder", \.configFolder, help: "Folder containing ModsConfig.xml")
                pathField("Workshop mods", \.workshopFolder, help: "steamapps/workshop/content/294100 (leave empty for non-Steam)")
                pathField("Local mods", \.localModsFolder, help: "The game's Mods folder")
                HStack {
                    Button("Auto-detect") { draft = GamePaths.detect() }
                    Spacer()
                    Button("Apply") { state.updatePaths(draft) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(draft == state.paths)
                }
            }

            Section("Community rules") {
                LabeledContent("Source") {
                    Text(state.communitySource?.path ?? "None loaded")
                        .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                }
                LabeledContent("Mods covered", value: "\(state.rules.community.ruleCount)")
                if let date = state.rules.community.timestamp {
                    LabeledContent("Updated", value: date.formatted(date: .abbreviated, time: .shortened))
                }
                Button("Download Latest") { Task { await state.updateCommunityRules() } }
                Text("From github.com/RimSort/Community-Rules-Database. Your own rules are kept separately in \(RuleStore.userRulesURL.path).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 620)
        .onAppear { draft = state.paths }
    }

    private func pathField(_ label: String, _ keyPath: WritableKeyPath<GamePaths, String>, help: String) -> some View {
        LabeledContent(label) {
            HStack {
                TextField(label, text: Binding(get: { draft[keyPath: keyPath] }, set: { draft[keyPath: keyPath] = $0 }))
                    .labelsHidden()
                    .help(help)
                Button("Choose…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.message = help
                    if !draft[keyPath: keyPath].isEmpty {
                        panel.directoryURL = URL(fileURLWithPath: draft[keyPath: keyPath])
                    }
                    if panel.runModal() == .OK, let url = panel.url { draft[keyPath: keyPath] = url.path }
                }
            }
        }
    }
}
