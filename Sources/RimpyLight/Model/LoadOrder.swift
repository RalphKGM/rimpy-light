import Foundation

/// Where an ordering constraint came from. Stronger constraints win when
/// rules contradict each other.
enum EdgeKind: Int, Comparable, Sendable {
    case community = 1, modder, dependency, user, forced

    static func < (a: EdgeKind, b: EdgeKind) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .community: "community rule"
        case .modder: "mod's About.xml"
        case .dependency: "dependency"
        case .user: "your rule"
        case .forced: "forced by About.xml"
        }
    }
}

/// `from` must load before `to`.
struct Edge: Hashable, Sendable {
    let from: String
    let to: String
    let kind: EdgeKind
}

struct RuleContext: Sendable {
    var community = RuleSet()
    var user = RuleSet()

    func isTop(_ mod: Mod) -> Bool {
        mod.packageId == "brrainz.harmony" || user.top.contains(mod.packageId) || community.top.contains(mod.packageId)
    }

    func isBottom(_ mod: Mod) -> Bool {
        user.bottom.contains(mod.packageId) || community.bottom.contains(mod.packageId)
    }

    func incompatibilities(of mod: Mod) -> Set<String> {
        mod.incompatibleWith
            .union(community.incompatible[mod.packageId] ?? [])
            .union(user.incompatible[mod.packageId] ?? [])
    }
}

enum LoadOrder {
    /// Builds every ordering constraint between the given active mods.
    static func edges(for active: [Mod], rules: RuleContext) -> [Edge] {
        var idsByPackage: [String: [String]] = [:]
        for mod in active { idsByPackage[mod.packageId, default: []].append(mod.id) }

        var strongest: [Pair: EdgeKind] = [:]
        func add(before: String, after mod: Mod, _ kind: EdgeKind) {
            for other in idsByPackage[before] ?? [] where other != mod.id {
                let pair = Pair(other, mod.id)
                strongest[pair] = max(strongest[pair] ?? kind, kind)
            }
        }
        func add(after: String, before mod: Mod, _ kind: EdgeKind) {
            for other in idsByPackage[after] ?? [] where other != mod.id {
                let pair = Pair(mod.id, other)
                strongest[pair] = max(strongest[pair] ?? kind, kind)
            }
        }

        for mod in active where !mod.isMissing {
            mod.forceLoadAfter.forEach { add(before: $0, after: mod, .forced) }
            mod.forceLoadBefore.forEach { add(after: $0, before: mod, .forced) }
            mod.loadAfter.forEach { add(before: $0, after: mod, .modder) }
            mod.loadBefore.forEach { add(after: $0, before: mod, .modder) }
            for dep in mod.dependencies {
                dep.packageIds.forEach { add(before: $0, after: mod, .dependency) }
            }
            rules.community.loadAfter[mod.packageId]?.forEach { add(before: $0, after: mod, .community) }
            rules.community.loadBefore[mod.packageId]?.forEach { add(after: $0, before: mod, .community) }
            rules.user.loadAfter[mod.packageId]?.forEach { add(before: $0, after: mod, .user) }
            rules.user.loadBefore[mod.packageId]?.forEach { add(after: $0, before: mod, .user) }
        }

        // When two rules directly contradict, keep only the stronger one.
        var result: [Edge] = []
        for (pair, kind) in strongest {
            if let reverse = strongest[Pair(pair.b, pair.a)], reverse > kind { continue }
            result.append(Edge(from: pair.a, to: pair.b, kind: kind))
        }
        return result
    }

    struct SortResult {
        var order: [String]
        /// Constraints dropped to break cycles.
        var broken: [Edge]
    }

