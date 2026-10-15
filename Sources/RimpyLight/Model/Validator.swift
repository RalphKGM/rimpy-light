import Foundation

struct ModIssue: Hashable, Identifiable, Sendable {
    enum Severity: Int, Comparable, Sendable {
        case info, warning, error
        static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
    }

    enum Fix: Hashable, Sendable {
        case activate(String)
        case deactivate(String)
        case openURL(String)
        case sort
    }

    var severity: Severity
    var message: String
    var fix: Fix?
    var id: String { "\(severity.rawValue)|\(message)" }
}

struct ValidationResult {
    var byMod: [String: [ModIssue]] = [:]
    var global: [ModIssue] = []

    func worst(_ id: String) -> ModIssue.Severity? { byMod[id]?.map(\.severity).max() }

    var counts: (errors: Int, warnings: Int) {
        let all = byMod.values.flatMap { $0 } + global
        return (all.filter { $0.severity == .error }.count, all.filter { $0.severity == .warning }.count)
    }
}

enum Validator {
    static func validate(active: [Mod], installed: [String: Mod], rules: RuleContext, gameVersion: String) -> ValidationResult {
        var result = ValidationResult()
        func add(_ id: String, _ issue: ModIssue) { result.byMod[id, default: []].append(issue) }

        let activePackages = Set(active.map(\.packageId))
        let position = Dictionary(uniqueKeysWithValues: active.enumerated().map { ($1.id, $0) })
        let byPackage = Dictionary(grouping: installed.values, by: \.packageId)
        func displayName(_ pid: String) -> String {
            byPackage[pid]?.first?.name ?? rules.community.names[pid] ?? rules.user.names[pid] ?? pid
        }

        if !activePackages.contains("ludeon.rimworld") {
            result.global.append(ModIssue(severity: .error, message: "Core (ludeon.rimworld) is not active.",
                                          fix: installed["ludeon.rimworld"] != nil ? .activate("ludeon.rimworld") : nil))
        }

        for mod in active {
            if mod.isMissing {
                add(mod.id, ModIssue(severity: .error, message: "Not installed. Remove it or install it.",
                                     fix: .deactivate(mod.id)))
                continue
            }

            for dep in mod.dependencies where !dep.packageIds.contains(where: activePackages.contains) {
                if let candidate = dep.packageIds.lazy.compactMap({ byPackage[$0]?.first }).first {
                    add(mod.id, ModIssue(severity: .error, message: "Requires \(candidate.name), which is inactive.",
                                         fix: .activate(candidate.id)))
                } else {
                    add(mod.id, ModIssue(severity: .error, message: "Requires \(dep.displayName), which is not installed.",
                                         fix: dep.workshopURL.map { .openURL($0) }))
                }
            }

            for other in rules.incompatibilities(of: mod) where activePackages.contains(other) {
                add(mod.id, ModIssue(severity: .error, message: "Incompatible with \(displayName(other)).",
                                     fix: nil))
            }

            if !mod.supports(gameVersion: gameVersion) {
                let listed = mod.supportedVersions.isEmpty ? "none listed" : mod.supportedVersions.joined(separator: ", ")
                add(mod.id, ModIssue(severity: .warning,
                                     message: "Not marked for RimWorld \(gameVersion) (supports: \(listed)).", fix: nil))
            }

            if mod.hasAmbiguousDuplicate {
                let others = mod.duplicateFolders.map(\.lastPathComponent).joined(separator: ", ")
                add(mod.id, ModIssue(severity: .error,
                                     message: "Another installed copy (\(others)) has the same packageId, so RimWorld loads only one of them and ignores the other. Unsubscribe from the copy you don't want.",
                                     fix: mod.workshopPageURL.map { .openURL($0.absoluteString) }))
            } else if !mod.duplicateFolders.isEmpty {
                add(mod.id, ModIssue(severity: .info,
                                     message: "Another copy with the same packageId is installed at \(mod.duplicateFolders.map(\.path).joined(separator: ", ")).",
                                     fix: nil))
            }
        }

        let names = Dictionary(uniqueKeysWithValues: active.map { ($0.id, $0.name) })
        let edges = LoadOrder.edges(for: active, rules: rules)

        // Mods ahead of Core can't inherit from Core's base defs ("Could not find
        // parent node named BuildingBase"), so only allow ones with a reason to be there.
        if let corePosition = position["ludeon.rimworld"] {
            var mustPrecedeCore: Set<String> = ["ludeon.rimworld"]
            var changed = true
            while changed {
                changed = false
                for e in edges where mustPrecedeCore.contains(e.to) && !mustPrecedeCore.contains(e.from) {
                    mustPrecedeCore.insert(e.from)
                    changed = true
                }
            }
            for mod in active.prefix(corePosition)
            where !mustPrecedeCore.contains(mod.id) && !rules.isTop(mod) && mod.source != .official {
                add(mod.id, ModIssue(severity: .error,
                                     message: "Loads before Core without needing to; its content may fail to load.",
                                     fix: .sort))
            }
        }

        for edge in edges {
            guard let from = position[edge.from], let to = position[edge.to], from > to else { continue }
            let severity: ModIssue.Severity = edge.kind == .community ? .info : .warning
            add(edge.to, ModIssue(severity: severity,
                                  message: "Should load after \(names[edge.from] ?? edge.from) (\(edge.kind.label)).",
                                  fix: .sort))
        }

        for (id, issues) in result.byMod {
            result.byMod[id] = issues.sorted { $0.severity > $1.severity }
        }
        return result
    }
}
