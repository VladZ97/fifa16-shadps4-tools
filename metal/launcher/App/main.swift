// FIFA 16.app's main executable: the launcher window, or with --cli a command line over the
// same model code (status | env | play | stop), for scripts and the smoke test.
import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: LauncherModel!
    private var window: NSWindow?
    private var quitting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = LauncherModel()
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: LauncherView.size),
                              styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "FIFA 16"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.contentView = NSHostingView(rootView: LauncherView(model: model))
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("FIFA16Launcher")
        self.window = window
        showWindow()
    }

    func showWindow() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return false
    }

    /// Closing the window quits only when no game is running (the Stop button stays reachable).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !model.running }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.phase == .running, !quitting else { return .terminateNow }
        // As with run.sh, the game outlives the launcher unless asked; the next launch reattaches.
        let alert = NSAlert()
        alert.messageText = "FIFA 16 is running"
        alert.informativeText = "Stop the game, or keep it running? Reopening the launcher shows its Stop button again."
        alert.addButton(withTitle: "Stop Game and Quit")
        alert.addButton(withTitle: "Keep Playing and Quit")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            quitting = true
            model.stop { NSApp.reply(toApplicationShouldTerminate: true) }
            return .terminateLater
        case .alertSecondButtonReturn: return .terminateNow
        default: return .terminateCancel
        }
    }
}

// MARK: --cli

func cli(_ args: [String]) -> Int32 {
    let home = URL(fileURLWithPath: NSHomeDirectory())
    let probe = Paths(home: home)
    let settings = LauncherSettings.load(from: probe.settingsFile)
    let paths = Paths(home: home, runScript: settings.runScript.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) })
    let base = LaunchEnvironment.base(inherited: ProcessInfo.processInfo.environment,
                                      loginPath: LaunchEnvironment.loginPath(), home: home.path)
    let launch = settings.launchEnvironment(base: base)
    switch args.first ?? "status" {
    case "status":
        for item in InstallStatus.check(paths) {
            print("\(item.ok ? "ok  " : (item.optional ? "warn" : "MISS")) \(item.title): \(item.detail)")
        }
        let state = LaunchState.load(paths.stateFile)
        if let state, Processes.isAlive(state.pid) { print("game: running, pid \(state.pid), \(state.runDir)") } else { print("game: not started by the launcher") }
        for p in Processes.emulators() where p.pid != state?.pid { print("other emulator: \(p.pid) \(p.command)") }
        return 0
    case "env":
        // The variables Play adds to run.sh's environment, then what the game process gets.
        print("# command: \(GameControl.command(script: paths.runScript, mode: settings.mode).joined(separator: " "))")
        print("# overrides: \(settings.overrides.isEmpty ? "none (run.sh defaults)" : settings.overrides.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")
        let game = RunScript.gameEnvironment(launch: launch, home: home.path)
        for key in game.keys.sorted() where launch[key] != game[key] || RunScript.exportedNames.contains(key) || LauncherSettings.ownedKeys.contains(key) {
            print("\(key)=\(game[key]!)")
        }
        return 0
    case "play":
        if let state = LaunchState.load(paths.stateFile), Processes.isAlive(state.pid) {
            print("already running: pid \(state.pid)"); return 1
        }
        let problems = InstallStatus.problems(InstallStatus.check(paths))
        guard problems.isEmpty else { print("not ready: \(problems.map(\.title).joined(separator: ", "))"); return 1 }
        let others = Processes.emulators().filter { $0.name == "shadps4" }
        if !others.isEmpty && !args.contains("--force") {
            print("another shadps4 is running (pid \(others.map { String($0.pid) }.joined(separator: ", "))); run.sh would stop it. Add --force to go ahead.")
            return 1
        }
        let r = GameControl.launch(script: paths.runScript, mode: settings.mode, environment: launch, home: home)
        print(r.output, terminator: "")
        guard let pid = r.pid, let dir = r.runDir, Processes.isAlive(pid) else { print("game did not stay up"); return 1 }
        try? LaunchState(pid: pid, runDir: dir.path, mode: settings.mode, started: Date()).save(paths.stateFile)
        print("launcher: game pid \(pid), run \(dir.path)")
        return 0
    case "stop":
        guard let state = LaunchState.load(paths.stateFile) else { print("no game started by the launcher"); return 1 }
        let monitor = (try? String(contentsOf: URL(fileURLWithPath: state.runDir).appendingPathComponent("monitor_pid"), encoding: .utf8))
            .flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let r = GameControl.stop(pid: state.pid, monitorPid: monitor)
        try? FileManager.default.removeItem(at: paths.stateFile)
        print("stop pid \(state.pid): \(r)")
        return 0
    default:
        print("usage: FIFA\\ 16 --cli [status|env|play [--force]|stop]")
        return 2
    }
}

if let i = CommandLine.arguments.firstIndex(of: "--cli") {
    exit(cli(Array(CommandLine.arguments[(i + 1)...])))
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    let menu = NSMenu()
    let appItem = NSMenuItem()
    menu.addItem(appItem)
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "About FIFA 16 Launcher", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "Hide", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "Quit FIFA 16 Launcher", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appItem.submenu = appMenu
    let editItem = NSMenuItem()
    menu.addItem(editItem)
    let editMenu = NSMenu(title: "Edit")
    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editItem.submenu = editMenu
    app.mainMenu = menu
    app.setActivationPolicy(.regular)
    app.run()
}
