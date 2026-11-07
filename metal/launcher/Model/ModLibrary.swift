// SPDX-License-Identifier: GPL-2.0-or-later
// FIFA 16 launcher: the mod library. The bundled engine (compiled fifamod) does the work; this
// file says where the library is, reads what the engine reports and runs it. No UI here, so the
// model tests cover it.
//
// A library is a store (registry mods.json + the merged tree of links handed to the game) and a
// folder of mods. The store must be on APFS (exFAT cannot hold links), so it stays in the app's
// data folder; the mods themselves can be anywhere, an exFAT drive included. What the launcher's
// Mods folder setting means depends on what is in it:
//   a merged tree or a folder with mods.json   an existing library (made by fifamod): used in place
//   a folder with data/ inside                 a ready-made patch: handed to the game as it is
//   anything else, or not set                  where this app keeps mods (not set: its data folder)
import Foundation

struct ModLibrary: Equatable {
    enum Kind: Equatable { case managed, plainPatch }
    let kind: Kind
    /// Registry and merged tree.
    let store: URL
    /// The chosen folder, when mods should be kept there (nil: the engine's default, <store>/mods).
    let modsFolder: URL?
    /// The ready-made patch folder (kind == .plainPatch).
    let patchFolder: URL?

    static let marker = ".fifamod-merged"
    var registry: URL { store.appendingPathComponent("mods.json") }
    var merged: URL { store.appendingPathComponent("merged") }

    static func locate(settings: LauncherSettings, paths: Paths, fm: FileManager = .default) -> ModLibrary {
        let managedDefault = ModLibrary(kind: .managed, store: paths.modStore, modsFolder: nil, patchFolder: nil)
        guard let chosen = GameFolders(settings: settings, paths: paths).mods else { return managedDefault }
        func exists(_ url: URL) -> Bool { fm.fileExists(atPath: url.path) }
        if exists(chosen.appendingPathComponent(marker)) {
            return ModLibrary(kind: .managed, store: chosen.deletingLastPathComponent(), modsFolder: nil, patchFolder: nil)
        }
        if exists(chosen.appendingPathComponent("mods.json")) {
            return ModLibrary(kind: .managed, store: chosen, modsFolder: nil, patchFolder: nil)
        }
        var dir: ObjCBool = false
        if fm.fileExists(atPath: chosen.appendingPathComponent("data").path, isDirectory: &dir), dir.boolValue {
            return ModLibrary(kind: .plainPatch, store: paths.modStore, modsFolder: nil, patchFolder: chosen)
        }
        return ModLibrary(kind: .managed, store: paths.modStore, modsFolder: chosen, patchFolder: nil)
    }

    /// The folder the game gets as its overlay; nil: none (the game runs unmodified).
    func overlay(fm: FileManager = .default) -> URL? {
        if kind == .plainPatch { return patchFolder }
        return fm.fileExists(atPath: merged.appendingPathComponent(Self.marker).path) ? merged : nil
    }

    /// What mods.json says, read directly (the status list runs without the engine).
    func registrySummary() -> RegistrySummary? {
        guard let data = try? Data(contentsOf: registry) else { return nil }
        return try? JSONDecoder.engine.decode(RegistrySummary.self, from: data)
    }
}

struct RegistrySummary: Decodable, Equatable {
    var base: String?
    var modsDir: String?
    var mods: [String]?
}

struct ModEntry: Decodable, Identifiable, Equatable {
    var id: String { slug }
    let slug: String
    let name: String
    var enabled: Bool
    let missing: Bool
    var files: Int?
    var overridesBase: Int?
    var clash: Int?
    var installed: String?
    var excluded: [String]?
    var hasExtras: Bool?
    var notes: [String]?
    var fixes: [String: Int]?
    var folder: String?
}

struct ScoreboardEntry: Decodable, Identifiable, Equatable {
    var id: Int { comp }
    let comp: Int
    let slug: String
    let league: Bool

    /// The competitions seen so far; the id is what the emulator logs when a match loads.
    static let knownNames = [53: "La Liga", 223: "UEFA Champions League", 39: "MLS"]
    static func title(_ comp: Int) -> String { knownNames[comp].map { "\($0) (\(comp))" } ?? "Competition \(comp)" }
}

struct LibraryState: Decodable, Equatable {
    var store: String
    var merged: String
    var initialised: Bool
    var mods: [ModEntry]
    var scoreboards: [ScoreboardEntry]
    var base: String?
    var baseOk: Bool?
    var game: String?
    var modsDir: String?
    var modsDirOk: Bool?
    var conflicts: Int?
    var mergedAt: String?

    var enabledCount: Int { mods.filter(\.enabled).count }
    var missingCount: Int { mods.filter(\.missing).count }
    var hasBase: Bool { !(base ?? "").isEmpty }
}

struct ModDetails: Decodable, Identifiable, Equatable {
    var id: String { slug }
    struct Part: Decodable, Identifiable, Equatable {
        var id: String { path }
        let path: String
        let files: Int
        let excluded: Bool
    }
    struct Variant: Decodable, Identifiable, Equatable {
        var id: String { file }
        let file: String
        let targets: [String]
        let inUse: Bool
    }
    struct Conflict: Decodable, Identifiable, Equatable {
        var id: String { slug }
        let slug: String
        let files: Int
        let wins: Int
    }
    let slug: String
    let name: String
    let source: String
    let installed: String
    let folder: String
    let notes: [String]
    let fixes: [String: Int]
    let parts: [Part]
    let extras: [String]
    let variants: [Variant]
    let picks: [String: String]
    let conflicts: [Conflict]
}

extension JSONDecoder {
    static var engine: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }
}

