// FIFA 16 launcher: the Mods page's state. Every action runs the bundled engine off the main
// thread, one at a time, and reloads the library afterwards. Changes are refused while a game
// runs: the merged tree the game reads is replaced by every rebuild.
import AppKit
import Foundation

@MainActor
final class ModsModel: ObservableObject {
    @Published private(set) var state: LibraryState?
    /// What is running now (nil: idle) and its latest output line.
    @Published private(set) var busy: String?
    @Published private(set) var progress = ""
    @Published var errorText: String?
    /// Competition ids seen in the latest game log.
    @Published private(set) var seenCompetitions: [Int] = []
    /// The mod shown in the details sheet.
    @Published var details: ModDetails?
    /// Text results (conflicts, fixes) shown in a sheet.
    @Published var report: Report?
    /// Files waiting to be installed; the first one is shown in the install sheet.
    @Published var installQueue: [URL] = []
    @Published var installOutput = ""
    @Published var installFinished = false
    @Published var replacePrompt: InstallRequest?
    // View state (this toolchain's swiftc has no plugin for SwiftUI's @State macro).
    @Published var dropTargeted = false
    @Published var toolsOpen = false
    @Published var newCompetition = ""
    @Published var installName = ""
    @Published var installOptional = true

    struct Report: Identifiable { let id = UUID(); let title: String; let text: String }
    struct InstallRequest: Identifiable, Equatable {
        let id = UUID()
        let source: URL
        let name: String
        let skipOptional: Bool
    }

    private var running: ModEngine.Handle?
    private weak var launcher: LauncherModel?
    private var paths: Paths? { launcher?.paths }

    func attach(_ launcher: LauncherModel) { self.launcher = launcher }

    var library: ModLibrary? {
        guard let launcher else { return nil }
        return ModLibrary.locate(settings: launcher.settings, paths: launcher.paths)
    }
    var isPlainPatch: Bool { library?.kind == .plainPatch }
    var engineAvailable: Bool {
        guard let paths else { return false }
        return FileManager.default.isExecutableFile(atPath: paths.modEngine.path)
    }
    /// Why nothing can be changed now, if so.
    var lockReason: String? {
        guard let launcher else { return nil }
        if !engineAvailable { return "The mod manager is missing from this app." }
        if launcher.running { return "Stop the game to change mods." }
        if !launcher.others.isEmpty { return "Another emulator is running. Close it to change mods." }
        return nil
    }
    var canChange: Bool { busy == nil && lockReason == nil }
    var folderToOpen: URL? {
        if let dir = state?.modsDir, FileManager.default.fileExists(atPath: dir) { return URL(fileURLWithPath: dir) }
        return launcher?.folders.mods
    }

    // MARK: Reading

    func reload() {
        guard let library, let paths, engineAvailable else { state = nil; return }
        let log = paths.latestRun()?.appendingPathComponent("emulator.log")
        Task.detached(priority: .userInitiated) {
            let result = ModEngine.run(["state"], library: library, paths: paths)
            let decoded = try? JSONDecoder.engine.decode(LibraryState.self, from: Data(result.output.utf8))
            let seen = log.map(ModEngine.competitions(inLog:)) ?? []
            await MainActor.run {
                if let decoded { self.state = decoded } else if !result.ok { self.errorText = result.message }
                self.seenCompetitions = seen
            }
        }
    }

    func showDetails(_ mod: ModEntry) {
        guard let library, let paths, !mod.missing else { return }
        Task.detached(priority: .userInitiated) {
            let result = ModEngine.run(["details", mod.slug], library: library, paths: paths)
            let decoded = try? JSONDecoder.engine.decode(ModDetails.self, from: Data(result.output.utf8))
            await MainActor.run {
                if let decoded { self.details = decoded } else { self.errorText = result.message }
            }
        }
    }

    // MARK: Changing

    /// Runs engine commands in order, stopping at the first failure. Registry set-up comes first.
    private func perform(_ title: String, _ commands: [[String]], showOutput: Bool = false,
                         then done: (@MainActor (ModEngine.Result) -> Void)? = nil) {
        guard canChange, let library, let paths, let settings = launcher?.settings else { return }
        busy = title
        progress = ""
        errorText = nil
        let all = ModEngine.prepareCommands(library: library, settings: settings) + commands
        let handle = ModEngine.Handle()
        running = handle
        Task.detached(priority: .userInitiated) {
            var last = ModEngine.Result(status: 0, output: "", error: "")
            var text = ""
            for command in all {
                last = ModEngine.run(command, library: library, paths: paths, handle: handle) { line in
                    Task { @MainActor in self.note(line) }
                }
                text += last.output
                if !last.ok || handle.wasCancelled { break }
            }
            let finished = ModEngine.Result(status: last.status, output: text, error: last.error)
            await MainActor.run {
                self.busy = nil
                self.running = nil
                self.progress = ""
                if finished.ok, showOutput { self.report = Report(title: title, text: finished.output) }
                if let done { done(finished) } else if !finished.ok { self.errorText = finished.message }
                self.reload()
                self.launcher?.refreshStatus()
            }
        }
    }

    /// Stops what is running (an install). The engine removes what it had unpacked.
    func cancel() { running?.cancel() }

