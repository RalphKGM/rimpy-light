import Foundation

struct GamePaths: Codable, Equatable, Sendable {
    var gameFolder = ""
    var configFolder = ""
    var workshopFolder = ""
    var localModsFolder = ""

    private static let defaultsKey = "gamePaths"
    private static let rimworldAppId = "294100"

    var modsConfigURL: URL { URL(fileURLWithPath: configFolder).appendingPathComponent("ModsConfig.xml") }
    var modListsFolder: URL {
        URL(fileURLWithPath: configFolder).deletingLastPathComponent().appendingPathComponent("ModLists")
    }

    /// Folder holding Core and the DLCs. On the Steam Mac build it sits next to
    /// the app bundle; other builds keep it inside the bundle.
    var dataFolder: String {
        let game = URL(fileURLWithPath: gameFolder)
        let candidates = [
            game.appendingPathComponent("Data"),
            game.appendingPathComponent("RimWorldMac.app/Data"),
            game.appendingPathComponent("RimWorldMac.app/Contents/Resources/Data"),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("Core").path) }?.path ?? ""
    }

    /// Full version string like "1.7.4977 rev1248".
    var fullGameVersion: String? {
        let url = URL(fileURLWithPath: gameFolder).appendingPathComponent("Version.txt")
        return (try? String(contentsOf: url, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isSteamInstall: Bool { gameFolder.contains("/steamapps/common/") }

    // MARK: - Persistence

    static func load() -> GamePaths {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode(GamePaths.self, from: data),
           !saved.gameFolder.isEmpty {
            return saved
        }
        return detect()
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    // MARK: - Detection

    static func detect() -> GamePaths {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var paths = GamePaths()

        for library in steamLibraries() {
            let game = library.appendingPathComponent("steamapps/common/RimWorld")
            if fm.fileExists(atPath: game.path), paths.gameFolder.isEmpty {
                paths.gameFolder = game.path
            }
            let workshop = library.appendingPathComponent("steamapps/workshop/content/\(rimworldAppId)")
            if fm.fileExists(atPath: workshop.path), paths.workshopFolder.isEmpty {
                paths.workshopFolder = workshop.path
            }
        }

        if paths.gameFolder.isEmpty {
            for candidate in ["/Applications/RimWorld", home.appendingPathComponent("Applications/RimWorld").path]
            where fm.fileExists(atPath: candidate) {
                paths.gameFolder = candidate
                break
            }
        }

        if !paths.gameFolder.isEmpty {
            paths.localModsFolder = URL(fileURLWithPath: paths.gameFolder).appendingPathComponent("Mods").path
        }

        let config = home.appendingPathComponent("Library/Application Support/RimWorld/Config")
        if fm.fileExists(atPath: config.path) { paths.configFolder = config.path }

        return paths
    }

    /// The default Steam folder plus any extra libraries listed in libraryfolders.vdf.
    private static func steamLibraries() -> [URL] {
        let steam = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Steam")
        var libraries = [steam]
        let vdf = steam.appendingPathComponent("steamapps/libraryfolders.vdf")
        if let text = try? String(contentsOf: vdf, encoding: .utf8),
           let regex = try? NSRegularExpression(pattern: "\"path\"\\s+\"([^\"]+)\"") {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range(at: 1), in: text) {
                    let url = URL(fileURLWithPath: String(text[range]))
                    if url.standardizedFileURL != steam.standardizedFileURL { libraries.append(url) }
                }
            }
        }
        return libraries
    }
}
