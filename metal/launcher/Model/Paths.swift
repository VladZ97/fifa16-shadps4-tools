// SPDX-License-Identifier: GPL-2.0-or-later
// FIFA 16 launcher: every location the launcher uses, derived from two roots: the app bundle
// (read-only payload: emulator, GPU host, run.sh, renderer settings) and the data folder
// (~/Library/Application Support/FIFA 16: settings, state, the emulator's user folder, runs).
// Both roots are injectable so the tests never touch the real data folder or bundle.
import Foundation

struct Paths: Equatable {
    /// Data folder name (~/Library/Application Support/FIFA 16): kept across the rename to F16.app so
    /// existing settings, caches and saves stay where they are.
    static let appName = "FIFA 16"
    /// What the app calls itself on screen.
    static let displayName = "F16"
    static let titleID = "CUSA02138"

    let dataDir: URL
    let bundle: URL

    init(dataDir: URL, bundle: URL) {
        self.dataDir = dataDir
        self.bundle = bundle
    }

    /// The real roots: the running app's bundle and the user's Application Support.
    static func live() -> Paths {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        // FIFA16_DATA_DIR: a separate data folder (testing a build beside the installed app).
        let override = ProcessInfo.processInfo.environment["FIFA16_DATA_DIR"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        return Paths(dataDir: override ?? support.appendingPathComponent(appName), bundle: Bundle.main.bundleURL)
    }

    // MARK: bundle payload (make_app.sh fills these)

    var resources: URL { bundle.appendingPathComponent("Contents/Resources") }
    /// The launch logic. Play runs `/bin/bash run.sh <mode>` with the folders in the environment.
    var runScript: URL { resources.appendingPathComponent("run.sh") }
    var bbportIni: URL { resources.appendingPathComponent("bbport.ini") }
    var configTemplate: URL { resources.appendingPathComponent("config.template.json") }
    var emulator: URL { resources.appendingPathComponent("emulator/shadps4") }
    /// The mod manager: compiled engine, 7-Zip and the files it reads. Needs nothing installed.
    var modResources: URL { resources.appendingPathComponent("fifamod") }
    var modEngine: URL { modResources.appendingPathComponent("engine/fifamod") }
    var sevenZip: URL { modResources.appendingPathComponent("7zz") }
    var unrar: URL { modResources.appendingPathComponent("unrar") }
    /// The GPU host app (Game Mode, direct presentation). The emulator runs the -macos27 sibling
    /// on macOS 27, so that copy is the one that must exist.
    var hostBundle: URL { bundle.appendingPathComponent("Contents/Helpers/F16 GPU.app") }
    var gpuHost: URL { hostBundle.appendingPathComponent("Contents/MacOS/bbgpu-host") }
    var gpuHostMacOS27: URL { URL(fileURLWithPath: gpuHost.path + "-macos27") }

    // MARK: data folder (writable)

    var settingsFile: URL { dataDir.appendingPathComponent("settings.json") }
    var stateFile: URL { dataDir.appendingPathComponent("state.json") }
    /// shadPS4's user folder for this app (run.sh points the emulator at it).
    var user: URL { dataDir.appendingPathComponent("user") }
    var config: URL { user.appendingPathComponent("config.json") }
    /// Where the emulator looks for the shader cache: since 0.5.1-i a link into the savegame folder
    /// (GameFolders.shaderCache); a real folder only until the first Play of that version.
    var shaderCache: URL { user.appendingPathComponent("cache/\(Self.titleID)") }
    var runs: URL { dataDir.appendingPathComponent("runs") }
    /// The mod library of this app: registry, merged tree and, unless another folder is chosen, the mods.
    var modStore: URL { dataDir.appendingPathComponent("mods") }
    /// Savegames when the user has not chosen a folder.
    var defaultSaves: URL { dataDir.appendingPathComponent("saves") }

    /// The newest run folder (run.sh names them by timestamp, so the lexically last one).
    func latestRun() -> URL? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: runs.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }.sorted().reversed().lazy.map { self.runs.appendingPathComponent($0) }.first { url in
            var dir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &dir) && dir.boolValue
        }
    }
}

/// The four folders the user chooses, resolved against the settings and the data folder.
struct GameFolders: Equatable {
    var game: URL?
    var update: URL?
    var mods: URL?
    var saves: URL

    init(settings: LauncherSettings, paths: Paths) {
        func url(_ s: String) -> URL? {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : URL(fileURLWithPath: (t as NSString).expandingTildeInPath)
        }
        game = url(settings.gameDir)
        update = url(settings.updateDir)
        mods = url(settings.modsDir)
        saves = url(settings.savesDir) ?? paths.defaultSaves
    }

    /// The shader cache the game builds while it runs: kept with the savegames (run.sh links the
    /// emulator's <data>/user/cache to <saves>/cache). Nothing of it ships with the app.
    var shaderCache: URL { saves.appendingPathComponent("cache/\(Paths.titleID)") }

    var eboot: URL? { game?.appendingPathComponent("eboot.bin") }
    var paramSFO: URL? { game?.appendingPathComponent("sce_sys/param.sfo") }
    /// The game's header art, shown in the window when present.
    var artwork: URL? { game?.appendingPathComponent("sce_sys/pic1.png") }
}
