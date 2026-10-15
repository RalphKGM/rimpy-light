import Foundation

/// Reads a mod folder's About/About.xml into a `Mod`.
enum AboutParser {
    static func parse(folder: URL, source: ModSource, gameVersion: String) -> Mod? {
        let aboutDir = folder.appendingPathComponent("About")
        guard let aboutFile = findFile(in: aboutDir, matching: { $0.lowercased() == "about.xml" }),
              let data = try? Data(contentsOf: aboutFile),
              let root = parseRoot(data)
        else { return nil }

        let folderName = folder.lastPathComponent
        let rawId = text(root, "packageId") ?? folderName
        let packageId = rawId.lowercased()

        var supported = list(child(root, "supportedVersions"))
        if supported.isEmpty, let target = text(root, "targetVersion") {
            supported = [majorMinor(target)]
        }

        var authors = text(root, "author") ?? ""
        let authorList = list(child(root, "authors"))
        if authors.isEmpty, !authorList.isEmpty { authors = authorList.joined(separator: ", ") }

        var workshopId: String?
        if let idFile = findFile(in: aboutDir, matching: { $0.lowercased() == "publishedfileid.txt" }),
           let raw = try? String(contentsOf: idFile, encoding: .utf8) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { workshopId = trimmed }
        }
        if workshopId == nil, source == .workshop, Int(folderName) != nil { workshopId = folderName }

        let preview = findFile(in: aboutDir) { name in
            let lower = name.lowercased()
            return lower == "preview.png" || lower == "preview.jpg" || lower == "preview.gif"
        }

        return Mod(
            id: packageId,
            packageId: packageId,
            displayPackageId: rawId,
            name: text(root, "name") ?? folderName,
            authors: authors,
            description: cleanDescription(text(root, "description") ?? ""),
            url: text(root, "url"),
            source: source,
            folder: folder,
            workshopId: workshopId,
            supportedVersions: supported,
            dependencies: dependencies(root, gameVersion: gameVersion),
            loadAfter: Set(versioned(root, "loadAfter", gameVersion).map { $0.lowercased() }),
            loadBefore: Set(versioned(root, "loadBefore", gameVersion).map { $0.lowercased() }),
            forceLoadAfter: Set(list(child(root, "forceLoadAfter")).map { $0.lowercased() }),
            forceLoadBefore: Set(list(child(root, "forceLoadBefore")).map { $0.lowercased() }),
            incompatibleWith: Set(versioned(root, "incompatibleWith", gameVersion).map { $0.lowercased() }),
            previewURL: preview
        )
    }

    // MARK: - XML helpers

    private static func parseRoot(_ data: Data) -> XMLElement? {
        if let doc = try? XMLDocument(data: data, options: []) { return doc.rootElement() }
        // Some mods ship slightly malformed XML; tidy mode recovers most of them.
        return (try? XMLDocument(data: data, options: [.documentTidyXML]))?.rootElement()
    }

    static func child(_ element: XMLElement?, _ name: String) -> XMLElement? {
        let lower = name.lowercased()
        return element?.children?.lazy
            .compactMap { $0 as? XMLElement }
            .first { $0.name?.lowercased() == lower }
    }

    private static func text(_ element: XMLElement, _ name: String) -> String? {
        guard let value = child(element, name)?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    private static func list(_ element: XMLElement?) -> [String] {
        (element?.children ?? []).compactMap { node in
            guard let el = node as? XMLElement, el.name == "li",
                  let value = el.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { return nil }
            return value
        }
    }

    /// RimWorld uses `<fieldByVersion><v1.7>` when it has an entry for the running
    /// version and falls back to the plain `<field>` list otherwise.
    private static func versionedElement(_ root: XMLElement, _ name: String, _ gameVersion: String) -> XMLElement? {
        if let byVersion = child(root, name + "ByVersion"), let entry = child(byVersion, "v" + gameVersion) {
            return entry
        }
        return child(root, name)
    }

    private static func versioned(_ root: XMLElement, _ name: String, _ gameVersion: String) -> [String] {
        list(versionedElement(root, name, gameVersion))
    }

    private static func dependencies(_ root: XMLElement, gameVersion: String) -> [ModDependency] {
        let container = versionedElement(root, "modDependencies", gameVersion)
        return (container?.children ?? []).compactMap { node in
            guard let li = node as? XMLElement, li.name == "li",
                  let pid = text(li, "packageId") else { return nil }
            let alternatives = list(child(li, "alternativePackageIds"))
            return ModDependency(
                packageIds: ([pid] + alternatives).map { $0.lowercased() },
                displayName: text(li, "displayName") ?? pid,
                workshopURL: text(li, "steamWorkshopUrl")
            )
        }
    }

    // MARK: - Misc

    static func findFile(in dir: URL, matching predicate: (String) -> Bool) -> URL? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.sorted().first(where: predicate).map { dir.appendingPathComponent($0) }
    }

    static func majorMinor(_ version: String) -> String {
        let parts = version.split(whereSeparator: { !$0.isNumber })
        guard parts.count >= 2 else { return version }
        return "\(parts[0]).\(parts[1])"
    }

    /// Strips Unity rich-text tags and BBCode that mod authors put in descriptions.
    private static func cleanDescription(_ raw: String) -> String {
        raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\[/?[a-zA-Z0-9=*#:/._?-]+\\]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\n", with: "\n")
    }
}
