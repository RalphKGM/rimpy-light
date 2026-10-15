import Foundation

enum ModSource: String, Sendable, CaseIterable {
    case official, local, workshop

    var label: String {
        switch self {
        case .official: "Official"
        case .local: "Local"
        case .workshop: "Steam Workshop"
        }
    }
}

struct ModDependency: Hashable, Sendable {
    /// Lowercased packageId plus any alternatives that also satisfy the dependency.
    var packageIds: [String]
    var displayName: String
    var workshopURL: String?
}

struct Mod: Identifiable, Hashable, Sendable {
    /// The key RimWorld writes to ModsConfig.xml: the lowercased packageId,
    /// with `_steam` appended when a local copy of the same mod also exists.
    var id: String
    /// Lowercased packageId from About.xml.
    var packageId: String
    var displayPackageId: String
    var name: String
    var authors: String
    var description: String
    var url: String?
    var source: ModSource
    var folder: URL
    var workshopId: String?
    var supportedVersions: [String]
    var dependencies: [ModDependency]
    var loadAfter: Set<String>
    var loadBefore: Set<String>
    var forceLoadAfter: Set<String>
    var forceLoadBefore: Set<String>
    var incompatibleWith: Set<String>
    var previewURL: URL?
    /// Listed in ModsConfig.xml but not found on disk.
    var isMissing = false
    /// Other installed copies sharing this packageId.
    var duplicateFolders: [URL] = []
    /// Shares its packageId with another copy of the same kind (e.g. two Steam
    /// subscriptions), which RimWorld can't tell apart: it loads only one of them.
    var hasAmbiguousDuplicate = false

    /// The id RimWorld understands. Internal `#n` suffixes that keep ambiguous
    /// duplicates apart in this app must never reach ModsConfig.xml.
    var gameId: String {
        guard let hash = id.firstIndex(of: "#") else { return id }
        return String(id[..<hash])
    }

    static func missing(id: String) -> Mod {
        Mod(id: id, packageId: id.replacingOccurrences(of: "_steam", with: ""), displayPackageId: id,
            name: id, authors: "", description: "", url: nil, source: .local,
            folder: URL(fileURLWithPath: "/"), workshopId: nil, supportedVersions: [],
            dependencies: [], loadAfter: [], loadBefore: [], forceLoadAfter: [], forceLoadBefore: [],
            incompatibleWith: [], previewURL: nil, isMissing: true)
    }

    var workshopPageURL: URL? {
        guard let workshopId else { return nil }
        return URL(string: "https://steamcommunity.com/sharedfiles/filedetails/?id=\(workshopId)")
    }

    func supports(gameVersion: String) -> Bool {
        source == .official || supportedVersions.contains(gameVersion)
    }
}
