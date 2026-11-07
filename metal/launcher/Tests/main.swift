// SPDX-License-Identifier: GPL-2.0-or-later
// Model tests for the FIFA 16 launcher (bash build.sh --test). One PASS line or exit 1.
//
// Everything runs against a throw-away data folder and a fake bundle created here, never the
// real ~/Library/Application Support/FIFA 16 or the real app. The launch test runs a stub
// run.sh that records the environment it got, so the exact variables Play passes are checked
// against a golden table for the default settings and for every option.
import Foundation

var failures = 0
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ what: String, line: Int = #line) {
    checks += 1
    if !condition() {
        failures += 1
        print("FAIL (Tests/main.swift:\(line)): \(what)")
    }
}

let fm = FileManager.default
final class LineBox: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func add(_ line: String) { lock.withLock { lines.append(line) } }
    var all: [String] { lock.withLock { lines } }
}

let scratch = fm.temporaryDirectory.appendingPathComponent("fifa-launcher-tests-\(getpid())")
try? fm.removeItem(at: scratch)
defer { try? fm.removeItem(at: scratch) }

func write(_ text: String, _ url: URL, executable: Bool = false) {
    try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? text.write(to: url, atomically: true, encoding: .utf8)
    if executable { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
}

// A fake bundle with the payload files the checklist looks for, and a fake game folder.
let bundle = scratch.appendingPathComponent("FIFA 16.app")
let dataDir = scratch.appendingPathComponent("data")
let paths = Paths(dataDir: dataDir, bundle: bundle)
write("#!/bin/bash\n", paths.emulator, executable: true)
write("", paths.gpuHostMacOS27)
write("", paths.gpuHost)
write("renderer=metal\n", paths.bbportIni)
let gameDir = scratch.appendingPathComponent("game/CUSA02138")
write("", gameDir.appendingPathComponent("eboot.bin"))
write("", gameDir.appendingPathComponent("sce_sys/param.sfo"))
let updateDir = scratch.appendingPathComponent("game/CUSA02138-UPDATE")
write("", updateDir.appendingPathComponent("eboot.bin"))
let modsDir = scratch.appendingPathComponent("mods")
try? fm.createDirectory(at: modsDir, withIntermediateDirectories: true)

// The stub run.sh: records its arguments, working folder and environment, prints what the real
// one prints ("run dir : <path>") and leaves a pid file with a process that stays alive.
let stubScript = """
#!/bin/bash
dir="$FIFA_DATA_DIR/runs/$(date +%Y%m%d_%H%M%S)_$$"
mkdir -p "$dir"
printf '%s\\n' "$@" > "$dir/args"
pwd > "$dir/cwd"
env | sort > "$dir/env"
# a long-lived "emulator" detached from run.sh's pipes, as the real nohup'd shadps4 is
nohup sleep 60 >/dev/null 2>&1 </dev/null &
echo $! > "$dir/pid"
disown 2>/dev/null || true
echo "run dir : $dir"
"""
write(stubScript, paths.runScript, executable: true)

// MARK: Paths
do {
    check(paths.config.path == dataDir.path + "/user/config.json", "config under the data folder's user dir")
    check(paths.shaderCache.path.hasSuffix("/user/cache/CUSA02138"), "shader cache path")
    check(paths.defaultSaves.path == dataDir.path + "/saves", "default saves folder")
    check(paths.hostBundle.path == bundle.path + "/Contents/Helpers/F16 GPU.app", "host bundle inside the app")
    check(paths.latestRun() == nil, "no runs yet")
    write("", paths.runs.appendingPathComponent("20260101_000000/emulator.log"))
    write("", paths.runs.appendingPathComponent("20260102_000000/emulator.log"))
    check(paths.latestRun()?.lastPathComponent == "20260102_000000", "latest run is the lexically last folder")
}

// MARK: Settings: defaults, round trip, missing keys, set
do {
    let d = LauncherSettings()
    check(d.gameDir == "" && d.updateDir == "" && d.modsDir == "" && d.savesDir == "", "folders default empty")
    check(d.fullscreen && !d.lowLatency && !d.frameStats && !d.metalHUD && d.mode == .play, "option defaults")
    check(d.overrides.isEmpty, "defaults add no variables")
    var s = LauncherSettings()
    s.gameDir = gameDir.path; s.updateDir = updateDir.path; s.modsDir = modsDir.path; s.savesDir = scratch.path + "/saves"
    s.fullscreen = false; s.lowLatency = true; s.frameStats = true; s.metalHUD = true; s.mode = .start
    let file = dataDir.appendingPathComponent("settings.json")
    try? s.save(to: file)
    check(LauncherSettings.load(from: file) == s, "settings round trip")
    let json = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
    for key in ["gameDir", "updateDir", "modsDir", "savesDir", "fullscreen", "lowLatency", "frameStats", "metalHUD", "mode"] {
        check(json.contains("\"\(key)\""), "settings.json has \(key)")
    }
    write("{\"gameDir\": \"/x\"}", file)
    let partial = LauncherSettings.load(from: file)
    check(partial.gameDir == "/x" && partial.fullscreen && partial.mode == .play, "missing keys keep defaults")
    write("not json", file)
    check(LauncherSettings.load(from: file) == LauncherSettings(), "unreadable file gives defaults")
    check(LauncherSettings.load(from: dataDir.appendingPathComponent("absent.json")) == LauncherSettings(), "absent file gives defaults")
    try? fm.removeItem(at: file)

    var t = LauncherSettings()
    try? t.set("gameDir", "/g"); try? t.set("fullscreen", "0"); try? t.set("lowLatency", "true"); try? t.set("mode", "start"); try? t.set("updateDir", "")
    check(t.gameDir == "/g" && !t.fullscreen && t.lowLatency && t.mode == .start && t.updateDir == "", "--cli set values")
    check((try? t.set("mode", "nope")) == nil, "set rejects a bad mode")
    check((try? t.set("colour", "x")) == nil, "set rejects an unknown key")
    check((try? t.set("metalHUD", "maybe")) == nil, "set rejects a bad boolean")
}

// MARK: Folders and the status checklist
do {
    var s = LauncherSettings()
    var items = InstallStatus.check(paths, settings: s)
    func item(_ title: String) -> StatusItem? { items.first { $0.title == title } }
    check(items.map(\.title) == ["Game folder", "Savegame folder", "Emulator (bundled)", "GPU host (bundled)", "Launch script (bundled)",
                                 "Update folder", "Mods folder", "Mod manager (bundled)", "Emulator config", "Shader cache"], "checklist order")
    check(items.filter(\.bundled).map(\.title) == ["Emulator (bundled)", "GPU host (bundled)", "Launch script (bundled)", "Mod manager (bundled)", "Emulator config", "Shader cache"], "the app's own parts go under Advanced Settings")
    check(item("Game folder")?.ok == false && item("Game folder")?.optional == false, "no game folder blocks Play")
    check(item("Savegame folder")?.ok == true, "default saves folder can be created")
    check(item("Savegame folder")?.detail.contains("created on first Play") == true, "default saves folder reported as to be created")
    check(item("Emulator (bundled)")?.ok == true && item("GPU host (bundled)")?.ok == true && item("Launch script (bundled)")?.ok == true, "bundled payload found")
    check(item("Update folder")?.ok == false && item("Update folder")?.optional == true && item("Update folder")?.detail == "none, base game 1.00 runs", "no update is optional")
    check(item("Mods folder")?.optional == true && item("Mods folder")?.ok == true && item("Mods folder")?.detail == "none", "no mods is optional and no warning")
    check(item("Emulator config")?.ok == false && item("Emulator config")?.optional == true, "config created on first Play")
    check(item("Shader cache")?.optional == true, "shader cache is optional")
    check(InstallStatus.problems(items).map(\.title) == ["Game folder"], "only the game folder blocks")

    s.gameDir = gameDir.path
    items = InstallStatus.check(paths, settings: s)
    check(item("Game folder")?.ok == true && InstallStatus.problems(items).isEmpty, "game folder with eboot.bin and param.sfo: ready")
    let folders = GameFolders(settings: s, paths: paths)
    check(folders.saves == paths.defaultSaves && folders.update == nil && folders.mods == nil, "folders resolve")
    check(folders.eboot?.path == gameDir.path + "/eboot.bin", "eboot path")

    s.gameDir = scratch.appendingPathComponent("game").path
    items = InstallStatus.check(paths, settings: s)
    check(item("Game folder")?.ok == false && item("Game folder")?.detail.contains("missing eboot.bin, sce_sys/param.sfo") == true, "wrong folder names what is missing")

    s.gameDir = gameDir.path
    s.updateDir = updateDir.path
    s.modsDir = modsDir.path
    items = InstallStatus.check(paths, settings: s)
    check(item("Update folder")?.ok == true, "update folder with eboot.bin")
    check(item("Mods folder")?.ok == true, "mods folder exists")
    s.updateDir = scratch.appendingPathComponent("nope").path
    s.modsDir = scratch.appendingPathComponent("nope").path
    items = InstallStatus.check(paths, settings: s)
    check(item("Update folder")?.ok == false && item("Update folder")?.optional == true, "bad update folder never blocks")
    check(item("Mods folder")?.ok == false && item("Mods folder")?.optional == true, "bad mods folder never blocks")
    check(InstallStatus.problems(items).isEmpty, "optional problems do not block Play")

    s.savesDir = "/nonexistent-root-folder/saves"
    items = InstallStatus.check(paths, settings: s)
    check(item("Savegame folder")?.ok == false && item("Savegame folder")?.optional == false, "an uncreatable saves folder blocks Play")
    write("", paths.config)
    write("", paths.shaderCache.appendingPathComponent("a.bin"))
    write("", paths.shaderCache.appendingPathComponent("b.bin"))
    s.savesDir = ""
    items = InstallStatus.check(paths, settings: s)
    check(item("Emulator config")?.ok == true && item("Shader cache")?.detail == "2 files", "config and cache counted")
}

// MARK: The environment Play passes (golden)
do {
    let inherited = ["PATH": "/usr/bin:/bin", "HOME": "/Users/test", "BB_FULLSCREEN": "0", "BB_PRESENT_MODE": "Immediate",
                     "FIFA_GAME_DIR": "/stale", "__CFBundleIdentifier": "x", "KEEP": "1"]
    let base = LaunchEnvironment.base(inherited: inherited, loginPath: "/opt/homebrew/bin:/usr/bin:/bin\n", home: "/Users/test")
    check(base["PATH"] == "/opt/homebrew/bin:/usr/bin:/bin", "login PATH replaces the app's")
    check(base["LANG"] == "en_US.UTF-8", "LANG set when missing")
    check(base["__CFBundleIdentifier"] == nil, "bundle identity removed")
    check(base["KEEP"] == "1", "other variables pass through")
    let noLogin = LaunchEnvironment.base(inherited: ["PATH": ""], loginPath: nil, home: "/Users/test")
    check(noLogin["PATH"]?.hasPrefix("/opt/homebrew/bin") == true && noLogin["HOME"] == "/Users/test", "fallback PATH and HOME")

    var s = LauncherSettings()
    s.gameDir = "/games/CUSA02138"
    var env = s.launchEnvironment(base: base, paths: paths)
    let golden: [String: String] = [
        "FIFA_APP": bundle.path, "FIFA_DATA_DIR": dataDir.path, "FIFA_GAME_DIR": "/games/CUSA02138",
        "FIFA_UPDATE_DIR": "", "FIFA_MODS_DIR": "", "FIFA_SAVES_DIR": dataDir.path + "/saves",
        "PATH": "/opt/homebrew/bin:/usr/bin:/bin", "HOME": "/Users/test", "LANG": "en_US.UTF-8", "KEEP": "1",
    ]
    check(env == golden, "default settings: folders only, inherited BB_* removed, stale FIFA_* replaced: \(env)")
    s.updateDir = "/games/CUSA02138-UPDATE"; s.modsDir = "~/mods"; s.savesDir = "/saves"
    s.fullscreen = false; s.lowLatency = true; s.frameStats = true; s.metalHUD = true
    env = s.launchEnvironment(base: base, paths: paths)
    var golden2 = golden
    golden2["FIFA_UPDATE_DIR"] = "/games/CUSA02138-UPDATE"
    golden2["FIFA_MODS_DIR"] = "" // a folder for mods, not built yet: nothing to hand to the game
    golden2["FIFA_SAVES_DIR"] = "/saves"
    golden2["BB_FULLSCREEN"] = "0"; golden2["BB_PRESENT_MODE"] = "Immediate"; golden2["BB_FRAME_STATS"] = "1"; golden2["MTL_HUD_ENABLED"] = "1"
    check(env == golden2, "every option and folder: \(env)")
    check(s.overrides == ["BB_FULLSCREEN": "0", "BB_PRESENT_MODE": "Immediate", "BB_FRAME_STATS": "1", "MTL_HUD_ENABLED": "1"], "overrides")
    check(GameControl.command(script: paths.runScript, mode: .start) == ["/bin/bash", paths.runScript.path, "start"], "command line")
    check(GameControl.runDirectory(inOutput: "x\nrun dir : /tmp/r1 \nmore") == URL(fileURLWithPath: "/tmp/r1"), "run dir parsed")
    check(GameControl.runDirectory(inOutput: "nothing") == nil, "no run dir")
}

// MARK: Mod library: where it is, what the game gets, the switch
do {
    func dir(_ name: String) -> URL {
        let url = scratch.appendingPathComponent("lib/\(name)")
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func env(_ s: LauncherSettings) -> String? { s.folderEnvironment(paths: paths)["FIFA_MODS_DIR"] }
    func modsItem(_ s: LauncherSettings) -> StatusItem? { InstallStatus.check(paths, settings: s).first { $0.title == "Mods folder" } }
    var s = LauncherSettings()
    check(s.modsEnabled, "mods switch on by default")
    check(try! JSONDecoder().decode(LauncherSettings.self, from: Data("{}".utf8)).modsEnabled, "an older settings file keeps mods on")
    var library = ModLibrary.locate(settings: s, paths: paths)
    check(library.kind == .managed && library.store == paths.modStore && library.modsFolder == nil, "not set: library in the data folder")
    check(library.overlay() == nil && env(s) == "", "nothing built: the game gets no overlay")
    check(modsItem(s)?.ok == true, "no library is fine")

    // An existing fifamod store, chosen by its merged tree (what v0.3 settings hold).
    let store = dir("store")
    let merged = store.appendingPathComponent("merged")
    try? fm.createDirectory(at: merged, withIntermediateDirectories: true)
    fm.createFile(atPath: merged.appendingPathComponent(ModLibrary.marker).path, contents: Data())
    let modsOnDrive = dir("drive/mods")
    let registry = "{\"base\": \"\", \"mods_dir\": \"\(modsOnDrive.path)\", \"mods\": [\"a\", \"b\"]}"
    fm.createFile(atPath: store.appendingPathComponent("mods.json").path, contents: Data(registry.utf8))
    s.modsDir = merged.path
    library = ModLibrary.locate(settings: s, paths: paths)
    check(library.store.path == store.path && library.modsFolder == nil, "a merged tree: its store is used in place")
    check(env(s) == merged.path, "the merged tree goes to the game")
    check(modsItem(s)?.detail == "2 mods installed", "status counts mods")
    s.modsEnabled = false
    check(env(s) == "", "switch off: no overlay, whatever is installed")
    check(modsItem(s)?.ok == true && modsItem(s)?.detail.hasPrefix("off") == true, "switch off is not a warning")
    check(InstallStatus.problems(InstallStatus.check(paths, settings: s)).filter { $0.title == "Mods folder" }.isEmpty, "switch off never blocks")
    s.modsEnabled = true
    s.modsDir = store.path
    check(ModLibrary.locate(settings: s, paths: paths).store.path == store.path, "a folder with mods.json: used in place")
    try? fm.removeItem(at: modsOnDrive)
    check(modsItem(s)?.ok == false && modsItem(s)?.detail.contains("drive connected") == true && modsItem(s)?.optional == true, "mods drive gone: warned, Play not blocked")

    let patch = dir("patch")
    try? fm.createDirectory(at: patch.appendingPathComponent("data"), withIntermediateDirectories: true)
    s.modsDir = patch.path
    library = ModLibrary.locate(settings: s, paths: paths)
    check(library.kind == .plainPatch && library.patchFolder?.path == patch.path && env(s) == patch.path, "a folder with data/: a ready-made patch")
    let plain = dir("plain")
    s.modsDir = plain.path
    library = ModLibrary.locate(settings: s, paths: paths)
    check(library.kind == .managed && library.store == paths.modStore && library.modsFolder?.path == plain.path, "any other folder: mods kept there, store stays on the Mac")

    s.gameDir = "/games/CUSA02138"
    check(ModEngine.prepareCommands(library: library, settings: s) == [["configure", "--game", "/games/CUSA02138", "--mods-dir", plain.path]], "first change creates the registry")
    let env1 = ModEngine.environment(library: library, paths: paths, home: "/Users/test")
    check(env1["FIFAMOD_APP"] == "1" && env1["FIFAMOD_STORE"] == paths.modStore.path && env1["PATH"] == "/usr/bin:/bin"
          && env1["FIFAMOD_7ZZ"] == paths.sevenZip.path && env1["FIFAMOD_UNRAR"] == paths.unrar.path && env1["FIFAMOD_RESOURCES"] == paths.modResources.path, "engine environment: nothing from the shell")

    let log = dir("log").appendingPathComponent("emulator.log")
    fm.createFile(atPath: log.path, contents: Data("x\n[K] Scoreboard: competition 53\nScoreboard: competition 223\nScoreboard: competition 53\nScoreboard: competition 0\n".utf8))
    check(ModEngine.competitions(inLog: log) == [223, 53], "competitions from the log, newest last, 0 ignored")
}

// MARK: Multi-part archives queue as one, by the first part
do {
    let d = URL(fileURLWithPath: "/m")
    check(ModEngine.firstVolume(d.appendingPathComponent("Mod.part2.rar")).lastPathComponent == "Mod.part1.rar", "first volume: partN.rar")
    check(ModEngine.firstVolume(d.appendingPathComponent("Mod.part07.RAR")).lastPathComponent == "Mod.part01.rar", "first volume: zero-padded part")
    check(ModEngine.firstVolume(d.appendingPathComponent("Mod.r03")).lastPathComponent == "Mod.rar", "first volume: old-style .rNN")
    check(ModEngine.firstVolume(d.appendingPathComponent("Mod.7z.002")).lastPathComponent == "Mod.7z.001", "first volume: .7z.NNN")
    check(ModEngine.firstVolume(d.appendingPathComponent("Mod.rar")).lastPathComponent == "Mod.rar", "first volume: a plain archive is unchanged")
    check(ModEngine.firstVolume(d.appendingPathComponent("Party.rar")).lastPathComponent == "Party.rar", "first volume: 'part' in a name is not a volume")
}

// MARK: The compiled engine (FIFA_TEST_ENGINE=<dir with fifamod, 7zz, stock/>)
if let root = ProcessInfo.processInfo.environment["FIFA_TEST_ENGINE"] {
    let engine = URL(fileURLWithPath: root).appendingPathComponent("engine/fifamod")
    let store = scratch.appendingPathComponent("engine-store")
    let lib = ModLibrary(kind: .managed, store: store, modsFolder: nil, patchFolder: nil)
    var e = ModEngine.environment(library: lib, paths: paths)
    e["FIFAMOD_RESOURCES"] = root; e["FIFAMOD_7ZZ"] = root + "/7zz"; e["FIFAMOD_UNRAR"] = root + "/unrar"
    func run(_ args: String...) -> ModEngine.Result { ModEngine.run(executable: engine, args: args, environment: e) }
    func state() -> LibraryState? { try? JSONDecoder.engine.decode(LibraryState.self, from: Data(run("state").output.utf8)) }
    check(state()?.initialised == false, "engine: state before anything exists")
    check(run("configure", "--game", "/games/x", "--build").ok, "engine: configure without a base patch")
    check(state()?.initialised == true && state()?.hasBase == false, "engine: library without a base patch")
    let src = scratch.appendingPathComponent("src/My Mod/data/ui/fonts")
    try? fm.createDirectory(at: src, withIntermediateDirectories: true)
    fm.createFile(atPath: src.appendingPathComponent("a.ttf").path, contents: Data("x".utf8))
    let lines = LineBox()
    let installed = ModEngine.run(executable: engine, args: ["install", src.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().path], environment: e) { lines.add($0) }
    check(installed.ok, "engine: install a folder: \(installed.error)")
    check(lines.all.contains { $0.hasPrefix("installed to") }, "engine: output arrives line by line")
    check(fm.fileExists(atPath: store.appendingPathComponent("merged/data/ui/fonts/a.ttf").path), "engine: merged tree built")
    let mods = state()?.mods ?? []
    check(mods.count == 1 && mods[0].enabled && mods[0].files == 1, "engine: mod listed")
    let again = run("install", src.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().path)
    check(!again.ok && again.error.contains("already installed"), "engine: a duplicate fails with status and message: \(again.status) \(again.error)")
    if let slug = mods.first?.slug {
        check(run("disable", slug).ok && state()?.mods.first?.enabled == false, "engine: disable")
        check(!fm.fileExists(atPath: store.appendingPathComponent("merged/data/ui/fonts/a.ttf").path), "engine: a disabled mod leaves the merged tree")
        check(run("enable", slug).ok, "engine: enable")
        let d = try? JSONDecoder.engine.decode(ModDetails.self, from: Data(run("details", slug).output.utf8))
        check(d?.slug == slug && d?.parts.isEmpty == true, "engine: details decode; a one-folder mod has no parts to switch")
        check(run("scoreboard", "53", slug).ok && state()?.scoreboards.first?.comp == 53, "engine: scoreboard")
        check(run("scoreboard", "53", "--clear").ok && state()?.scoreboards.isEmpty == true, "engine: scoreboard cleared")
        check(run("remove", slug, "--yes").ok && state()?.mods.isEmpty == true, "engine: remove")
    }
    // Multi-part archives: any part chosen, extracted from the first one, named without the part suffix.
    let volSrc = scratch.appendingPathComponent("vol/data/ui/fonts")
    try? fm.createDirectory(at: volSrc, withIntermediateDirectories: true)
    fm.createFile(atPath: volSrc.appendingPathComponent("big.ttf").path, contents: Data((0..<3000).map { _ in UInt8.random(in: 0...255) }))  // incompressible: several volumes
    let sevenZip = Process(); sevenZip.executableURL = URL(fileURLWithPath: root + "/7zz")
    fm.createFile(atPath: scratch.appendingPathComponent("vol/readme.txt").path, contents: Data("hi".utf8))  // two top entries: the name comes from the archive
    sevenZip.currentDirectoryURL = scratch.appendingPathComponent("vol")
    sevenZip.arguments = ["a", "-v1k", "-bso0", scratch.appendingPathComponent("Multi Part.7z").path, "data", "readme.txt"]
    try? sevenZip.run(); sevenZip.waitUntilExit()
    check(fm.fileExists(atPath: scratch.appendingPathComponent("Multi Part.7z.002").path), "engine test: a multi-volume archive was made")
    let fromPart3 = run("install", scratch.appendingPathComponent("Multi Part.7z.003").path)
    check(fromPart3.ok && fromPart3.output.contains("extracting from Multi Part.7z.001"), "engine: a later part installs from the first: \(fromPart3.error)")
    check(state()?.mods.first?.name == "Multi Part" && state()?.mods.first?.files == 1, "engine: multi-part mod named without the part suffix: \(state()?.mods.first?.name ?? "-")")
    if let slug = state()?.mods.first?.slug { _ = run("remove", slug, "--yes") }
    let orphan = scratch.appendingPathComponent("Alone.part2.rar"); fm.createFile(atPath: orphan.path, contents: Data())
    let r2 = run("install", orphan.path)
    check(!r2.ok && r2.error.contains("first part"), "engine: a later part without its first part is refused with a reason")
    for refused in ["/Applications", "/Applications/Safari.app", NSHomeDirectory(), NSHomeDirectory() + "/Downloads", "/"] {
        let r = run("install", refused)
        check(!r.ok && !fm.fileExists(atPath: store.appendingPathComponent(".tmp").path + "/x"), "engine: \(refused) refused: \(r.message)")
    }
    // Cancel during an install: stops at once, nothing left behind.
    let big = scratch.appendingPathComponent("big/data/ui")
    try? fm.createDirectory(at: big, withIntermediateDirectories: true)
    for i in 0..<40 { fm.createFile(atPath: big.appendingPathComponent("f\(i).bin").path, contents: Data(count: 32 << 20)) }
    let handle = ModEngine.Handle()
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) { handle.cancel() }
    let cancelled = ModEngine.run(executable: engine, args: ["install", scratch.appendingPathComponent("big").path], environment: e, handle: handle)
    let left = ((try? fm.contentsOfDirectory(atPath: store.appendingPathComponent(".tmp").path)) ?? []).filter { $0.hasPrefix("fifamod-") }
    check(!cancelled.ok && handle.wasCancelled && left.isEmpty, "engine: cancel stops the install and cleans up: \(cancelled.status) \(cancelled.error) \(left)")
    check(state()?.mods.isEmpty == true, "engine: a cancelled install adds nothing")
    let bad = run("configure", "--base", engine.deletingLastPathComponent().path)
    check(!bad.ok && bad.message.contains("no data/ folder"), "engine: a wrong base patch folder is refused")
}

// MARK: Launch through the stub run.sh, then Stop
do {
    var s = LauncherSettings()
    let patchDir = scratch.appendingPathComponent("patch")
    try? fm.createDirectory(at: patchDir.appendingPathComponent("data"), withIntermediateDirectories: true)
    s.gameDir = gameDir.path
    s.modsDir = patchDir.path
    s.frameStats = true
    let env = s.launchEnvironment(base: ["PATH": "/usr/bin:/bin", "HOME": scratch.path], paths: paths)
    try? fm.createDirectory(at: dataDir, withIntermediateDirectories: true)
    let r = GameControl.launch(script: paths.runScript, mode: .play, environment: env, directory: dataDir)
    check(r.status == 0, "stub run.sh ran: \(r.output)")
    check(r.runDir?.path.hasPrefix(paths.runs.path) == true, "run folder under the data folder")
    check(r.pid.map(Processes.isAlive) == true, "pid file read and alive")
    if let dir = r.runDir {
        let args = (try? String(contentsOf: dir.appendingPathComponent("args"), encoding: .utf8)) ?? ""
        check(args == "play\n", "mode passed as the argument")
        let cwd = ((try? String(contentsOf: dir.appendingPathComponent("cwd"), encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        check(URL(fileURLWithPath: cwd).standardizedFileURL.path == dataDir.standardizedFileURL.path
              || URL(fileURLWithPath: cwd).resolvingSymlinksInPath().path == dataDir.resolvingSymlinksInPath().path, "run.sh runs in the data folder: \(cwd)")
        let recorded = (try? String(contentsOf: dir.appendingPathComponent("env"), encoding: .utf8)) ?? ""
        var got: [String: String] = [:]
        for line in recorded.split(separator: "\n") {
            if let eq = line.firstIndex(of: "=") { got[String(line[..<eq])] = String(line[line.index(after: eq)...]) }
        }
        for (k, v) in env where !["_", "PWD", "OLDPWD", "SHLVL"].contains(k) {
            check(got[k] == v, "run.sh received \(k)=\(v) (got \(got[k] ?? "nil"))")
        }
        check(got["BB_FULLSCREEN"] == nil && got["BB_PRESENT_MODE"] == nil && got["MTL_HUD_ENABLED"] == nil, "defaults add no option variables")
        check(got["FIFA_UPDATE_DIR"] == "" && got["FIFA_MODS_DIR"] == patchDir.path, "empty update, chosen patch folder")
    }
    if let pid = r.pid {
        // The stub's "emulator" is a sleep, not shadps4: Stop must refuse it (wrong name) ...
        check(GameControl.stop(pid: pid, grace: 1) == .notOurs("sleep"), "Stop leaves a process with another name alone")
        // ... and stop it when told the name, children included.
        check(GameControl.stop(pid: pid, expectedName: "sleep", grace: 2) == .stopped(forced: false), "Stop ends the recorded pid")
        check(!Processes.isAlive(pid), "pid gone after Stop")
        check(GameControl.stop(pid: pid, expectedName: "sleep") == .notRunning, "Stop on a dead pid")
    }
    check(GameControl.stop(pid: 0) == .notRunning, "pid 0 is never stopped")
}

// MARK: Processes and the log tail
do {
    let ps = Processes.parse(" 10 1 /usr/bin/x\n 42 10 /path/shadps4\n 43 42 /app/bbgpu-host-macos27\nbad line\n")
    check(ps.count == 3 && ps[1].isEmulator && ps[2].isEmulator && !ps[0].isEmulator, "ps parsing and emulator names")
    check(ps[2].ppid == 42, "ppid parsed")
    let log = scratch.appendingPathComponent("log.txt")
    write((1...700).map { "\u{1b}[31mline \($0)\u{1b}[0m" }.joined(separator: "\n") + "\n", log)
    let tail = LogTail.read(log, maxLines: 5)
    check(tail == "line 696\nline 697\nline 698\nline 699\nline 700\n", "last lines without colour codes: \(tail.debugDescription)")
    check(LogTail.read(scratch.appendingPathComponent("absent.log")) == "", "missing log reads empty")
    let state = LaunchState(pid: 1, runDir: "/r", mode: .start, started: Date(timeIntervalSince1970: 1_000))
    let stateFile = dataDir.appendingPathComponent("state.json")
    try? state.save(stateFile)
    check(LaunchState.load(stateFile) == state, "state round trip")
}

if failures == 0 {
    print("PASS: \(checks) checks")
    exit(0)
} else {
    print("\(failures) of \(checks) checks failed")
    exit(1)
}
