import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    var paths = GamePaths.load()
    var fullGameVersion = ""
    /// "1.7"-style version used for supportedVersions checks.
    var gameVersion = ""

    private(set) var mods: [String: Mod] = [:]
    /// Active mod ids in load order. May include ids that are not installed.
    private(set) var active: [String] = []
    private(set) var savedActive: [String] = []
    private(set) var knownExpansions: [String] = []
    private(set) var validation = ValidationResult()

    var rules = RuleContext()
    var communitySource: URL?

    var focused: String?
    /// Which list owns the selection (true = active). The other list clears its own
    /// so clicking a row there always registers as a change.
    var selectingActiveList: Bool?
    var isLoading = false
    var status = ""
    var alert: String?

    var isDirty: Bool { active != savedActive }

    var inactiveIDs: [String] {
        let activeSet = Set(active)
        return mods.values.filter { !activeSet.contains($0.id) }
            .sorted { ($0.source == .official ? 0 : 1, $0.name.lowercased()) < ($1.source == .official ? 0 : 1, $1.name.lowercased()) }
            .map(\.id)
    }

    func mod(_ id: String) -> Mod { mods[id] ?? .missing(id: id) }

    func matches(_ id: String, _ query: String) -> Bool {
        let m = mod(id)
        return m.name.localizedCaseInsensitiveContains(query)
            || m.id.localizedCaseInsensitiveContains(query)
            || m.authors.localizedCaseInsensitiveContains(query)
    }

    // MARK: - Loading

    func reload() async {
        isLoading = true
        status = "Scanning mods…"
        defer { isLoading = false }

        fullGameVersion = paths.fullGameVersion ?? ""
        let config = try? ModListIO.read(paths.modsConfigURL)
        if fullGameVersion.isEmpty { fullGameVersion = config?.version ?? "" }
        gameVersion = AboutParser.majorMinor(fullGameVersion)

        let paths = self.paths
        let version = gameVersion
        let scanned = await Task.detached(priority: .userInitiated) {
            ModScanner.scan(paths: paths, gameVersion: version)
        }.value
        let community = await Task.detached { RuleStore.loadCommunity() }.value

        mods = Dictionary(scanned.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        rules.community = community?.0 ?? RuleSet()
        communitySource = community?.1
        rules.user = RuleStore.loadUser()

        knownExpansions = config?.knownExpansions ?? []
        savedActive = dedupe(config?.ids ?? [])
        active = savedActive
        revalidate()

        if paths.dataFolder.isEmpty {
            alert = "Couldn't find RimWorld's Data folder (Core and DLCs). Set the game folder in Settings."
        }
        status = "Loaded \(mods.count) mods" + (fullGameVersion.isEmpty ? "" : " for RimWorld \(fullGameVersion)")
    }

    func revalidate() {
        validation = Validator.validate(active: active.map(mod), installed: mods, rules: rules, gameVersion: gameVersion)
    }

    private func dedupe(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    // MARK: - Editing the active list

    /// Moves `ids` into the active list before `before` (or to the end).
    func activate(_ ids: [String], before: String? = nil) {
        let moving = dedupe(ids)
        var list = active.filter { !moving.contains($0) }
        let index = before.flatMap { list.firstIndex(of: $0) } ?? list.count
        list.insert(contentsOf: moving, at: index)
        setActive(list)
    }

    func deactivate(_ ids: [String]) {
        let removing = Set(ids)
        setActive(active.filter { !removing.contains($0) })
    }

    func toggle(_ ids: Set<String>) {
        let activeSet = Set(active)
        let toActivate = ids.filter { !activeSet.contains($0) }
        if toActivate.isEmpty {
            deactivate(Array(ids))
        } else {
            activate(toActivate.sorted { mod($0).name < mod($1).name })
        }
    }

    func moveToTop(_ ids: [String]) { activate(orderedByActive(ids), before: active.first) }
    func moveToBottom(_ ids: [String]) { activate(orderedByActive(ids)) }

    private func orderedByActive(_ ids: [String]) -> [String] {
        let set = Set(ids)
        return active.filter { set.contains($0) }
    }

    /// Clears everything except official content.
    func clear() {
        setActive(active.filter { mod($0).source == .official && !mod($0).isMissing })
    }

    func restore() { setActive(savedActive) }

    func autosort() {
        let result = LoadOrder.sort(active.map(mod), rules: rules)
        let moved = LoadOrder.movedCount(from: active, to: result.order)
        setActive(result.order)
        var message = moved > 0 ? "Sorted: moved \(moved) of \(active.count) mods." : "Already in order."
        if !result.broken.isEmpty {
            message += " Ignored \(result.broken.count) conflicting rule(s): "
            message += result.broken.map { "\(mod($0.from).name) → \(mod($0.to).name) (\($0.kind.label))" }
                .joined(separator: "; ")
        }
        status = message
    }

    /// Activates every installed mod required by the active list, repeating until nothing is missing.
    func addMissingDependencies() {
        var added: [String] = []
        while true {
            let fixes = validation.byMod.values.flatMap { $0 }.compactMap { issue -> String? in
                if case .activate(let id)? = issue.fix { return id }
                return nil
            }
            let new = dedupe(fixes).filter { !active.contains($0) }
            if new.isEmpty { break }
            added += new
            activate(new)
        }
        status = added.isEmpty ? "No installed dependencies were missing." : "Activated \(added.count) dependencies."
    }

    func apply(_ fix: ModIssue.Fix) {
        switch fix {
        case .activate(let id): activate([id])
        case .deactivate(let id): deactivate([id])
        case .openURL(let url): if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        case .sort: autosort()
        }
    }

    private func setActive(_ list: [String]) {
        active = list
        revalidate()
    }

    // MARK: - Saving and lists

    func save() {
        let official = mods.values.filter { $0.source == .official && $0.id != "ludeon.rimworld" }.map(\.id)
        let expansions = dedupe(knownExpansions + official.sorted())
        do {
            try ModListIO.writeModsConfig(to: paths.modsConfigURL,
                                          version: fullGameVersion,
                                          active: dedupe(active.map { mod($0).gameId }),
                                          knownExpansions: expansions)
            savedActive = active
            knownExpansions = expansions
            status = "Saved \(active.count) mods to ModsConfig.xml (previous version kept as ModsConfig.xml.bak)."
        } catch {
            alert = "Couldn't save ModsConfig.xml: \(error.localizedDescription)"
        }
    }

    func importList(from url: URL) {
        do {
            let list = try ModListIO.read(url)
            guard !list.ids.isEmpty else {
                alert = "No mod list found in \(url.lastPathComponent)."
                return
            }
            // Lists made on another machine may reference a local copy we only have from Steam, or vice versa.
            let resolved = list.ids.map { id -> String in
                if mods[id] != nil { return id }
                if mods[id + "_steam"] != nil { return id + "_steam" }
                if id.hasSuffix("_steam"), mods[String(id.dropLast(6))] != nil { return String(id.dropLast(6)) }
                return id
            }
            setActive(dedupe(resolved))
            let missing = active.filter { mods[$0] == nil }.count
            status = "Imported \(active.count) mods from \(url.lastPathComponent)"
                + (missing > 0 ? " (\(missing) not installed)." : ".")
        } catch {
            alert = "Couldn't read \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func exportList(to url: URL) {
        do {
            try ModListIO.writeRML(to: url, version: fullGameVersion, mods: active.map(mod))
            status = "Exported \(active.count) mods to \(url.lastPathComponent)."
        } catch {
            alert = "Couldn't export: \(error.localizedDescription)"
        }
    }

    func copyListToClipboard() {
        let lines = active.enumerated().map { index, id -> String in
            let m = mod(id)
            let link = m.workshopPageURL?.absoluteString ?? m.url ?? ""
            return "\(index + 1). \(m.name)" + (link.isEmpty ? "" : " — \(link)")
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        status = "Copied \(active.count) mods to the clipboard."
    }

    // MARK: - Game and rules

    func launchGame() {
        if isDirty {
            alert = "You have unsaved changes. Save the mod list first so the game picks them up."
            return
        }
        if paths.isSteamInstall, let url = URL(string: "steam://rungameid/294100") {
            NSWorkspace.shared.open(url)
            return
        }
        let game = URL(fileURLWithPath: paths.gameFolder)
        let apps = ["RimWorldMac.app", "RimWorld.app"].map { game.appendingPathComponent($0) }
        if let app = apps.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            NSWorkspace.shared.openApplication(at: app, configuration: .init())
        } else {
            alert = "Couldn't find the RimWorld app in \(paths.gameFolder)."
        }
    }

    func updateCommunityRules() async {
        status = "Downloading community rules…"
        do {
            rules.community = try await RuleStore.downloadCommunity()
            communitySource = RuleStore.communityCacheURL
            revalidate()
            status = "Community rules updated (\(rules.community.ruleCount) mods covered)."
        } catch {
            alert = "Couldn't download community rules: \(error.localizedDescription)"
        }
    }

    func editUserRules(_ change: (inout RuleSet) -> Void) {
        change(&rules.user)
        do {
            try RuleStore.saveUser(rules.user)
        } catch {
            alert = "Couldn't save your rules: \(error.localizedDescription)"
        }
        revalidate()
    }

    func addUserRule(mod pid: String, loadsAfter other: String) {
        editUserRules { rules in
            rules.loadAfter[pid, default: []].insert(other)
            rules.loadBefore[pid]?.remove(other)
            rules.names[other] = mods.values.first { $0.packageId == other }?.name
        }
    }

    func addUserRule(mod pid: String, loadsBefore other: String) {
        editUserRules { rules in
            rules.loadBefore[pid, default: []].insert(other)
            rules.loadAfter[pid]?.remove(other)
            rules.names[other] = mods.values.first { $0.packageId == other }?.name
        }
    }

    func updatePaths(_ newPaths: GamePaths) {
        paths = newPaths
        paths.save()
        Task { await reload() }
    }
}
