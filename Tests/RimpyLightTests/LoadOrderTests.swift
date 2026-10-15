import Foundation
import Testing
@testable import RimpyLight

struct LoadOrderTests {
    private func mod(_ id: String, source: ModSource = .workshop, after: [String] = [], before: [String] = [],
                     deps: [String] = [], versions: [String] = ["1.7"]) -> Mod {
        Mod(id: id, packageId: id, displayPackageId: id, name: id, authors: "", description: "", url: nil,
            source: source, folder: URL(fileURLWithPath: "/tmp/\(id)"), workshopId: nil,
            supportedVersions: versions,
            dependencies: deps.map { ModDependency(packageIds: [$0], displayName: $0, workshopURL: nil) },
            loadAfter: Set(after), loadBefore: Set(before), forceLoadAfter: [], forceLoadBefore: [],
            incompatibleWith: [], previewURL: nil)
    }

    @Test func harmonyThenOfficialThenDependencies() {
        let mods = [
            mod("b", deps: ["a"]),
            mod("a"),
            mod("ludeon.rimworld", source: .official),
            mod("brrainz.harmony"),
        ]
        let order = LoadOrder.sort(mods, rules: RuleContext()).order
        #expect(order == ["brrainz.harmony", "ludeon.rimworld", "a", "b"])
    }

    /// Regression: a mod required before Core that sat low in the list used to
    /// let every other mod above it jump ahead of Core.
    @Test func modsRequiredBeforeCorePullUpInsteadOfDelayingCore() {
        let mods = [
            mod("brrainz.harmony"),
            mod("a"), mod("b"), mod("c"),
            mod("fastload", before: ["ludeon.rimworld"]),
            mod("ludeon.rimworld", source: .official),
            mod("ludeon.rimworld.biotech", source: .official),
        ]
        let order = LoadOrder.sort(mods, rules: RuleContext()).order
        #expect(order == ["brrainz.harmony", "fastload", "ludeon.rimworld", "ludeon.rimworld.biotech", "a", "b", "c"])
    }

    @Test func validatorFlagsModsPlacedBeforeCore() {
        let core = mod("ludeon.rimworld", source: .official)
        let early = mod("fastload", before: ["ludeon.rimworld"])
        let stray = mod("stray")
        let installed = Dictionary(uniqueKeysWithValues: [core, early, stray].map { ($0.id, $0) })
        let result = Validator.validate(active: [stray, early, core], installed: installed, rules: RuleContext(), gameVersion: "1.7")
        #expect(result.byMod["stray"]?.first?.severity == .error)
        #expect(result.byMod["fastload"] == nil)
    }

    @Test func keepsCurrentOrderWhenUnconstrained() {
        let mods = [mod("z"), mod("m"), mod("a")]
        #expect(LoadOrder.sort(mods, rules: RuleContext()).order == ["z", "m", "a"])
    }

    @Test func loadBeforeAndBottomRule() {
        var rules = RuleContext()
        rules.community.bottom = ["last"]
        let mods = [mod("last"), mod("x"), mod("y", before: ["x"])]
        #expect(LoadOrder.sort(mods, rules: rules).order == ["y", "x", "last"])
    }

    @Test func userRuleBeatsCommunityRule() {
        var rules = RuleContext()
        rules.community.loadAfter = ["a": ["b"]]
        rules.user.loadBefore = ["a": ["b"]]
        let order = LoadOrder.sort([mod("b"), mod("a")], rules: rules).order
        #expect(order == ["a", "b"])
    }

    @Test func cycleIsBrokenAtWeakestRule() {
        var rules = RuleContext()
        rules.community.loadAfter = ["a": ["c"]]
        let mods = [mod("a"), mod("b", deps: ["a"]), mod("c", after: ["b"])]
        let result = LoadOrder.sort(mods, rules: rules)
        #expect(result.order == ["a", "b", "c"])
        #expect(result.broken.map(\.kind) == [.community])
    }

    @Test func validatorFlagsMissingDependencyAndOrder() {
        let core = mod("ludeon.rimworld", source: .official, versions: ["1.6"])
        let lib = mod("lib")
        let user = mod("user", deps: ["lib"])
        let installed = Dictionary(uniqueKeysWithValues: [core, lib, user].map { ($0.id, $0) })

        let inactive = Validator.validate(active: [core, user], installed: installed, rules: RuleContext(), gameVersion: "1.7")
        #expect(inactive.byMod["user"]?.first?.fix == .activate("lib"))
        #expect(inactive.byMod["ludeon.rimworld"] == nil, "official content is never version-flagged")

        let misordered = Validator.validate(active: [core, user, lib], installed: installed, rules: RuleContext(), gameVersion: "1.7")
        #expect(misordered.byMod["user"]?.first?.fix == .sort)
    }

    @Test func steamSuffixForDuplicates() {
        let local = mod("dup", source: .local)
        let steam = mod("dup", source: .workshop)
        let ids = Set(ModScanner.assignIds([steam, local]).map(\.id))
        #expect(ids == ["dup", "dup_steam"])
    }

    /// Regression: two Steam copies of one mod used to be saved as `dup#2`,
    /// an id RimWorld doesn't know, so neither copy loaded.
    @Test func ambiguousDuplicatesAreFlaggedAndNeverSavedWithSuffix() {
        let mods = ModScanner.assignIds([mod("dup", source: .workshop), mod("dup", source: .workshop)])
        #expect(mods.allSatisfy { $0.hasAmbiguousDuplicate })
        #expect(Set(mods.map { $0.gameId }) == ["dup"])
        #expect(mods.contains { $0.id == "dup#2" })
    }
}

struct ParsingTests {
    @Test func aboutXmlByVersion() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("About"), withIntermediateDirectories: true)
        try """
        <?xml version="1.0" encoding="utf-8"?>
        <ModMetaData>
          <name>Test</name>
          <packageId>Me.Test</packageId>
          <supportedVersions><li>1.6</li><li>1.7</li></supportedVersions>
          <loadAfter><li>Old.Thing</li></loadAfter>
          <loadAfterByVersion><v1.7><li>New.Thing</li></v1.7></loadAfterByVersion>
          <modDependencies>
            <li><packageId>brrainz.harmony</packageId><displayName>Harmony</displayName>
              <alternativePackageIds><li>other.harmony</li></alternativePackageIds></li>
          </modDependencies>
        </ModMetaData>
        """.write(to: dir.appendingPathComponent("About/About.xml"), atomically: true, encoding: .utf8)

        let mod = try #require(AboutParser.parse(folder: dir, source: .local, gameVersion: "1.7"))
        #expect(mod.id == "me.test")
        #expect(mod.loadAfter == ["new.thing"])
        #expect(mod.dependencies.first?.packageIds == ["brrainz.harmony", "other.harmony"])
        #expect(AboutParser.parse(folder: dir, source: .local, gameVersion: "1.6")?.loadAfter == ["old.thing"])
    }

    @Test func modsConfigRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".xml")
        try ModListIO.writeModsConfig(to: url, version: "1.7.4977 rev1248", active: ["brrainz.harmony", "ludeon.rimworld"],
                                      knownExpansions: ["ludeon.rimworld.biotech"])
        let read = try ModListIO.read(url)
        #expect(read.ids == ["brrainz.harmony", "ludeon.rimworld"])
        #expect(read.version == "1.7.4977 rev1248")
        #expect(read.knownExpansions == ["ludeon.rimworld.biotech"])
    }
}
