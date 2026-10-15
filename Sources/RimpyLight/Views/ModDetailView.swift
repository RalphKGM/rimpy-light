import SwiftUI

struct ModDetailView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if let id = state.focused {
            ModDetail(mod: state.mod(id), isActive: state.active.contains(id))
                .id(id)
        } else {
            ContentUnavailableView("No Mod Selected", systemImage: "shippingbox",
                                   description: Text("Select a mod to see its details."))
        }
    }
}

private struct ModDetail: View {
    @Environment(AppState.self) private var state
    let mod: Mod
    let isActive: Bool

    @State private var preview: NSImage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let preview {
                    Image(nsImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(mod.name).font(.title2.bold()).textSelection(.enabled)
                    if !mod.authors.isEmpty {
                        Text("by \(mod.authors)").foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Button(isActive ? "Deactivate" : "Activate") { state.toggle([mod.id]) }
                    if !mod.isMissing {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([mod.folder]) }
                    }
                    if let url = mod.workshopPageURL {
                        Button("Workshop") { NSWorkspace.shared.open(url) }
                    } else if let link = mod.url, let url = URL(string: link) {
                        Button("Website") { NSWorkspace.shared.open(url) }
                    }
                }

                issues

                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 4) {
                    row("Package ID", mod.displayPackageId)
                    row("Source", mod.isMissing ? "Not installed" : mod.source.label)
                    if !mod.supportedVersions.isEmpty {
                        row("Versions", mod.supportedVersions.joined(separator: ", "))
                    }
                    if !mod.dependencies.isEmpty {
                        row("Requires", mod.dependencies.map(\.displayName).joined(separator: ", "))
                    }
                    if !mod.isMissing {
                        row("Folder", mod.folder.path)
                    }
                }
                .font(.callout)

                if !mod.isMissing {
                    UserRulesEditor(mod: mod)
                }

                if !mod.description.isEmpty {
                    Divider()
                    Text(mod.description)
                        .font(.callout)
                        .textSelection(.enabled)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: mod.previewURL) {
            guard let url = mod.previewURL else { preview = nil; return }
            preview = await Task.detached { NSImage(contentsOf: url) }.value
        }
    }

    @ViewBuilder
    private var issues: some View {
        let list = state.validation.byMod[mod.id] ?? []
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(list) { issue in
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: issue.severity.symbol).foregroundStyle(issue.severity.color)
                        Text(issue.message).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        if let fix = issue.fix {
                            Button(fix.title) { state.apply(fix) }.controlSize(.small)
                        }
                    }
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).textSelection(.enabled).lineLimit(4)
        }
    }
}

private extension ModIssue.Fix {
    var title: String {
        switch self {
        case .activate: "Activate"
        case .deactivate: "Remove"
        case .openURL: "Open Page"
        case .sort: "Sort"
        }
    }
}

/// Lets the player pin a mod to the top/bottom or add their own load-after/before rules.
private struct UserRulesEditor: View {
    @Environment(AppState.self) private var state
    let mod: Mod
    @State private var otherId = ""

    var body: some View {
        let user = state.rules.user
        let pid = mod.packageId
        let after = (user.loadAfter[pid] ?? []).sorted()
        let before = (user.loadBefore[pid] ?? []).sorted()
        let community = state.rules.community

        DisclosureGroup("Load order rules") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Always load at top", isOn: binding(\.top))
                Toggle("Always load at bottom", isOn: binding(\.bottom))

                ForEach(after, id: \.self) { other in
                    ruleRow("Loads after \(name(other))") {
                        state.editUserRules { $0.loadAfter[pid]?.remove(other) }
                    }
                }
                ForEach(before, id: \.self) { other in
                    ruleRow("Loads before \(name(other))") {
                        state.editUserRules { $0.loadBefore[pid]?.remove(other) }
                    }
                }

                HStack {
                    Picker("Mod", selection: $otherId) {
                        Text("Choose a mod…").tag("")
                        ForEach(otherMods, id: \.packageId) { Text($0.name).tag($0.packageId) }
                    }
                    .labelsHidden()
                    Button("Load After") { state.addUserRule(mod: pid, loadsAfter: otherId); otherId = "" }
                        .disabled(otherId.isEmpty)
                    Button("Load Before") { state.addUserRule(mod: pid, loadsBefore: otherId); otherId = "" }
                        .disabled(otherId.isEmpty)
                }

                let communityAfter = community.loadAfter[pid]?.count ?? 0
                let communityBefore = community.loadBefore[pid]?.count ?? 0
                if communityAfter + communityBefore > 0 || community.bottom.contains(pid) || community.top.contains(pid) {
                    Text("Community rules: loads after \(communityAfter), before \(communityBefore) mod(s)"
                         + (community.bottom.contains(pid) ? ", pinned to bottom" : "")
                         + (community.top.contains(pid) ? ", pinned to top" : "") + ".")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 6)
        }
    }

    private var otherMods: [Mod] {
        state.active.map(state.mod).filter { $0.packageId != mod.packageId && !$0.isMissing }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    private func name(_ pid: String) -> String {
        state.active.map(state.mod).first { $0.packageId == pid }?.name ?? state.rules.user.names[pid] ?? pid
    }

    private func ruleRow(_ text: String, remove: @escaping () -> Void) -> some View {
        HStack {
            Text(text)
            Spacer()
            Button(role: .destructive, action: remove) { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
        }
    }

    private func binding(_ keyPath: WritableKeyPath<RuleSet, Set<String>>) -> Binding<Bool> {
        Binding(
            get: { state.rules.user[keyPath: keyPath].contains(mod.packageId) },
            set: { on in
                state.editUserRules { rules in
                    if on { rules[keyPath: keyPath].insert(mod.packageId) } else { rules[keyPath: keyPath].remove(mod.packageId) }
                }
            }
        )
    }
}
