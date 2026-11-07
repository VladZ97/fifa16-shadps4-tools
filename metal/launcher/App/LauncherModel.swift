// SPDX-License-Identifier: GPL-2.0-or-later
// FIFA 16 launcher: the window's state. Play runs the bundled run.sh (GameControl.launch) with
// the four folders the user chose; Stop stops only the emulator this launcher started
// (state.json); everything else is read-only.
import AppKit
import Foundation

@MainActor
final class LauncherModel: ObservableObject {
    enum Phase: Equatable { case idle, starting, running, stopping }

    let paths: Paths
    @Published var settings: LauncherSettings {
        didSet {
            guard settings != oldValue else { return }
            try? settings.save(to: paths.settingsFile)
            refreshStatus()
            if settings.modsDir != oldValue.modsDir { mods.reload() }
        }
    }
    @Published private(set) var status: [StatusItem] = []
    @Published private(set) var phase = Phase.idle
    @Published private(set) var game: LaunchState?
    @Published private(set) var others: [EmulatorProcess] = []
    @Published private(set) var logText = ""
    @Published private(set) var logURL: URL?
    @Published private(set) var scriptOutput = ""
    @Published var message: String?
    @Published var page = Page.game
    /// The Advanced Settings section of the Game page is open.
    @Published var advancedOpen = false

    enum Page: Hashable { case game, mods, log }
    /// The Mods page's state.
    let mods = ModsModel()

    var onStateChange: (() -> Void)?
    private var timer: Timer?
    private var refreshing = false
    private var tick = 0

    init(paths: Paths = .live()) {
        self.paths = paths
        settings = LauncherSettings.load(from: paths.settingsFile)
        if let state = LaunchState.load(paths.stateFile), Processes.isAlive(state.pid), Processes.name(of: state.pid) == "shadps4" {
            game = state
            phase = .running
        } else {
            try? FileManager.default.removeItem(at: paths.stateFile)
        }
        mods.attach(self)
        refreshStatus()
        refresh()
        mods.reload()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    var folders: GameFolders { GameFolders(settings: settings, paths: paths) }
    var running: Bool { phase != .idle }
    var problems: [StatusItem] { InstallStatus.problems(status) }
    var canPlay: Bool { phase == .idle && problems.isEmpty }
    var firstLaunch: Bool { settings.gameDir.trimmingCharacters(in: .whitespaces).isEmpty }
    var playHelp: String {
        if let p = problems.first { return "\(p.title): \(p.detail)" }
        return "Runs the bundled run.sh \(settings.mode.rawValue) with the folders above"
    }
    /// The run folder shown (this launcher's game, else the newest run).
    var runFolder: URL? { game.map { URL(fileURLWithPath: $0.runDir) } ?? paths.latestRun() }
    var commandLine: String {
        let env = settings.overrides.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value) " }.joined()
        return env + "bash \"F16.app/Contents/Resources/run.sh\" " + settings.mode.rawValue
    }

