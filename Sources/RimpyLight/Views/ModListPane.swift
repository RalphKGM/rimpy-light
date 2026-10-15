import SwiftUI
import UniformTypeIdentifiers

/// One of the two mod lists. Rows can be dragged within the active list to
/// reorder and between lists to (de)activate; double-click toggles.
struct ModListPane: View {
    @Environment(AppState.self) private var state
    let isActiveList: Bool

    @State private var filter = ""
    @State private var selection = Set<String>()

    private var ids: [String] { isActiveList ? state.active : state.inactiveIDs }
    private var visible: [String] { filter.isEmpty ? ids : ids.filter { state.matches($0, filter) } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
        }
        .onChange(of: selection) { old, new in
            if let added = new.subtracting(old).first ?? (new.count == 1 ? new.first : nil) {
                state.focused = added
            }
            if !new.isEmpty { state.selectingActiveList = isActiveList }
        }
        .onChange(of: state.selectingActiveList) { _, owner in
            if owner != isActiveList { selection = [] }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(isActiveList ? "Active" : "Inactive").font(.headline)
                Text("\(ids.count)").foregroundStyle(.secondary).monospacedDigit()
                Spacer()
            }
            TextField("Filter", text: $filter)
                .textFieldStyle(.roundedBorder)
        }
        .padding(10)
    }

    private var list: some View {
        let positions = Dictionary(uniqueKeysWithValues: state.active.enumerated().map { ($1, $0 + 1) })
        return List(selection: $selection) {
            ForEach(visible, id: \.self) { id in
                ModRow(mod: state.mod(id),
                       position: isActiveList ? positions[id] : nil,
                       severity: isActiveList ? state.validation.worst(id) : nil,
                       gameVersion: state.gameVersion)
                    // `.itemProvider` hooks into List's own dragging; `.onDrag` would
                    // swallow clicks on the row content and break selection.
                    .itemProvider { NSItemProvider(object: id as NSString) }
            }
            .onInsert(of: [.plainText]) { index, providers in
                receive(providers, at: index)
            }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            contextMenu(for: ids)
        } primaryAction: { ids in
            state.toggle(ids)
            selection.subtract(ids)
        }
        .overlay {
            if ids.isEmpty && !state.isLoading {
                Text(isActiveList ? "Drag mods here to activate them" : "No inactive mods")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onDrop(of: [.plainText], isTargeted: nil) { providers in
                        receive(providers, at: 0)
                        return true
                    }
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for ids: Set<String>) -> some View {
        if !ids.isEmpty {
            Button(isActiveList ? "Deactivate" : "Activate") {
                state.toggle(ids)
                selection.subtract(ids)
            }
            if isActiveList {
                Button("Move to Top") { state.moveToTop(Array(ids)) }
                Button("Move to Bottom") { state.moveToBottom(Array(ids)) }
            }
            Divider()
            if ids.count == 1, let id = ids.first {
                let mod = state.mod(id)
                if !mod.isMissing {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([mod.folder]) }
                }
                if let url = mod.workshopPageURL {
                    Button("Open Workshop Page") { NSWorkspace.shared.open(url) }
                }
                Button("Copy Package ID") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(mod.displayPackageId, forType: .string)
                }
            }
        }
    }

    /// List drags one item per selected row; collect them all, then apply once
    /// so multi-row drops keep their order.
    private func receive(_ providers: [NSItemProvider], at index: Int) {
        let target = index < visible.count ? visible[index] : nil
        Task { @MainActor in
            var dropped: [String] = []
            for provider in providers {
                if let id = await loadString(provider) { dropped.append(id) }
            }
            guard !dropped.isEmpty else { return }
            if isActiveList {
                state.activate(dropped, before: target)
            } else {
                state.deactivate(dropped)
            }
            selection = Set(dropped)
        }
    }

    private func loadString(_ provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                continuation.resume(returning: object as? String)
            }
        }
    }
}

struct ModRow: View {
    let mod: Mod
    let position: Int?
    let severity: ModIssue.Severity?
    let gameVersion: String

    var body: some View {
        HStack(spacing: 8) {
            if let position {
                Text("\(position)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(minWidth: 22, alignment: .trailing)
            }
            Image(systemName: sourceIcon)
                .foregroundStyle(mod.source == .official ? .yellow : .secondary)
                .frame(width: 16)
                .help(mod.isMissing ? "Not installed" : mod.source.label)
            VStack(alignment: .leading, spacing: 1) {
                Text(mod.name)
                    .lineLimit(1)
                    .foregroundStyle(nameColor)
                if !mod.authors.isEmpty {
                    Text(mod.authors).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let severity {
                Image(systemName: severity.symbol).foregroundStyle(severity.color)
            }
        }
        .padding(.vertical, 1)
    }

    private var sourceIcon: String {
        if mod.isMissing { return "questionmark.folder" }
        switch mod.source {
        case .official: return "star.fill"
        case .local: return "folder"
        case .workshop: return "cloud"
        }
    }

    private var nameColor: Color {
        if mod.isMissing { return .red }
        if !mod.supports(gameVersion: gameVersion) { return .orange }
        return .primary
    }
}

extension ModIssue.Severity {
    var symbol: String {
        switch self {
        case .error: "xmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .info: "info.circle"
        }
    }

    var color: Color {
        switch self {
        case .error: .red
        case .warning: .orange
        case .info: .blue
        }
    }
}
