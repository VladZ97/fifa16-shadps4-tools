// FIFA 16 launcher window: game art header, status and settings (two grouped forms, as in the
// Bloodborne port's launcher), the log page, and the Play/Stop bar.
import AppKit
import SwiftUI

struct LauncherView: View {
    static let size = CGSize(width: 900, height: 700)
    @ObservedObject var model: LauncherModel

    var body: some View {
        VStack(spacing: 0) {
            Header(model: model)
            Picker("", selection: $model.page) {
                Text("Game").tag(LauncherModel.Page.game)
                Text("Log").tag(LauncherModel.Page.log)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.top, 10)
            Group {
                switch model.page {
                case .game: gamePage
                case .log: LogPage(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            bottomBar.padding()
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    private var gamePage: some View {
        HStack(alignment: .top, spacing: 0) {
            Form {
                Section("Installation") {
                    ForEach(model.status) { item in
                        HStack {
                            StatusRow(item: item)
                            if item.action == .refreshHost {
                                Spacer()
                                Button("Refresh host", action: model.refreshHost)
                                    .disabled(!model.canRefreshHost)
                                    .help(model.canRefreshHost ? "Runs bash ~/fifa_metal/host_app/refresh.sh"
                                                               : "Not while an emulator is running: it uses these files")
                            }
                        }
                    }
                }
                Section("Patch overlay") {
                    Picker("Overlay", selection: Binding(get: { model.currentOverlay ?? "" },
                                                         set: { model.selectOverlay($0) })) {
                        if model.currentOverlay == nil { Text("None").tag("") }
                        ForEach(model.overlays, id: \.self) { Text(Overlay.label($0)).tag($0) }
                    }
                    .disabled(model.running || model.overlays.isEmpty)
                    Text("The FIP and test overlays in ~/fifa_perf/overlay. Switching re-points the Metal build's download/CUSA02138 link (asks first).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            Form {
                Section("Display") {
                    Picker("Window", selection: $model.settings.fullscreen) {
                        Text("Windowed").tag(false)
                        Text("Full screen").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Text("BB_FULLSCREEN. Full screen is run.sh's default.").font(.caption).foregroundStyle(.secondary)
                    Toggle("Low-latency presentation (display sync off)", isOn: $model.settings.lowLatency)
                        .help("BB_PRESENT_MODE=Immediate")
                    Text("Measured here: flip-to-screen 18 to 22 ms instead of 25 to 29 ms, but on a non-ProMotion display it can tear, which is why it is opt-in.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Diagnostics") {
                    Toggle("Frame stats in the log", isOn: $model.settings.frameStats)
                        .help("BB_FRAME_STATS=1: frame and latency figures every 5 s")
                    Toggle("Metal Performance HUD", isOn: $model.settings.metalHUD)
                        .help("MTL_HUD_ENABLED=1: Apple's HUD with FPS and GPU time, top right")
                    Picker("Launch mode", selection: $model.settings.mode) {
                        ForEach(RunMode.allCases) { Text($0.label).tag($0) }
                    }
                    Text(model.settings.mode == .play
                         ? "run.sh play: the emulator log keeps errors only."
                         : "run.sh start: full emulator log, plus screenshots and CPU/GPU stats every 20 s in the run folder.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Launch") {
                    LabeledContent("Command") {
                        Text(model.commandLine).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Button("Reset to run.sh Defaults", action: model.resetSettings)
                            .disabled(model.settings == LauncherSettings())
                        Spacer()
                        Button("Show settings.json", action: model.openSettingsFile)
                    }
                    Text("Settings apply at the next Play.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Folders") {
                    HStack {
                        Button("Open Run Folder", action: model.openRunFolder).disabled(model.runFolder == nil)
                        Button("All Runs", action: model.openRuns)
                        Button("Open Shader Cache", action: model.openShaderCache)
                    }
                    if let dir = model.runFolder {
                        Text(dir.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            .textSelection(.enabled).help(dir.path)
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(model.running)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if !model.others.isEmpty {
                Label("Other emulator running: pid \(model.others.map { String($0.pid) }.joined(separator: ", "))",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange).lineLimit(1)
                    .help(model.others.map { "\($0.pid) \($0.command)" }.joined(separator: "\n"))
            }
            if let message = model.message {
                Text(message).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            switch model.phase {
            case .idle:
                Button(action: model.play) { Text("Play").frame(minWidth: 90) }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .disabled(!model.canPlay)
                    .help(model.playHelp)
            case .starting:
                ProgressView().controlSize(.small)
                Text("Starting…").foregroundStyle(.secondary)
                Button(action: {}) { Text("Play").frame(minWidth: 90) }.controlSize(.large).disabled(true)
            case .running, .stopping:
                Text(model.phase == .stopping ? "Stopping…" : "Game running (pid \(model.game.map { String($0.pid) } ?? "?"))")
                    .foregroundStyle(.secondary)
                Button(action: { model.stop() }) { Label("Stop", systemImage: "stop.fill").frame(minWidth: 90) }
                    .controlSize(.large)
                    .disabled(model.phase == .stopping)
                    .help("Ends the game this launcher started. Use the game's own menus first if it is saving.")
            }
        }
    }
}

private struct Header: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let image = Header.artwork(model.paths) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: LauncherView.size.width, height: 150).clipped()
            } else {
                LinearGradient(colors: [Color(red: 0.05, green: 0.18, blue: 0.12), Color(red: 0.02, green: 0.05, blue: 0.1)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("FIFA 16").font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
                    Text("PS4 CUSA02138 · update 1.07 · shadPS4 with the native Metal renderer")
                        .font(.callout).foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                StatePill(model: model)
            }
            .padding(16)
        }
        .frame(width: LauncherView.size.width, height: 150)
    }

    private static var cached: NSImage??
    static func artwork(_ paths: Paths) -> NSImage? {
        if let cached { return cached }
        let image = Bundle.main.url(forResource: "banner", withExtension: "jpg").flatMap(NSImage.init(contentsOf:))
            ?? NSImage(contentsOf: paths.artwork)
        cached = .some(image)
        return image
    }
}

private struct StatePill: View {
    @ObservedObject var model: LauncherModel
    var body: some View {
        let (text, color): (String, Color) = switch model.phase {
        case .idle: model.problems.isEmpty ? ("Ready", .green) : ("Not ready", .red)
        case .starting: ("Starting", .yellow)
        case .running: ("Running", .green)
        case .stopping: ("Stopping", .orange)
        }
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.callout.weight(.semibold)).foregroundStyle(.white)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(.black.opacity(0.45), in: Capsule())
    }
}

private struct StatusRow: View {
    let item: StatusItem
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: item.ok ? "checkmark.circle.fill" : (item.optional ? "exclamationmark.circle.fill" : "xmark.circle.fill"))
                .foregroundStyle(item.ok ? .green : (item.optional ? .orange : .red))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                    .help(item.detail)
            }
        }
    }
}

private struct LogPage: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.logURL?.path ?? "No run yet").font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                Spacer()
                Button("Show in Finder", action: model.revealLog).disabled(model.logURL == nil)
                Button("Open Run Folder", action: model.openRunFolder).disabled(model.runFolder == nil)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    Text(model.logText.isEmpty ? "(empty: play mode logs errors only)" : model.logText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    Color.clear.frame(height: 1).id("end")
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onChange(of: model.logText) { proxy.scrollTo("end", anchor: .bottom) }
                .onAppear { proxy.scrollTo("end", anchor: .bottom) }
            }
            if !model.scriptOutput.isEmpty {
                Text("run.sh output").font(.caption.weight(.semibold))
                ScrollView {
                    Text(model.scriptOutput).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(6)
                }
                .frame(height: 90)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding()
    }
}
