// SPDX-License-Identifier: GPL-2.0-or-later
// FIFA 16 launcher: settings.json (the four folders and the few options) and the environment
// Play hands the bundled run.sh. run.sh owns every emulator and bridge variable; the launcher
// passes the folders, and an option only when it differs from run.sh's default.
import Foundation

enum RunMode: String, Codable, CaseIterable, Identifiable {
    /// run.sh play: emulator log reduced to errors, no screenshot monitor (the default).
    case play
    /// run.sh start: full log plus the screenshot/stats monitor (diagnostics).
    case start
    var id: String { rawValue }
    var label: String { self == .play ? "Play" : "Diagnostics (start)" }
}

struct LauncherSettings: Codable, Equatable {
    /// Folder with eboot.bin and sce_sys/ (the dumped CUSA02138 folder).
    var gameDir = ""
    /// Folder of update 1.07 (eboot.bin or sce_sys/ inside); empty: the base game runs.
    var updateDir = ""
    /// Where mods are kept, or an existing library or patch folder (ModLibrary); empty: the app's data folder.
    var modsDir = ""
    /// Off: the game runs without any mods, whatever is installed.
    var modsEnabled = true
    /// Savegames; empty: <data dir>/saves.
    var savesDir = ""
    /// BB_FULLSCREEN (run.sh default 1).
    var fullscreen = true
    /// BB_FRAME_STATS=1: frame/latency stats in the log every 5 s (unset by default).
    var frameStats = false
    /// MTL_HUD_ENABLED=1: Apple's Metal Performance HUD (unset by default).
    var metalHUD = false
    /// BB_PRESENT_MODE=Immediate: present without display sync (lower latency, can tear; unset by default).
    var lowLatency = false
    /// run.sh's mode argument.
    var mode = RunMode.play

    /// The option variables the settings own: removed from the inherited environment, then set
    /// when the setting differs from run.sh's default.
    static let ownedKeys = ["BB_FULLSCREEN", "BB_FRAME_STATS", "MTL_HUD_ENABLED", "BB_PRESENT_MODE"]
    /// The folder variables, always set (empty when unset) so run.sh never sees a stale value.
    static let folderKeys = ["FIFA_APP", "FIFA_DATA_DIR", "FIFA_GAME_DIR", "FIFA_UPDATE_DIR", "FIFA_MODS_DIR", "FIFA_SAVES_DIR"]
    /// The keys `--cli set` accepts.
    static let settableKeys = ["gameDir", "updateDir", "modsDir", "modsEnabled", "savesDir", "fullscreen", "lowLatency", "frameStats", "metalHUD", "mode"]

    init() {}

    init(from decoder: Decoder) throws {
        // Missing keys keep the defaults (older or hand-written files).
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gameDir = try c.decodeIfPresent(String.self, forKey: .gameDir) ?? ""
        updateDir = try c.decodeIfPresent(String.self, forKey: .updateDir) ?? ""
        modsDir = try c.decodeIfPresent(String.self, forKey: .modsDir) ?? ""
        modsEnabled = try c.decodeIfPresent(Bool.self, forKey: .modsEnabled) ?? true
        savesDir = try c.decodeIfPresent(String.self, forKey: .savesDir) ?? ""
        fullscreen = try c.decodeIfPresent(Bool.self, forKey: .fullscreen) ?? true
        frameStats = try c.decodeIfPresent(Bool.self, forKey: .frameStats) ?? false
        metalHUD = try c.decodeIfPresent(Bool.self, forKey: .metalHUD) ?? false
        lowLatency = try c.decodeIfPresent(Bool.self, forKey: .lowLatency) ?? false
        mode = (try? c.decodeIfPresent(RunMode.self, forKey: .mode)) ?? .play
    }

