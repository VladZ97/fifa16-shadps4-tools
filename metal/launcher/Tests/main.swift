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
    check(paths.hostBundle.path == bundle.path + "/Contents/Helpers/FIFA 16 GPU.app", "host bundle inside the app")
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
                                 "Update folder", "Mods folder", "Emulator config", "Shader cache"], "checklist order")
    check(item("Game folder")?.ok == false && item("Game folder")?.optional == false, "no game folder blocks Play")
    check(item("Savegame folder")?.ok == true, "default saves folder can be created")
    check(item("Savegame folder")?.detail.contains("created on first Play") == true, "default saves folder reported as to be created")
    check(item("Emulator (bundled)")?.ok == true && item("GPU host (bundled)")?.ok == true && item("Launch script (bundled)")?.ok == true, "bundled payload found")
    check(item("Update folder")?.ok == false && item("Update folder")?.optional == true && item("Update folder")?.detail == "none, base game 1.00 runs", "no update is optional")
    check(item("Mods folder")?.optional == true && item("Mods folder")?.detail == "none", "no mods is optional")
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
    golden2["FIFA_MODS_DIR"] = ("~/mods" as NSString).expandingTildeInPath
    golden2["FIFA_SAVES_DIR"] = "/saves"
    golden2["BB_FULLSCREEN"] = "0"; golden2["BB_PRESENT_MODE"] = "Immediate"; golden2["BB_FRAME_STATS"] = "1"; golden2["MTL_HUD_ENABLED"] = "1"
    check(env == golden2, "every option and folder: \(env)")
    check(s.overrides == ["BB_FULLSCREEN": "0", "BB_PRESENT_MODE": "Immediate", "BB_FRAME_STATS": "1", "MTL_HUD_ENABLED": "1"], "overrides")
    check(GameControl.command(script: paths.runScript, mode: .start) == ["/bin/bash", paths.runScript.path, "start"], "command line")
    check(GameControl.runDirectory(inOutput: "x\nrun dir : /tmp/r1 \nmore") == URL(fileURLWithPath: "/tmp/r1"), "run dir parsed")
    check(GameControl.runDirectory(inOutput: "nothing") == nil, "no run dir")
}

// MARK: Launch through the stub run.sh, then Stop
do {
    var s = LauncherSettings()
    s.gameDir = gameDir.path
    s.modsDir = modsDir.path
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
        check(got["FIFA_UPDATE_DIR"] == "" && got["FIFA_MODS_DIR"] == modsDir.path, "empty update, chosen mods")
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
