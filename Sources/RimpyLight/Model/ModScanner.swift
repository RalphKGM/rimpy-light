import Foundation

enum ModScanner {
    /// Scans official content, local mods and workshop mods in parallel.
    static func scan(paths: GamePaths, gameVersion: String) -> [Mod] {
        var folders: [(URL, ModSource)] = []
        folders += subdirectories(paths.dataFolder).map { ($0, .official) }
        folders += subdirectories(paths.localModsFolder).map { ($0, .local) }
        folders += subdirectories(paths.workshopFolder).map { ($0, .workshop) }

        var parsed = [Mod?](repeating: nil, count: folders.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: folders.count) { i in
            let mod = AboutParser.parse(folder: folders[i].0, source: folders[i].1, gameVersion: gameVersion)
            lock.lock()
            parsed[i] = mod
            lock.unlock()
        }
        return assignIds(parsed.compactMap { $0 })
    }

    /// Mirrors RimWorld's handling of duplicate packageIds: when a local or
    /// official copy exists, the workshop copy is referred to as `<id>_steam`.
    static func assignIds(_ mods: [Mod]) -> [Mod] {
        var result = mods
        let groups = Dictionary(grouping: result.indices, by: { result[$0].packageId })
        for (_, indices) in groups where indices.count > 1 {
            let hasNonSteam = indices.contains { result[$0].source != .workshop }
            var used = Set<String>()
            for i in indices.sorted(by: { result[$0].source != .workshop && result[$1].source == .workshop }) {
                var id = result[i].packageId
                if result[i].source == .workshop, hasNonSteam { id += "_steam" }
                var n = 2
                let base = id
                while used.contains(id) { id = "\(base)#\(n)"; n += 1 }
                used.insert(id)
                result[i].id = id
                result[i].hasAmbiguousDuplicate = indices.contains {
                    $0 != i && result[$0].source == result[i].source
                }
                result[i].duplicateFolders = indices.filter { $0 != i }.map { result[$0].folder }
            }
        }
        return result
    }

    private static func subdirectories(_ path: String) -> [URL] {
        guard !path.isEmpty else { return [] }
        let url = URL(fileURLWithPath: path)
        let items = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        return items.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }
}
