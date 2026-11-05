// FIFA 16 launcher: the window's state. Play runs ~/fifa_metal/run.sh (GameControl.launch); Stop
// stops only the emulator this launcher started (state.json); everything else is read-only.
import AppKit
import Foundation

@MainActor
final class LauncherModel: ObservableObject {
    enum Phase: Equatable { case idle, starting, running, stopping }

    let home = URL(fileURLWithPath: NSHomeDirectory())
    private(set) var paths: Paths
    @Published var settings: LauncherSettings {
        didSet {
            guard settings != oldValue else { return }
            try? settings.save(to: paths.settingsFile)
            if settings.runScript != oldValue.runScript { reloadPaths() }
        }
    }
    @Published private(set) var status: [StatusItem] = []
    @Published private(set) var overlays: [String] = []
    @Published private(set) var currentOverlay: String?
    @Published private(set) var phase = Phase.idle
    @Published private(set) var game: LaunchState?
    @Published private(set) var others: [EmulatorProcess] = []
    @Published private(set) var logText = ""
    @Published private(set) var logURL: URL?
    @Published private(set) var scriptOutput = ""
    @Published var message: String?
    @Published var page = Page.game

    enum Page: Hashable { case game, log }

    var onStateChange: (() -> Void)?
    private var timer: Timer?
    private var refreshing = false
    private var tick = 0

