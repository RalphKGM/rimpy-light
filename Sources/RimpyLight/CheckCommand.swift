import Foundation

/// `RimpyLight --check` prints what the app sees and what Sort would do,
/// without touching ModsConfig.xml.
enum CheckCommand {
    static func run() -> Never {
        let paths = GamePaths.load()
        let listArg = CommandLine.arguments.firstIndex(of: "--list").map { CommandLine.arguments[$0 + 1] }
        let config = try? ModListIO.read(listArg.map { URL(fileURLWithPath: $0) } ?? paths.modsConfigURL)
        let fullVersion = paths.fullGameVersion ?? config?.version ?? ""
        let version = AboutParser.majorMinor(fullVersion)

        let start = Date()
        let mods = ModScanner.scan(paths: paths, gameVersion: version)
        let elapsed = Date().timeIntervalSince(start)
        let byId = Dictionary(mods.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        var rules = RuleContext()
        rules.community = RuleStore.loadCommunity()?.0 ?? RuleSet()
        rules.user = RuleStore.loadUser()

        let active = (config?.ids ?? []).map { byId[$0] ?? .missing(id: $0) }
        let validation = Validator.validate(active: active, installed: byId, rules: rules, gameVersion: version)
        let sorted = LoadOrder.sort(active, rules: rules)
        let afterSort = Validator.validate(active: sorted.order.map { byId[$0] ?? .missing(id: $0) },
                                           installed: byId, rules: rules, gameVersion: version)

        print("Game:      \(paths.gameFolder) (\(fullVersion))")
        print("Data:      \(paths.dataFolder)")
        print("Config:    \(paths.modsConfigURL.path)")
        print("Workshop:  \(paths.workshopFolder)")
        print("Scanned \(mods.count) mods in \(String(format: "%.2f", elapsed))s: "
              + ModSource.allCases.map { s in "\(mods.filter { $0.source == s }.count) \(s.rawValue)" }.joined(separator: ", "))
        print("Community rules: \(rules.community.ruleCount) mods")
        print("Active: \(active.count), not installed: \(active.filter(\.isMissing).count)")
        print("Issues now:        \(validation.counts.errors) errors, \(validation.counts.warnings) warnings")
        print("Issues after sort: \(afterSort.counts.errors) errors, \(afterSort.counts.warnings) warnings")
        print("Sort would move \(LoadOrder.movedCount(from: active.map(\.id), to: sorted.order)) mod(s); broke \(sorted.broken.count) rule(s)")
        for edge in sorted.broken {
            print("  ignored: \(edge.from) before \(edge.to) (\(edge.kind.label))")
        }
        if let flag = CommandLine.arguments.firstIndex(of: "--explain"), flag + 1 < CommandLine.arguments.count {
            let target = CommandLine.arguments[flag + 1].lowercased()
            print("\nConstraints involving \(target):")
            for edge in LoadOrder.edges(for: active, rules: rules) where edge.from == target || edge.to == target {
                print("  \(edge.from) before \(edge.to) (\(edge.kind.label))")
            }
        }
        if CommandLine.arguments.contains("--order") {
            print("\nCurrent → sorted:")
            for (i, (a, b)) in zip(active.map(\.id), sorted.order).enumerated() {
                print(String(format: "%3d  %@ %@", i + 1, a.padding(toLength: 46, withPad: " ", startingAt: 0), a == b ? "" : "→ \(b)"))
            }
        }
        print("\nIssues:")
        for mod in active {
            for issue in validation.byMod[mod.id] ?? [] where issue.severity > .info {
                print("  [\(issue.severity == .error ? "E" : "W")] \(mod.name): \(issue.message)")
            }
        }
        exit(0)
    }
}