    /// Only the differences from run.sh's defaults.
    var overrides: [String: String] {
        var env: [String: String] = [:]
        if !fullscreen { env["BB_FULLSCREEN"] = "0" }
        if frameStats { env["BB_FRAME_STATS"] = "1" }
        if metalHUD { env["MTL_HUD_ENABLED"] = "1" }
        if lowLatency { env["BB_PRESENT_MODE"] = "Immediate" }
        return env
    }

    /// The folders as run.sh reads them.
    func folderEnvironment(paths: Paths) -> [String: String] {
        let f = GameFolders(settings: self, paths: paths)
        return [
            "FIFA_APP": paths.bundle.path,
            "FIFA_DATA_DIR": paths.dataDir.path,
            "FIFA_GAME_DIR": f.game?.path ?? "",
            "FIFA_UPDATE_DIR": f.update?.path ?? "",
            "FIFA_MODS_DIR": modsEnabled ? ModLibrary.locate(settings: self, paths: paths).overlay()?.path ?? "" : "",
            "FIFA_SAVES_DIR": f.saves.path,
        ]
    }

    /// The environment for `/bin/bash run.sh <mode>`: `base` without the owned keys, plus the
    /// folders and the overrides.
    func launchEnvironment(base: [String: String], paths: Paths) -> [String: String] {
        var env = base
        for key in Self.ownedKeys { env.removeValue(forKey: key) }
        env.merge(folderEnvironment(paths: paths)) { _, new in new }
        env.merge(overrides) { _, new in new }
        return env
    }

    /// `--cli set <key> <value>`: folders as paths (empty clears), booleans as true/false/1/0, mode as play/start.
    mutating func set(_ key: String, _ value: String) throws {
        func bool() throws -> Bool {
            switch value.lowercased() {
            case "1", "true", "yes", "on": return true
            case "0", "false", "no", "off": return false
            default: throw SetError.badValue(key, value)
            }
        }
        switch key {
        case "gameDir": gameDir = value
        case "updateDir": updateDir = value
        case "modsDir": modsDir = value
        case "modsEnabled": modsEnabled = try bool()
        case "savesDir": savesDir = value
        case "fullscreen": fullscreen = try bool()
        case "lowLatency": lowLatency = try bool()
        case "frameStats": frameStats = try bool()
        case "metalHUD": metalHUD = try bool()
        case "mode":
            guard let m = RunMode(rawValue: value) else { throw SetError.badValue(key, value) }
            mode = m
        default: throw SetError.unknownKey(key)
        }
    }

    enum SetError: Error, CustomStringConvertible {
        case unknownKey(String), badValue(String, String)
        var description: String {
            switch self {
            case .unknownKey(let k): return "unknown setting \(k); one of \(LauncherSettings.settableKeys.joined(separator: ", "))"
            case .badValue(let k, let v): return "bad value \(v) for \(k)"
            }
        }
    }

    static func load(from url: URL) -> LauncherSettings {
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(LauncherSettings.self, from: data) else { return LauncherSettings() }
        return settings
    }

    func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

enum LaunchEnvironment {
    /// The base environment for run.sh: the launcher's own (a Finder launch has launchd's), with
    /// the login shell's PATH (so python3 and friends resolve as in Terminal), LANG as Terminal
    /// sets it, and without the launcher's bundle identity.
    static func base(inherited: [String: String], loginPath: String?, home: String) -> [String: String] {
        var env = inherited
        env.removeValue(forKey: "__CFBundleIdentifier")
        if let path = loginPath?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
            env["PATH"] = path
        } else if (env["PATH"] ?? "").isEmpty {
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        }
        if (env["HOME"] ?? "").isEmpty { env["HOME"] = home }
        if (env["LANG"] ?? "").isEmpty { env["LANG"] = "en_US.UTF-8" }
        return env
    }

    /// The login shell's PATH (`zsh -l`: .zshenv and .zprofile, as a Terminal window has before .zshrc).
    static func loginPath() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-l", "-c", "printf %s \"$PATH\""]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