    init() {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let probe = Paths(home: home)
        let settings = LauncherSettings.load(from: probe.settingsFile)
        self.settings = settings
        paths = Paths(home: home, runScript: settings.runScript.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) })
        if let state = LaunchState.load(paths.stateFile), Processes.isAlive(state.pid), Processes.name(of: state.pid) == "shadps4" {
            game = state
            phase = .running
        } else {
            try? FileManager.default.removeItem(at: paths.stateFile)
        }
        refreshStatus()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func reloadPaths() {
        paths = Paths(home: home, runScript: settings.runScript.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) })
        refreshStatus()
    }

    var running: Bool { phase != .idle }
    var problems: [StatusItem] { InstallStatus.problems(status) }
    var canPlay: Bool { phase == .idle && problems.isEmpty }
    var playHelp: String {
        if let p = problems.first { return "\(p.title) not found: \(p.detail)" }
        return "Runs bash \(paths.runScript.path.replacingOccurrences(of: home.path, with: "~")) \(settings.mode.rawValue)"
    }
    /// The run folder shown (this launcher's game, else the newest run).
    var runFolder: URL? { game.map { URL(fileURLWithPath: $0.runDir) } ?? paths.latestRun() }
    var commandLine: String {
        let env = settings.overrides.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value) " }.joined()
        return env + "bash " + paths.runScript.path.replacingOccurrences(of: home.path, with: "~") + " " + settings.mode.rawValue
    }

    func refreshStatus() {
        status = InstallStatus.check(paths)
        overlays = Overlay.choices(paths)
        currentOverlay = Overlay.current(paths)
    }

    /// Process list and log tail, off the main thread.
    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        tick += 1
        if tick % 10 == 0 { refreshStatus() }
        let paths = self.paths
        let game = self.game
        Task.detached(priority: .utility) {
            let emulators = Processes.emulators()
            let alive = game.map { Processes.isAlive($0.pid) } ?? false
            let dir = game.map { URL(fileURLWithPath: $0.runDir) } ?? paths.latestRun()
            let log = dir?.appendingPathComponent("emulator.log")
            let text = log.map { LogTail.read($0) } ?? ""
            await MainActor.run {
                self.refreshing = false
                self.apply(emulators: emulators, gameAlive: alive, log: log, text: text)
            }
        }
    }

    private func apply(emulators: [EmulatorProcess], gameAlive: Bool, log: URL?, text: String) {
        if let game, phase == .running, !gameAlive, self.game == game {
            self.game = nil
            phase = .idle
            message = "The game exited."
            try? FileManager.default.removeItem(at: paths.stateFile)
            onStateChange?()
        }
        let ours = game?.pid
        others = emulators.filter { $0.pid != ours && $0.ppid != ours }
        logURL = log
        if text != logText { logText = text }
    }

    // MARK: Play and Stop

    func play() {
        guard canPlay else { return }
        let foreign = Processes.emulators().filter { $0.name == "shadps4" }
        if !foreign.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Another shadPS4 is running"
            alert.informativeText = "run.sh stops every running shadps4 (pkill -x shadps4) before it starts the game, as it does in Terminal. Running now: pid \(foreign.map { String($0.pid) }.joined(separator: ", "))."
            alert.addButton(withTitle: "Stop It and Play")
            alert.addButton(withTitle: "Cancel")
            alert.alertStyle = .warning
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        phase = .starting
        message = nil
        scriptOutput = "$ \(commandLine)\n"
        onStateChange?()
        let settings = self.settings, paths = self.paths, home = self.home
        Task.detached(priority: .userInitiated) {
            let base = LaunchEnvironment.base(inherited: ProcessInfo.processInfo.environment,
                                              loginPath: LaunchEnvironment.loginPath(), home: home.path)
            let env = settings.launchEnvironment(base: base)
            let result = GameControl.launch(script: paths.runScript, mode: settings.mode, environment: env, home: home)
            await MainActor.run { self.launched(result, mode: settings.mode) }
        }
    }

    private func launched(_ result: GameControl.LaunchResult, mode: RunMode) {
        scriptOutput += result.output
        if let pid = result.pid, let dir = result.runDir, Processes.isAlive(pid) {
            let state = LaunchState(pid: pid, runDir: dir.path, mode: mode, started: Date())
            try? state.save(paths.stateFile)
            game = state
            phase = .running
            message = nil
        } else {
            phase = .idle
            message = result.runDir == nil ? "run.sh did not start the game (status \(result.status))." : "The game exited early."
            page = .log
        }
        refresh()
        onStateChange?()
    }

    /// Stops the game this launcher started; false when there is none.
    @discardableResult
    func stop(then done: (() -> Void)? = nil) -> Bool {
        guard let game, phase == .running else { return false }
        phase = .stopping
        onStateChange?()
        let monitor = (try? String(contentsOf: URL(fileURLWithPath: game.runDir).appendingPathComponent("monitor_pid"), encoding: .utf8))
            .flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let stateFile = paths.stateFile
        Task.detached(priority: .userInitiated) {
            let result = GameControl.stop(pid: game.pid, monitorPid: monitor)
            await MainActor.run {
                switch result {
                case .stopped(let forced): self.message = forced ? "Stopped (forced after 10 s)." : "Stopped."
                case .notRunning: self.message = "The game had already exited."
                case .notOurs(let name): self.message = "pid \(game.pid) is now \(name); left alone."
                }
                try? FileManager.default.removeItem(at: stateFile)
                self.game = nil
                self.phase = .idle
                self.refresh()
                self.onStateChange?()
                done?()
            }
        }
        return true
    }

    // MARK: GPU host bundle

    /// No game may be using the host while its binaries are overwritten (ours or another run's).
    var canRefreshHost: Bool { !running && others.isEmpty }

    /// Runs `bash ~/fifa_metal/host_app/refresh.sh` (copies the built host into FIFA 16 GPU.app).
    func refreshHost() {
        guard canRefreshHost else { return }
        let script = paths.hostRefreshScript
        message = "Refreshing the GPU host…"
        Task.detached(priority: .userInitiated) {
            // Checked again right before copying: a run may have started meanwhile.
            let busy = Processes.emulators()
            let result = busy.isEmpty ? Shell.run(["/bin/bash", script.path]) : (status: Int32(-1), output: "an emulator is running")
            await MainActor.run {
                let text = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                self.message = result.status == 0 ? (text.isEmpty ? "GPU host refreshed." : text) : "Refresh failed: \(text)"
                self.refreshStatus()
            }
        }
    }

    // MARK: Overlay and folders

    func selectOverlay(_ name: String) {
        guard !running, name != currentOverlay else { return }
        let alert = NSAlert()
        alert.messageText = "Use the \(Overlay.label(name)) overlay?"
        alert.informativeText = "Points \(paths.overlayLink.path.replacingOccurrences(of: home.path, with: "~")) at \(paths.overlayStore.appendingPathComponent(name).path.replacingOccurrences(of: home.path, with: "~")) (now: \(currentOverlay ?? "none")). This is the Metal build's patch overlay: it applies to every launch of that build, including run.sh in Terminal."
        alert.addButton(withTitle: "Switch Overlay")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try Overlay.select(name, paths: paths)
            message = "Overlay: \(Overlay.label(name))."
        } catch {
            message = "\(error)"
        }
        refreshStatus()
    }

    func openRunFolder() { if let dir = runFolder { NSWorkspace.shared.open(dir) } }
    func openRuns() { NSWorkspace.shared.open(paths.runs) }
    func openShaderCache() { NSWorkspace.shared.open(paths.shaderCache) }
    func revealLog() { if let logURL { NSWorkspace.shared.activateFileViewerSelecting([logURL]) } }
    func openSettingsFile() {
        if !FileManager.default.fileExists(atPath: paths.settingsFile.path) { try? settings.save(to: paths.settingsFile) }
        NSWorkspace.shared.activateFileViewerSelecting([paths.settingsFile])
    }
    func resetSettings() { settings = LauncherSettings() }
}
