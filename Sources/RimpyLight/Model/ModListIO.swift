import Foundation

/// Reads and writes the XML formats RimWorld uses for mod lists.
enum ModListIO {
    struct ParsedList {
        var ids: [String] = []
        var names: [String] = []
        var version: String?
        var knownExpansions: [String] = []
    }

    /// Reads ModsConfig.xml, a RimWorld .rml mod list, or a save file (.rws).
    /// Only the header is parsed, so large saves stay fast.
    static func read(_ url: URL) throws -> ParsedList {
        guard let parser = XMLParser(contentsOf: url) else { throw CocoaError(.fileReadNoSuchFile) }
        let delegate = HeaderParser()
        parser.delegate = delegate
        parser.parse()
        if delegate.result.ids.isEmpty, let error = parser.parserError, !delegate.aborted { throw error }
        return delegate.result
    }

    static func writeModsConfig(to url: URL, version: String, active: [String], knownExpansions: [String]) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            let backup = url.appendingPathExtension("bak")
            try? FileManager.default.removeItem(at: backup)
            try FileManager.default.copyItem(at: url, to: backup)
        }
        var xml = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<ModsConfigData>\n"
        xml += "  <version>\(escape(version))</version>\n"
        xml += "  <activeMods>\n" + active.map { "    <li>\(escape($0))</li>\n" }.joined() + "  </activeMods>\n"
        xml += "  <knownExpansions>\n" + knownExpansions.map { "    <li>\(escape($0))</li>\n" }.joined() + "  </knownExpansions>\n"
        xml += "</ModsConfigData>\n"
        try xml.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Writes the same .rml format the game's own mod list saver produces.
    static func writeRML(to url: URL, version: String, mods: [Mod]) throws {
        func items(_ values: [String], indent: String) -> String {
            values.map { "\(indent)<li>\(escape($0))</li>\n" }.joined()
        }
        let ids = mods.map(\.gameId)
        let steamIds = mods.map { $0.source == .workshop ? ($0.workshopId ?? "0") : "0" }
        let names = mods.map(\.name)
        var xml = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<savedModList>\n\t<meta>\n"
        xml += "\t\t<gameVersion>\(escape(version))</gameVersion>\n"
        xml += "\t\t<modIds>\n\(items(ids, indent: "\t\t\t"))\t\t</modIds>\n"
        xml += "\t\t<modSteamIds>\n\(items(steamIds, indent: "\t\t\t"))\t\t</modSteamIds>\n"
        xml += "\t\t<modNames>\n\(items(names, indent: "\t\t\t"))\t\t</modNames>\n"
        xml += "\t</meta>\n\t<modList>\n"
        xml += "\t\t<ids>\n\(items(ids, indent: "\t\t\t"))\t\t</ids>\n"
        xml += "\t\t<names>\n\(items(names, indent: "\t\t\t"))\t\t</names>\n"
        xml += "\t</modList>\n</savedModList>\n"
        try xml.write(to: url, atomically: true, encoding: .utf8)
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private final class HeaderParser: NSObject, XMLParserDelegate {
        var result = ParsedList()
        var aborted = false
        private var stack: [String] = []
        private var text = ""
        private var idsDone = false
        private var namesDone = false

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            stack.append(name)
            text = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let parent = stack.count >= 2 ? stack[stack.count - 2] : ""
            switch name {
            case "li" where (parent == "activeMods" || parent == "modIds") && !idsDone:
                result.ids.append(value.lowercased())
            case "li" where parent == "modNames" && !namesDone:
                result.names.append(value)
            case "li" where parent == "knownExpansions":
                result.knownExpansions.append(value.lowercased())
            case "version", "gameVersion":
                if result.version == nil, !value.isEmpty { result.version = value }
            case "activeMods", "modIds":
                idsDone = idsDone || !result.ids.isEmpty
            case "modNames":
                namesDone = true
            case "meta":
                // Save files continue with megabytes of world data we don't need.
                aborted = true
                parser.abortParsing()
            default:
                break
            }
            stack.removeLast()
            text = ""
        }
    }
}