enum ModEngine {
    /// "Mod.part2.rar" -> "Mod.part1.rar", "Mod.r01" -> "Mod.rar", "Mod.7z.002" -> "Mod.7z.001"; others unchanged.
    static func firstVolume(_ url: URL) -> URL {
        let name = url.lastPathComponent
        let patterns: [(String, (NSTextCheckingResult, String) -> String)] = [
            ("^(.+)\\.part(\\d+)\\.rar$", { m, n in
                let base = (n as NSString).substring(with: m.range(at: 1)), digits = m.range(at: 2).length
                return base + ".part" + String(repeating: "0", count: max(0, digits - 1)) + "1.rar" }),
            ("^(.+)\\.r\\d\\d$", { m, n in (n as NSString).substring(with: m.range(at: 1)) + ".rar" }),
            ("^(.+\\.(?:7z|zip|rar))\\.\\d{3}$", { m, n in (n as NSString).substring(with: m.range(at: 1)) + ".001" }),
        ]
        for (pattern, first) in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let m = re.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) else { continue }
            return url.deletingLastPathComponent().appendingPathComponent(first(m, name))
        }
        return url
    }

    struct Result: Equatable {
        let status: Int32
        let output: String
        let error: String
        var ok: Bool { status == 0 }
        /// The engine's own message for a failure.
        var message: String {
            let e = error.trimmingCharacters(in: .whitespacesAndNewlines)
            return e.isEmpty ? "The mod manager stopped (status \(status))." : e
        }
    }

    /// Nothing inherited: the engine needs no Python, Homebrew or anything else from the shell.
    static func environment(library: ModLibrary, paths: Paths, home: String = NSHomeDirectory()) -> [String: String] {
        ["HOME": home, "LANG": "en_US.UTF-8", "PATH": "/usr/bin:/bin", "FIFAMOD_APP": "1",
         "FIFAMOD_STORE": library.store.path, "FIFAMOD_RESOURCES": paths.modResources.path,
         "FIFAMOD_7ZZ": paths.sevenZip.path, "FIFAMOD_UNRAR": paths.unrar.path]
    }

    /// The commands that create or update the registry before `library` is changed. Empty when
    /// nothing has to change. New libraries remember the game folder (for the root .ini files).
    static func prepareCommands(library: ModLibrary, settings: LauncherSettings, fm: FileManager = .default) -> [[String]] {
        let wanted = library.modsFolder?.path
        guard fm.fileExists(atPath: library.registry.path) else {
            return [["configure", "--game", settings.gameDir] + (wanted.map { ["--mods-dir", $0] } ?? [])]
        }
        if let wanted, library.registrySummary()?.modsDir != wanted { return [["configure", "--mods-dir", wanted]] }
        return []
    }

    /// Stops a running engine command (Cancel): SIGTERM, the engine then removes its temporary files.
    final class Handle: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var cancelled = false
        var wasCancelled: Bool { lock.withLock { cancelled } }
        fileprivate func set(_ p: Process?) { lock.withLock { process = p } }
        func cancel() { lock.withLock { cancelled = true; process?.terminate() } }
    }

    /// Runs the engine and waits. `onLine` gets each line of output as it comes (any thread).
    static func run(_ args: [String], library: ModLibrary, paths: Paths, handle: Handle? = nil, onLine: (@Sendable (String) -> Void)? = nil) -> Result {
        run(executable: paths.modEngine, args: args, environment: environment(library: library, paths: paths), handle: handle, onLine: onLine)
    }

    static func run(executable: URL, args: [String], environment: [String: String], handle: Handle? = nil, onLine: (@Sendable (String) -> Void)? = nil) -> Result {
        let process = Process()
        process.executableURL = executable
        process.arguments = args
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let collected = Collector(onLine: onLine)
        out.fileHandleForReading.readabilityHandler = { handle in collected.add(handle.availableData) }
        let errorData = Collector(onLine: nil)
        err.fileHandleForReading.readabilityHandler = { handle in errorData.add(handle.availableData) }
        do { try process.run() } catch {
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            return Result(status: -1, output: "", error: "The mod manager could not start: \(error.localizedDescription)")
        }
        handle?.set(process)
        process.waitUntilExit()
        handle?.set(nil)
        out.fileHandleForReading.readabilityHandler = nil
        err.fileHandleForReading.readabilityHandler = nil
        collected.add((try? out.fileHandleForReading.readToEnd()) ?? Data())
        errorData.add((try? err.fileHandleForReading.readToEnd()) ?? Data())
        return Result(status: process.terminationStatus, output: collected.text, error: errorData.text)
    }

    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        private var delivered = 0
        private let onLine: (@Sendable (String) -> Void)?
        init(onLine: (@Sendable (String) -> Void)?) { self.onLine = onLine }
        var text: String { lock.withLock { String(decoding: data, as: UTF8.self) } }
        func add(_ chunk: Data) {
            guard !chunk.isEmpty else { return }
            let lines: [String] = lock.withLock {
                data.append(chunk)
                guard onLine != nil, let end = data.lastIndex(of: 10), end >= delivered else { return [] }
                let text = String(decoding: data[delivered..<end], as: UTF8.self)
                delivered = end + 1
                return text.components(separatedBy: "\n")
            }
            lines.forEach { onLine?($0) }
        }
    }

    /// Competition ids in a game log, newest last ("Scoreboard: competition 53").
    static func competitions(inLog url: URL) -> [Int] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let text = String(decoding: data, as: UTF8.self)
        guard let regex = try? NSRegularExpression(pattern: "Scoreboard: competition (\\d+)") else { return [] }
        var seen: [Int] = []
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let r = Range(match.range(at: 1), in: text), let id = Int(text[r]), id != 0 {
                seen.removeAll { $0 == id }
                seen.append(id)
            }
        }
        return seen
    }
}