    private func note(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { progress = trimmed }
        if !installQueue.isEmpty { installOutput += line + "\n" }
    }

    func setEnabled(_ mod: ModEntry, _ on: Bool) {
        perform(on ? "Enabling \(mod.name)" : "Disabling \(mod.name)", [[on ? "enable" : "disable", mod.slug]])
    }

    func move(_ mod: ModEntry, _ place: String) { perform("Moving \(mod.name)", [["move", mod.slug, place]]) }

    func remove(_ mod: ModEntry) {
        let alert = NSAlert()
        alert.messageText = "Delete \(mod.name)?"
        alert.informativeText = "Its folder is deleted. To keep it for later, switch it off instead."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        details = nil
        perform("Removing \(mod.name)", [["remove", mod.slug, "--yes"]])
    }

    func rebuild() { perform("Rebuilding", [["build"]]) }
    func showConflicts() { perform("Conflicts", [["conflicts"]], showOutput: true) }

    func chooseBase() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Choose"
        panel.message = "The patch's Manual Install folder (the one with data/ inside). Your mods go on top of it."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setBase(url.path)
    }

    func setBase(_ path: String) { perform(path.isEmpty ? "Removing the base patch" : "Setting the base patch", [["configure", "--base", path, "--build"]]) }

    /// A ready-made patch chosen as the Mods folder becomes the library's base patch.
    func adoptPlainPatch() {
        guard let launcher, let patch = library?.patchFolder else { return }
        launcher.settings.modsDir = ""
        setBase(patch.path)
    }

    func fixBase() {
        let alert = NSAlert()
        alert.messageText = "Run the PS4 fixes on the base patch?"
        alert.informativeText = "This rewrites files inside the base patch folder and can take several minutes on a large patch. Only needed for a patch made for PC that shows exploding hair or blank crests."
        alert.addButton(withTitle: "Run Fixes")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        perform("PS4 fixes on the base patch", [["fix", "base"]], showOutput: true)
    }

    func fix(_ slug: String, name: String) { perform("PS4 fixes on \(name)", [["fix", slug]], showOutput: true) }

    func setPart(_ details: ModDetails, _ part: ModDetails.Part, included: Bool) {
        perform("Updating \(details.name)", [["exclude", details.slug, part.path] + (included ? ["--remove"] : [])]) { result in
            if !result.ok { self.errorText = result.message }
            self.refreshDetails(details.slug)
        }
    }

    func useVariant(_ details: ModDetails, _ variant: ModDetails.Variant, target: String) {
        perform("Switching variant", [["pick", details.slug, variant.file, target]]) { result in
            if !result.ok { self.errorText = result.message }
            self.refreshDetails(details.slug)
        }
    }

    private func refreshDetails(_ slug: String) {
        guard let library, let paths else { return }
        Task.detached(priority: .userInitiated) {
            let result = ModEngine.run(["details", slug], library: library, paths: paths)
            let decoded = try? JSONDecoder.engine.decode(ModDetails.self, from: Data(result.output.utf8))
            await MainActor.run { if let decoded { self.details = decoded } }
        }
    }

    func setScoreboard(comp: Int, slug: String?) {
        perform("Updating scoreboards", [["scoreboard", String(comp)] + (slug.map { [$0] } ?? ["--clear"])])
    }

    // MARK: Installing

    func chooseArchive() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Install"
        panel.message = "A mod archive (.rar, .zip, .7z) or an unpacked mod folder."
        guard panel.runModal() == .OK else { return }
        enqueue(panel.urls)
    }

    func enqueue(_ urls: [URL]) {
        guard canChange else { return }
        if installQueue.isEmpty { installOutput = ""; installFinished = false }
        // The parts of a multi-part archive are one mod: queue the set once, by its first part
        // (the engine extracts from there and follows the other volumes).
        for url in urls.map(ModEngine.firstVolume) where !installQueue.contains(where: { $0.path == url.path }) {
            installQueue.append(url)
        }
    }


    func preview(_ request: InstallRequest) {
        installOutput = ""
        installFinished = false
        perform("Checking \(request.source.lastPathComponent)", [command(request) + ["--dry-run"]]) { result in
            if !result.ok { self.installOutput += "\n" + result.message + "\n" }
        }
    }

    func install(_ request: InstallRequest, replace: Bool = false) {
        installOutput = ""
        installFinished = false
        perform("Installing \(request.source.lastPathComponent)", [command(request) + (replace ? ["--replace"] : [])]) { result in
            if result.ok {
                self.installFinished = true
            } else if result.error.contains("already installed") {
                self.replacePrompt = request
            } else {
                self.installOutput += "\n" + result.message + "\n"
            }
        }
    }

    private func command(_ request: InstallRequest) -> [String] {
        var args = ["install", request.source.path]
        let name = request.name.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { args += ["--name", name] }
        if request.skipOptional { args.append("--skip-optional") }
        return args
    }

    /// Closes the install sheet; the next queued file, if any, opens it again.
    func finishInstallSheet() {
        if !installQueue.isEmpty { installQueue.removeFirst() }
        installName = ""
        installOptional = true
        installOutput = ""
        installFinished = false
    }
}
