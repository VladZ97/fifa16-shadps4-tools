// FIFA 16 launcher: the installation checklist (read-only) and the log tail.
import Foundation

struct StatusItem: Identifiable, Equatable {
    var id: String { title }
    let title: String
    let detail: String
    let ok: Bool
    /// Not needed to play (shown in orange when missing, never blocks Play).
    var optional = false
}

enum InstallStatus {
    static func check(_ paths: Paths, settings: LauncherSettings, fm: FileManager = .default) -> [StatusItem] {
        func exists(_ url: URL) -> Bool { fm.fileExists(atPath: url.path) }
        func isDir(_ url: URL) -> Bool {
            var dir: ObjCBool = false
            return fm.fileExists(atPath: url.path, isDirectory: &dir) && dir.boolValue
        }
        let f = GameFolders(settings: settings, paths: paths)
        var items: [StatusItem] = []

        // Required: the game, the savegame folder and the bundled payload.
        if let game = f.game, let eboot = f.eboot, let sfo = f.paramSFO {
            let ok = exists(eboot) && exists(sfo)
            let missing = [eboot, sfo].filter { !exists($0) }.map { $0.path.replacingOccurrences(of: game.path + "/", with: "") }
            items.append(StatusItem(title: "Game folder", detail: ok ? game.path : "\(game.path): missing \(missing.joined(separator: ", "))", ok: ok))
        } else {
            items.append(StatusItem(title: "Game folder", detail: "not set: choose the dumped \(Paths.titleID) folder (eboot.bin, sce_sys/)", ok: false))
        }
        items.append(StatusItem(title: "Savegame folder", detail: savesDetail(f.saves, fm: fm), ok: savesUsable(f.saves, fm: fm)))
        items.append(StatusItem(title: "Emulator (bundled)", detail: paths.emulator.path, ok: fm.isExecutableFile(atPath: paths.emulator.path)))
        items.append(StatusItem(title: "GPU host (bundled)", detail: paths.hostBundle.path, ok: exists(paths.gpuHostMacOS27)))
        items.append(StatusItem(title: "Launch script (bundled)", detail: paths.runScript.path, ok: exists(paths.runScript)))

        // Optional: update, mods, config, shader cache.
        if let update = f.update {
            let ok = isDir(update) && (exists(update.appendingPathComponent("eboot.bin")) || isDir(update.appendingPathComponent("sce_sys")))
            items.append(StatusItem(title: "Update folder", detail: ok ? update.path : "\(update.path): no eboot.bin or sce_sys/ inside", ok: ok, optional: true))
        } else {
            items.append(StatusItem(title: "Update folder", detail: "none, base game 1.00 runs", ok: false, optional: true))
        }
        if let mods = f.mods {
            let ok = isDir(mods)
            items.append(StatusItem(title: "Mods folder", detail: ok ? mods.path : "\(mods.path): not found", ok: ok, optional: true))
        } else {
            items.append(StatusItem(title: "Mods folder", detail: "none", ok: false, optional: true))
        }
        let config = exists(paths.config)
        items.append(StatusItem(title: "Emulator config", detail: config ? paths.config.path : "created on first Play", ok: config, optional: true))
        let cacheFiles = (try? fm.contentsOfDirectory(atPath: paths.shaderCache.path))?.filter { !$0.hasPrefix(".") }.count ?? 0
        items.append(StatusItem(title: "Shader cache", detail: cacheFiles > 0 ? "\(cacheFiles) files" : "empty, first sessions compile shaders",
                                ok: cacheFiles > 0, optional: true))
        return items
    }

    /// The savegame folder exists and is writable, or can be created (its nearest existing parent is writable).
    static func savesUsable(_ url: URL, fm: FileManager = .default) -> Bool {
        var dir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &dir) { return dir.boolValue && fm.isWritableFile(atPath: url.path) }
        var parent = url.deletingLastPathComponent()
        while !fm.fileExists(atPath: parent.path) && parent.path != "/" { parent = parent.deletingLastPathComponent() }
        return fm.isWritableFile(atPath: parent.path)
    }

    static func savesDetail(_ url: URL, fm: FileManager = .default) -> String {
        if fm.fileExists(atPath: url.path) { return fm.isWritableFile(atPath: url.path) ? url.path : "\(url.path): not writable" }
        return savesUsable(url, fm: fm) ? "\(url.path) (created on first Play)" : "\(url.path): cannot be created"
    }

    /// Play needs every non-optional item.
    static func problems(_ items: [StatusItem]) -> [StatusItem] { items.filter { !$0.ok && !$0.optional } }
}

enum LogTail {
    /// The last `maxLines` lines of the file (at most `maxBytes` read), colour codes removed.
    static func read(_ url: URL, maxBytes: Int = 256 * 1024, maxLines: Int = 600) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: start)
        let data = (try? handle.readToEnd()) ?? Data()
        var text = String(decoding: data, as: UTF8.self)
        if start > 0, let newline = text.firstIndex(of: "\n") { text = String(text[text.index(after: newline)...]) }
        return lastLines(stripColour(text), maxLines)
    }

    static func stripColour(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{1b}\\[[0-9;]*m", with: "", options: .regularExpression)
    }

    static func lastLines(_ s: String, _ n: Int) -> String {
        let lines = s.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.suffix(n + (s.hasSuffix("\n") ? 1 : 0)).joined(separator: "\n")
    }
}