    /// Topological sort. Among mods that are free to go next, the one with the
    /// lowest tier wins (top-pinned, official, normal, bottom-pinned), then the
    /// one earliest in the current list, so a sort only moves what the rules require.
    ///
    /// A mod that must load before a higher-priority mod inherits that mod's tier.
    /// Without this, a mod required before Core (e.g. Faster Game Loading) that sat
    /// low in the list would hold Core back while every other mod above it went first.
    static func sort(_ active: [Mod], rules: RuleContext) -> SortResult {
        let position = Dictionary(uniqueKeysWithValues: active.enumerated().map { ($1.id, $0) })
        func tier(_ mod: Mod) -> Int {
            if rules.isTop(mod) { return 0 }
            if mod.source == .official { return 1 }
            if rules.isBottom(mod) { return 3 }
            return 2
        }
        let ownTiers = Dictionary(uniqueKeysWithValues: active.map { ($0.id, tier($0)) })
        var tiers = ownTiers
        func key(_ id: String) -> (Int, Int) { (tiers[id]!, position[id]!) }

        var edges = Set(edges(for: active, rules: rules))
        var broken: [Edge] = []
        var remaining = Set(active.map(\.id))
        var order: [String] = []

        /// Each mod takes the lowest tier of anything that must load after it.
        func inheritTiers() {
            tiers = ownTiers
            var changed = true
            var rounds = 0
            while changed && rounds <= active.count {
                changed = false
                rounds += 1
                for e in edges where tiers[e.to]! < tiers[e.from]! {
                    tiers[e.from] = tiers[e.to]
                    changed = true
                }
            }
        }
        inheritTiers()

        while !remaining.isEmpty {
            var indegree = Dictionary(uniqueKeysWithValues: remaining.map { ($0, 0) })
            for e in edges where remaining.contains(e.from) && remaining.contains(e.to) {
                indegree[e.to]! += 1
            }
            let ready = indegree.filter { $0.value == 0 }.map(\.key)
            guard let next = ready.min(by: { key($0) < key($1) }) else {
                // Cycle: drop its weakest constraint and try again.
                let cycle = findCycle(in: remaining, edges: edges)
                let weakest = cycle.min { ($0.kind.rawValue, key($0.from).0, key($0.from).1) < ($1.kind.rawValue, key($1.from).0, key($1.from).1) }!
                edges.remove(weakest)
                broken.append(weakest)
                inheritTiers()
                continue
            }
            order.append(next)
            remaining.remove(next)
        }
        return SortResult(order: order, broken: broken)
    }

    /// How many mods a reorder actually relocates: everything outside the
    /// longest run of mods that kept their relative order.
    static func movedCount(from old: [String], to new: [String]) -> Int {
        let rank = Dictionary(uniqueKeysWithValues: old.enumerated().map { ($1, $0) })
        var tails: [Int] = []
        for id in new {
            guard let r = rank[id] else { continue }
            var lo = 0, hi = tails.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if tails[mid] < r { lo = mid + 1 } else { hi = mid }
            }
            if lo == tails.count { tails.append(r) } else { tails[lo] = r }
        }
        return new.count - tails.count
    }

    private static func findCycle(in nodes: Set<String>, edges: Set<Edge>) -> [Edge] {
        var outgoing: [String: [Edge]] = [:]
        for e in edges where nodes.contains(e.from) && nodes.contains(e.to) {
            outgoing[e.from, default: []].append(e)
        }
        var state: [String: Int] = [:] // 1 = on stack, 2 = done
        var stack: [Edge] = []

        func visit(_ node: String) -> [Edge]? {
            state[node] = 1
            for e in outgoing[node] ?? [] {
                if state[e.to] == 1 {
                    let start = stack.firstIndex { $0.from == e.to } ?? stack.count
                    return Array(stack[start...]) + [e]
                }
                if state[e.to] == nil {
                    stack.append(e)
                    if let cycle = visit(e.to) { return cycle }
                    stack.removeLast()
                }
            }
            state[node] = 2
            return nil
        }
        for node in nodes.sorted() where state[node] == nil {
            if let cycle = visit(node) { return cycle }
        }
        return []
    }

    private struct Pair: Hashable {
        let a: String, b: String
        init(_ a: String, _ b: String) { self.a = a; self.b = b }
    }
}
