import Foundation

/// Load-order rules in the community rules JSON schema
/// (`{"timestamp": n, "rules": {packageId: {"loadAfter": {otherId: {...}}, ...}}}`),
/// shared by RimPy's bundled database, RimSort's Community-Rules-Database, and
/// this app's user rules file.
struct RuleSet: Sendable {
    var loadAfter: [String: Set<String>] = [:]
    var loadBefore: [String: Set<String>] = [:]
    var incompatible: [String: Set<String>] = [:]
    var top: Set<String> = []
    var bottom: Set<String> = []
    /// Display names recorded alongside referenced package IDs.
    var names: [String: String] = [:]
    var timestamp: Date?

    var ruleCount: Int {
        Set(loadAfter.keys).union(loadBefore.keys).union(incompatible.keys).union(top).union(bottom).count
    }

    static func parse(_ data: Data) throws -> RuleSet {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rules = json["rules"] as? [String: Any]
        else { throw CocoaError(.fileReadCorruptFile) }

        var set = RuleSet()
        if let ts = json["timestamp"] as? Double { set.timestamp = Date(timeIntervalSince1970: ts) }
        for (rawId, value) in rules {
            guard let entry = value as? [String: Any] else { continue }
            let pid = rawId.lowercased()
            set.loadAfter[pid] = set.collect(entry["loadAfter"])
            set.loadBefore[pid] = set.collect(entry["loadBefore"])
            set.incompatible[pid] = set.collect(entry["incompatibleWith"])
            if flag(entry["loadTop"]) { set.top.insert(pid) }
            if flag(entry["loadBottom"]) { set.bottom.insert(pid) }
        }
        set.loadAfter = set.loadAfter.filter { !$0.value.isEmpty }
        set.loadBefore = set.loadBefore.filter { !$0.value.isEmpty }
        set.incompatible = set.incompatible.filter { !$0.value.isEmpty }
        return set
    }

    private mutating func collect(_ value: Any?) -> Set<String> {
        guard let dict = value as? [String: Any] else { return [] }
        var ids = Set<String>()
        for (rawId, info) in dict {
            let id = rawId.lowercased()
            ids.insert(id)
            if let name = ((info as? [String: Any])?["name"] as? [String])?.first { names[id] = name }
        }
        return ids
    }

    private static func flag(_ value: Any?) -> Bool {
        (value as? [String: Any])?["value"] as? Bool ?? false
    }

    func encoded() throws -> Data {
        var rules: [String: [String: Any]] = [:]
        func refs(_ ids: Set<String>) -> [String: Any] {
            Dictionary(uniqueKeysWithValues: ids.map { ($0, ["name": [names[$0] ?? $0]]) })
        }
        let allIds = Set(loadAfter.keys).union(loadBefore.keys).union(incompatible.keys).union(top).union(bottom)
        for pid in allIds {
            var entry: [String: Any] = [
                "loadAfter": refs(loadAfter[pid] ?? []),
                "loadBefore": refs(loadBefore[pid] ?? []),
            ]
            if let inc = incompatible[pid], !inc.isEmpty { entry["incompatibleWith"] = refs(inc) }
            if top.contains(pid) { entry["loadTop"] = ["value": true] }
            if bottom.contains(pid) { entry["loadBottom"] = ["value": true] }
            rules[pid] = entry
        }
        let json: [String: Any] = ["timestamp": Int(Date().timeIntervalSince1970), "rules": rules]
        return try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
    }
}

/// Where rule files live and how the community database is refreshed.
enum RuleStore {
    static let communityRulesURL = URL(string:
        "https://raw.githubusercontent.com/RimSort/Community-Rules-Database/main/communityRules.json")!

    static var supportFolder: URL {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/RimpyLight")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var communityCacheURL: URL { supportFolder.appendingPathComponent("communityRules.json") }
    static var userRulesURL: URL { supportFolder.appendingPathComponent("userRules.json") }

    /// Our own downloaded copy first, then RimSort's copy if it is installed.
    static func loadCommunity() -> (RuleSet, URL)? {
        let rimsort = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Application Support/RimSort/dbs/Community-Rules-Database/communityRules.json")
        for url in [communityCacheURL, rimsort] {
            if let data = try? Data(contentsOf: url), let rules = try? RuleSet.parse(data) {
                return (rules, url)
            }
        }
        return nil
    }

    static func downloadCommunity() async throws -> RuleSet {
        let (data, response) = try await URLSession.shared.data(from: communityRulesURL)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        let rules = try RuleSet.parse(data)
        try data.write(to: communityCacheURL, options: .atomic)
        return rules
    }

    static func loadUser() -> RuleSet {
        guard let data = try? Data(contentsOf: userRulesURL) else { return RuleSet() }
        return (try? RuleSet.parse(data)) ?? RuleSet()
    }

    static func saveUser(_ rules: RuleSet) throws {
        try rules.encoded().write(to: userRulesURL, options: .atomic)
    }
}