    func refreshStatus() {
        status = InstallStatus.check(paths, settings: settings)
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
            alert.informativeText = "It is not part of this app and will be left running (pid \(foreign.map { String($0.pid) }.joined(separator: ", "))). Two emulators at once share the GPU and the keyboard, so the game may run poorly until it is closed."
            alert.addButton(withTitle: "Play Anyway")
            alert.addButton(withTitle: "Cancel")
            alert.alertStyle = .warning
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        phase = .starting
        message = nil
        scriptOutput = "$ \(commandLine)\n"
        onStateChange?()
        let settings = self.settings, paths = self.paths
        Task.detached(priority: .userInitiated) {
            let base = LaunchEnvironment.base(inherited: ProcessInfo.processInfo.environment,
                                              loginPath: LaunchEnvironment.loginPath(), home: NSHomeDirectory())
            let env = settings.launchEnvironment(base: base, paths: paths)
            let result = GameControl.launch(script: paths.runScript, mode: settings.mode, environment: env, directory: paths.dataDir)
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
        refreshStatus()
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

    // MARK: Folders

    enum Folder: String, CaseIterable, Identifiable {
        case game, update, mods, saves
        var id: String { rawValue }
        var title: String {
            switch self {
            case .game: return "Game folder"
            case .update: return "Update folder"
            case .mods: return "Mods folder"
            case .saves: return "Savegame folder"
            }
        }
        var hint: String {
            switch self {
            case .game: return "The dumped CUSA02138 folder: eboot.bin and sce_sys/ inside. Required."
            case .update: return "The dumped update 1.07 (CUSA02138-UPDATE). Optional: without it the 1.00 game runs."
            case .mods: return "Where your mods are kept: any folder, an external drive too. Optional: by default they stay in the app's data folder."
            case .saves: return "Where savegames are kept. Default: the app's data folder."
            }
        }
        var clearable: Bool { self == .update || self == .mods }
    }

    func folderPath(_ folder: Folder) -> String {
        switch folder {
        case .game: return settings.gameDir
        case .update: return settings.updateDir
        case .mods: return settings.modsDir
        case .saves: return settings.savesDir.isEmpty ? paths.defaultSaves.path : settings.savesDir
        }
    }

    func folderIsSet(_ folder: Folder) -> Bool {
        folder == .saves || !folderPath(folder).trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The bundled items and the data the app looks after itself (Advanced Settings).
    var bundledStatus: [StatusItem] { status.filter(\.bundled) }
    /// What the user chose.
    var chosenStatus: [StatusItem] { status.filter { !$0.bundled } }
    /// Advanced Settings opens by itself when something in it stops Play.
    var bundledProblem: Bool { problems.contains(where: \.bundled) }

    func setFolder(_ folder: Folder, _ path: String) {
        switch folder {
        case .game: settings.gameDir = path
        case .update: settings.updateDir = path
        case .mods: settings.modsDir = path
        case .saves: settings.savesDir = path == paths.defaultSaves.path ? "" : path
        }
    }

    func chooseFolder(_ folder: Folder) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = folder == .saves
        panel.prompt = "Choose"
        panel.message = folder.hint
        let current = folderPath(folder)
        if !current.isEmpty { panel.directoryURL = URL(fileURLWithPath: (current as NSString).expandingTildeInPath) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setFolder(folder, url.path)
        message = "\(folder.title): \(url.lastPathComponent)"
    }

    func clearFolder(_ folder: Folder) {
        guard folder.clearable else { return }
        setFolder(folder, "")
    }

    func openRunFolder() { if let dir = runFolder { NSWorkspace.shared.open(dir) } }
    func openRuns() {
        try? FileManager.default.createDirectory(at: paths.runs, withIntermediateDirectories: true)
        NSWorkspace.shared.open(paths.runs)
    }
    func openSaves() {
        try? FileManager.default.createDirectory(at: folders.saves, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folders.saves)
    }
    func openMods() { if let dir = mods.folderToOpen { NSWorkspace.shared.open(dir) } }
    func openShaderCache() {
        try? FileManager.default.createDirectory(at: paths.shaderCache, withIntermediateDirectories: true)
        NSWorkspace.shared.open(paths.shaderCache)
    }
    func revealLog() { if let logURL { NSWorkspace.shared.activateFileViewerSelecting([logURL]) } }
    func openSettingsFile() {
        if !FileManager.default.fileExists(atPath: paths.settingsFile.path) { try? settings.save(to: paths.settingsFile) }
        NSWorkspace.shared.activateFileViewerSelecting([paths.settingsFile])
    }
    /// Options back to run.sh's defaults; the folders stay.
    func resetOptions() {
        var s = settings
        s.fullscreen = true; s.lowLatency = false; s.frameStats = false; s.metalHUD = false; s.mode = .play
        settings = s
    }
    var optionsAreDefault: Bool {
        settings.fullscreen && !settings.lowLatency && !settings.frameStats && !settings.metalHUD && settings.mode == .play
    }
}
