# RimPy Light

A small native macOS mod manager for RimWorld, built with SwiftUI. It covers the
everyday parts of RimPy: scan mods, edit the active list, sort, check problems and
save to `ModsConfig.xml`

An independent app and not a port of rimpy

## Build & run

```sh
./scripts/build-app.sh          # → dist/RimPy Light.app
swift run                       # or run straight from the package
```

Requires macOS 14+ and the Swift toolchain (Command Line Tools are enough).

Tests use Swift Testing. With only the Command Line Tools installed, point SwiftPM at its frameworks:

```sh
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
swift test -Xswiftc -F -Xswiftc $F -Xlinker -F -Xlinker $F -Xlinker -rpath -Xlinker $F \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```

Read-only report of what the app sees and what Sort would change (never writes anything):

```sh
.build/debug/RimpyLight --check [--order] [--explain <packageId>]
```

## Features

- Detects the Steam install (including extra Steam libraries), `Data/` (Core + DLCs),
  `Mods/`, the workshop folder and `~/Library/Application Support/RimWorld/Config`.
  You can change any of them in Settings (⌘,).
- Inactive and active lists with filtering, multi-select, drag to reorder or (de)activate,
  and double-click to toggle.
- Details pane: preview image, metadata, issues with one-click fixes, Finder and Workshop links.
- Checks for missing or inactive dependencies, incompatibilities, load-order violations,
  mods not marked for the running game version, duplicate packageIds and mods that aren't installed.
- **Sort**: a topological sort over
  - `modDependencies`, `loadAfter`/`loadBefore` (including `…ByVersion`), `forceLoadAfter`/`forceLoadBefore`
  - community rules ([RimSort/Community-Rules-Database](https://github.com/RimSort/Community-Rules-Database), the same JSON schema as RimPy's `communityRules.json`)
  - your own rules (load after/before, pin to top/bottom), stored in
    `~/Library/Application Support/RimpyLight/userRules.json`

  Ties go to Harmony and top-pinned mods first, then Core/DLCs, then normal mods, then
  bottom-pinned mods. Within a group the current order is kept, so a sort only moves what the
  rules require. If rules form a cycle, the weakest rule is dropped
  (community < About.xml < dependency < yours < forced) and the status bar names it.
- Add Missing Dependencies activates installed mods that are required, repeating until none are left.
- Save writes `ModsConfig.xml` and keeps the previous file as `ModsConfig.xml.bak`.
- Import from `ModsConfig.xml`, a `.rml` list or a save file (`.rws`); export to `.rml`;
  copy the list to the clipboard with Workshop links.
- Play launches through Steam (`steam://rungameid/294100`) or opens the app bundle directly.

Left out on purpose: texture conversion, mod stripping and merging, SteamCMD downloads,
log analysis and mod-pack creation.

## Layout

```
Sources/RimpyLight/
  Model/        About.xml parsing, scanning, rules, sorting, validation, ModsConfig I/O
  Views/        SwiftUI panes and settings
  AppState.swift
  CheckCommand.swift
Tests/RimpyLightTests/
```

## How the feature set was chosen

The feature set comes from a static look at RimPy 1.2.6.28's Windows release. That
release is a Nuitka-compiled Python/PyQt5 app, so the evidence is its packaged UI strings
and its bundled `communityRules.json` schema; RimPy was never run. Its exact sort
algorithm wasn't recovered: a Hopper pass on the 106 MB executable didn't finish. The
sorter here is its own design, described above.
