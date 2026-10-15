import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        HSplitView {
            ModListPane(isActiveList: false)
                .frame(minWidth: 260, idealWidth: 300, maxHeight: .infinity)
            ModListPane(isActiveList: true)
                .frame(minWidth: 280, idealWidth: 340, maxHeight: .infinity)
            ModDetailView()
                .frame(minWidth: 320, idealWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) { StatusBar() }
        .toolbar { toolbar }
        .navigationTitle("RimPy Light")
        .navigationSubtitle(state.isDirty ? "Unsaved changes" : "")
        .alert("RimPy Light", isPresented: Binding(get: { state.alert != nil }, set: { if !$0 { state.alert = nil } })) {
            Button("OK") { state.alert = nil }
        } message: {
            Text(state.alert ?? "")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { Task { await state.reload() } } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .help("Rescan mod folders and reload ModsConfig.xml")
            .disabled(state.isLoading)
        }
        ToolbarItemGroup {
            Button(action: state.clear) { Label("Clear", systemImage: "xmark.circle") }
                .help("Deactivate everything except Core and DLCs")
            Button(action: state.restore) { Label("Restore", systemImage: "arrow.uturn.backward") }
                .help("Go back to the list saved in ModsConfig.xml")
                .disabled(!state.isDirty)
            Button(action: state.addMissingDependencies) { Label("Dependencies", systemImage: "link.badge.plus") }
                .help("Activate installed mods that active mods depend on")
            Button(action: state.autosort) { Label("Sort", systemImage: "arrow.up.arrow.down") }
                .help("Sort by dependencies, About.xml rules, community rules and your rules")
            Menu {
                Button("Import Mod List…", action: importList)
                Button("Export Mod List…", action: exportList)
                Button("Copy List to Clipboard", action: state.copyListToClipboard)
            } label: {
                Label("Lists", systemImage: "list.bullet.rectangle")
            }
            .help("Import or export mod lists")
            Button(action: state.save) { Label("Save", systemImage: "square.and.arrow.down") }
                .help("Write the active list to ModsConfig.xml")
                .keyboardShortcut("s")
                .tint(state.isDirty ? .accentColor : nil)
            Button(action: state.launchGame) { Label("Play", systemImage: "play.fill") }
                .help("Launch RimWorld")
        }
    }

    private func importList() {
        let panel = NSOpenPanel()
        panel.message = "Choose ModsConfig.xml, a .rml mod list, or a save file (.rws)"
        panel.allowedContentTypes = [.xml] + ["rml", "rws"].compactMap { UTType(filenameExtension: $0) }
        panel.directoryURL = state.paths.modListsFolder
        if panel.runModal() == .OK, let url = panel.url { state.importList(from: url) }
    }

    private func exportList() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "rml") ?? .xml]
        panel.nameFieldStringValue = "RimPy Light list.rml"
        panel.directoryURL = state.paths.modListsFolder
        if panel.runModal() == .OK, let url = panel.url { state.exportList(to: url) }
    }
}

private struct StatusBar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let counts = state.validation.counts
        HStack(spacing: 12) {
            if state.isLoading { ProgressView().controlSize(.small) }
            Text(state.status).lineLimit(1).truncationMode(.tail).help(state.status)
            Spacer()
            ForEach(state.validation.global) { issue in
                Label(issue.message, systemImage: "exclamationmark.octagon.fill").foregroundStyle(.red)
            }
            if counts.errors > 0 {
                Label("\(counts.errors)", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                    .help("\(counts.errors) errors")
            }
            if counts.warnings > 0 {
                Label("\(counts.warnings)", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    .help("\(counts.warnings) warnings")
            }
            if !state.fullGameVersion.isEmpty {
                Text("RimWorld \(state.fullGameVersion)").foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
