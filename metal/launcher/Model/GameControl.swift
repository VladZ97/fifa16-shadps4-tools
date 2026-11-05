// FIFA 16 launcher: starting the bundled run.sh, finding the game's processes and stopping them.
// Process work without UI, shared by the window and the command line (`FIFA 16 --cli ...`).
import Foundation

struct EmulatorProcess: Equatable {
    let pid: Int32
    let ppid: Int32
    let command: String
    var name: String { (command as NSString).lastPathComponent }
    var isEmulator: Bool { name == "shadps4" || name.hasPrefix("bbgpu-host") }
}

enum Processes {
    /// `ps -axo pid=,ppid=,comm=` lines.
    static func parse(_ output: String) -> [EmulatorProcess] {
        output.split(separator: "\n").compactMap { raw in
            let parts = raw.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, let pid = Int32(parts[0]), let ppid = Int32(parts[1]) else { return nil }
            return EmulatorProcess(pid: pid, ppid: ppid, command: String(parts[2]))
        }
    }

    static func list() -> [EmulatorProcess] {
        parse(Shell.run(["/bin/ps", "-axo", "pid=,ppid=,comm="]).output)
    }

    static func emulators() -> [EmulatorProcess] { list().filter(\.isEmulator) }

    static func isAlive(_ pid: Int32) -> Bool {
        pid > 0 && (kill(pid, 0) == 0 || errno == EPERM)
    }

    static func name(of pid: Int32) -> String? {
        let out = Shell.run(["/bin/ps", "-o", "comm=", "-p", String(pid)])
        let s = out.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return out.status == 0 && !s.isEmpty ? (s as NSString).lastPathComponent : nil
    }
}

enum Shell {
    @discardableResult
    static func run(_ command: [String], environment: [String: String]? = nil, directory: URL? = nil) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command[0])
        process.arguments = Array(command.dropFirst())
        if let environment { process.environment = environment }
        if let directory { process.currentDirectoryURL = directory }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return (-1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}

/// The game the launcher started (state.json): Stop only ever touches this pid.
struct LaunchState: Codable, Equatable {
    var pid: Int32
    var runDir: String
    var mode: RunMode
    var started: Date

    static func load(_ url: URL) -> LaunchState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LaunchState.self, from: data)
    }

    func save(_ url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

enum GameControl {
    struct LaunchResult {
        var status: Int32
        var output: String
        var runDir: URL?
        var pid: Int32?
    }

    /// The exact command Play runs: bash "<bundle>/Contents/Resources/run.sh" <mode>.
    static func command(script: URL, mode: RunMode) -> [String] { ["/bin/bash", script.path, mode.rawValue] }

    /// Runs run.sh (a few seconds: it waits to report whether the emulator stayed up) and returns
    /// its output, the run folder and the emulator's pid (run.sh prints "run dir : <path>" and
    /// writes <run dir>/pid). Blocking: call off the main thread.
    static func launch(script: URL, mode: RunMode, environment: [String: String], directory: URL) -> LaunchResult {
        let result = Shell.run(command(script: script, mode: mode), environment: environment, directory: directory)
        let dir = runDirectory(inOutput: result.output)
        let pid = dir.flatMap { try? String(contentsOf: $0.appendingPathComponent("pid"), encoding: .utf8) }
            .flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return LaunchResult(status: result.status, output: result.output, runDir: dir, pid: pid)
    }

    /// "run dir : /path" from run.sh's output.
    static func runDirectory(inOutput output: String) -> URL? {
        for line in output.split(separator: "\n") where line.hasPrefix("run dir : ") {
            return URL(fileURLWithPath: String(line.dropFirst("run dir : ".count)).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    enum StopResult: Equatable {
        case stopped(forced: Bool)
        case notRunning
        /// The pid is alive but is not the expected program (reused pid): left alone.
        case notOurs(String)
    }

    /// Stops the emulator `pid` (SIGTERM as run.sh stop's pkill sends, SIGKILL after `grace`),
    /// then its GPU host children if they outlive it (they watch their parent and normally exit
    /// by themselves). Never touches other processes. Blocking.
    static func stop(pid: Int32, expectedName: String = "shadps4", childPrefix: String = "bbgpu-host",
                     grace: TimeInterval = 10, childGrace: TimeInterval = 5, monitorPid: Int32? = nil) -> StopResult {
        guard Processes.isAlive(pid) else { return .notRunning }
        guard let name = Processes.name(of: pid) else { return .notRunning }
        guard name == expectedName else { return .notOurs(name) }
        let children = Processes.list().filter { $0.ppid == pid && $0.name.hasPrefix(childPrefix) }
        kill(pid, SIGTERM)
        var forced = false
        if !wait(for: pid, timeout: grace) {
            forced = true
            kill(pid, SIGKILL)
            _ = wait(for: pid, timeout: 3)
        }
        for child in children where Processes.isAlive(child.pid) {
            if !wait(for: child.pid, timeout: childGrace), Processes.name(of: child.pid)?.hasPrefix(childPrefix) == true {
                kill(child.pid, SIGTERM)
                if !wait(for: child.pid, timeout: 2) { kill(child.pid, SIGKILL) }
            }
        }
        // run.sh start's screenshot monitor (a zsh loop) ends when the emulator does; stop it anyway.
        if let monitorPid, Processes.isAlive(monitorPid), Processes.name(of: monitorPid) == "zsh" {
            kill(monitorPid, SIGTERM)
        }
        return .stopped(forced: forced)
    }

    private static func wait(for pid: Int32, timeout: TimeInterval) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if !Processes.isAlive(pid) { return true }
            usleep(100_000)
        }
        return !Processes.isAlive(pid)
    }
}
