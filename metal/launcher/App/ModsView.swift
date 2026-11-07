// FIFA 16 launcher: the Mods page. Everything fifamod does on the command line, with nothing to
// install: the library with a switch per mod, the switch for all of them, installing by button
// or drag and drop, a sheet per mod (parts, variants, conflicts) and per-competition scoreboards.
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ModsPage: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var mods: ModsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
            if let reason = mods.lockReason { banner(reason, "lock.fill", .secondary) }
            if mods.isPlainPatch { plainPatchBanner }
            if let state = mods.state {
                if state.hasBase, state.baseOk == false { banner("Base patch not found: \(state.base ?? ""). Is its drive connected?", "externaldrive.badge.xmark", .orange) }
                if state.missingCount > 0 { banner("\(state.missingCount) mod(s) not found in \(state.modsDir ?? ""). Is the drive connected?", "externaldrive.badge.xmark", .orange) }
            }
            Group {
                if let state = mods.state, !state.mods.isEmpty { list(state) } else { emptyState }
            }
            .opacity(model.settings.modsEnabled ? 1 : 0.5)
            .overlay {
                if mods.dropTargeted {
                    RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, lineWidth: 3).padding(6)
                }
            }
            .onDrop(of: [UTType.fileURL], isTargeted: $mods.dropTargeted) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        if let url { Task { @MainActor in mods.enqueue([url]) } }
                    }
                }
                return mods.canChange
            }
            statusLine
        }
        .onAppear(perform: mods.reload)
        .sheet(item: $mods.details) { details in ModDetailsSheet(mods: mods, details: details) }
        .sheet(item: $mods.report) { report in ReportSheet(report: report) }
        .sheet(isPresented: Binding(get: { !mods.installQueue.isEmpty }, set: { if !$0 { mods.finishInstallSheet() } })) {
            if let source = mods.installQueue.first {
                InstallSheet(mods: mods, source: source).id(source)
            }
        }
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Toggle(isOn: $model.settings.modsEnabled) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Use mods").font(.headline)
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .disabled(model.running)
            .help("Off: the game starts without any mods. Nothing is deleted. Takes effect at the next Play.")
            Spacer()
            Button(action: mods.chooseArchive) { Label("Install Mod…", systemImage: "plus") }
                .disabled(!mods.canChange)
        }
    }

    private var summary: String {
        guard model.settings.modsEnabled else { return "Off: the game starts without any mods." }
        guard let state = mods.state, !state.mods.isEmpty else { return "Optional: the game runs fine without any." }
        var text = "\(state.enabledCount) of \(state.mods.count) on"
        if let conflicts = state.conflicts, conflicts > 0 { text += " · \(conflicts) overlapping files" }
        return text
    }

    private func banner(_ text: String, _ icon: String, _ color: Color) -> some View {
        Label(text, systemImage: icon).font(.callout).foregroundStyle(color).lineLimit(2)
            .padding(.horizontal, 16).padding(.bottom, 6)
    }

    private var plainPatchBanner: some View {
        HStack {
            Label("The Mods folder is a ready-made patch: the game uses it as it is.", systemImage: "shippingbox")
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button("Add Mods on Top of It", action: mods.adoptPlainPatch).disabled(!mods.canChange)
        }
        .padding(.horizontal, 16).padding(.bottom, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "shippingbox").font(.system(size: 38)).foregroundStyle(.secondary)
            Text("No mods installed").font(.title3)
            Text("Mods are optional. To add one, drop an archive (.rar, .zip, .7z) or a mod folder here, or use Install Mod.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 380)
            Spacer()
            basePatchForm.frame(height: 150)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func list(_ state: LibraryState) -> some View {
        Form {
            Section {
                ForEach(Array(state.mods.enumerated()), id: \.element.id) { index, mod in
                    ModRow(mods: mods, mod: mod, first: index == 0, last: index == state.mods.count - 1)
                }
            } header: {
                Text("Installed mods")
            } footer: {
                Text("Where two mods change the same file, the one lower in the list wins.").font(.caption).foregroundStyle(.secondary)
            }
            ScoreboardSection(mods: mods, state: state)
            baseSection
            Section { libraryTools(state) }
        }
        .formStyle(.grouped)
    }

    private var basePatchForm: some View {
        Form { baseSection }.formStyle(.grouped).scrollDisabled(true)
    }

    private var baseSection: some View {
        Section("Base patch (optional)") {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Patch folder")
                    let base = mods.state?.base ?? ""
                    Text(base.isEmpty ? "None. A big patch such as FIP's Manual Install goes here; your mods go on top of it." : base)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.head)
                }
                Spacer()
                if mods.state?.hasBase == true { Button("Clear") { mods.setBase("") }.disabled(!mods.canChange) }
                Button("Choose…", action: mods.chooseBase).disabled(!mods.canChange)
            }
        }
    }

    private func libraryTools(_ state: LibraryState) -> some View {
        DisclosureGroup("Library tools", isExpanded: $mods.toolsOpen) {
            HStack {
                Button("Show Conflicts", action: mods.showConflicts).disabled(!mods.canChange)
                Button("Rebuild", action: mods.rebuild).disabled(!mods.canChange)
                    .help("Assembles the game's view of your mods again, after editing a mod's files by hand")
                Button("Open Mods Folder") { if let dir = mods.folderToOpen { NSWorkspace.shared.open(dir) } }
                    .disabled(mods.folderToOpen == nil)
                Button("Fix Base Patch…", action: mods.fixBase).disabled(!mods.canChange || !state.hasBase)
            }
            if let at = state.mergedAt {
                Text("Last built \(at.prefix(19).replacingOccurrences(of: "T", with: " ")). Library: \(state.store)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            }
        }
    }

    @ViewBuilder private var statusLine: some View {
        if let busy = mods.busy {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(busy).font(.callout)
                Text(mods.progress).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        } else if let error = mods.errorText {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(error).font(.callout).lineLimit(3).textSelection(.enabled)
                Spacer()
                Button("Dismiss") { mods.errorText = nil }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
    }
}

private struct ModRow: View {
    @ObservedObject var mods: ModsModel
    let mod: ModEntry
    let first: Bool
    let last: Bool

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { mod.enabled }, set: { mods.setEnabled(mod, $0) }))
                .toggleStyle(.switch).controlSize(.small).labelsHidden()
                .disabled(!mods.canChange || mod.missing)
            VStack(alignment: .leading, spacing: 1) {
                Text(mod.name).lineLimit(1).truncationMode(.middle).foregroundStyle(mod.missing ? .secondary : .primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button { mods.move(mod, "up") } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.borderless).disabled(!mods.canChange || first).help("Move up (lower priority)")
            Button { mods.move(mod, "down") } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.borderless).disabled(!mods.canChange || last).help("Move down (higher priority)")
            Button { mods.showDetails(mod) } label: { Image(systemName: "info.circle") }
                .buttonStyle(.borderless).disabled(mod.missing).help("Details: parts, variants, conflicts")
            Button { mods.remove(mod) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).disabled(!mods.canChange).help("Delete this mod")
        }
    }

    private var subtitle: String {
        if mod.missing { return "not found" }
        var parts = ["\(mod.files ?? 0) files"]
        if let clash = mod.clash, clash > 0 { parts.append("\(clash) shared with other mods") }
        if let excluded = mod.excluded, !excluded.isEmpty { parts.append("\(excluded.count) part(s) off") }
        if let installed = mod.installed, !installed.isEmpty { parts.append(installed) }
        return parts.joined(separator: " · ")
    }
}

private struct ScoreboardSection: View {
    @ObservedObject var mods: ModsModel
    let state: LibraryState

    var body: some View {
        Section {
            ForEach(state.scoreboards) { entry in
                Picker(selection: Binding(get: { entry.slug }, set: { mods.setScoreboard(comp: entry.comp, slug: $0) })) {
                    ForEach(state.mods.filter { !$0.missing }) { Text($0.name).tag($0.slug) }
                } label: {
                    HStack {
                        Text(ScoreboardEntry.title(entry.comp))
                        Button { mods.setScoreboard(comp: entry.comp, slug: nil) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).help("Back to the default scoreboard for this competition")
                    }
                }
                .disabled(!mods.canChange)
            }
            HStack {
                TextField("", text: $mods.newCompetition, prompt: Text("Competition id")).labelsHidden().frame(width: 130)
                Menu("Add for Mod") {
                    ForEach(state.mods.filter { !$0.missing }) { mod in
                        Button(mod.name) {
                            if let comp = Int(mods.newCompetition) { mods.setScoreboard(comp: comp, slug: mod.slug); mods.newCompetition = "" }
                        }
                    }
                }
                .fixedSize()
                .disabled(Int(mods.newCompetition) == nil || !mods.canChange)
                Spacer()
                let unassigned = mods.seenCompetitions.filter { id in !state.scoreboards.contains { $0.comp == id } }
                if !unassigned.isEmpty {
                    Text("Seen in your last game:").font(.caption).foregroundStyle(.secondary)
                    ForEach(unassigned.suffix(3), id: \.self) { id in
                        Button(String(id)) { mods.newCompetition = String(id) }.controlSize(.small).help(ScoreboardEntry.title(id))
                    }
                }
            }
        } header: {
            Text("Scoreboards by competition")
        } footer: {
            Text("A mod assigned here shows only in that competition, whether or not its switch is on. Play a match of a competition to see its id here. League ids need both teams in the league; cup ids always apply.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct ModDetailsSheet: View {
    @ObservedObject var mods: ModsModel
    let details: ModDetails
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section(details.name) {
                    LabeledContent("Installed", value: String(details.installed.prefix(10)))
                    if !details.source.isEmpty {
                        LabeledContent("From") { Text(details.source).lineLimit(1).truncationMode(.head).help(details.source) }
                    }
                    ForEach(details.fixes.sorted { $0.key < $1.key }, id: \.key) { fix in
                        LabeledContent("PS4 fix", value: "\(fix.key): \(fix.value)")
                    }
                    ForEach(details.notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                }
                if !details.parts.isEmpty {
                    Section("Parts") {
                        ForEach(details.parts) { part in
                            Toggle(isOn: Binding(get: { !part.excluded }, set: { mods.setPart(details, part, included: $0) })) {
                                HStack {
                                    Text(part.path).font(.system(.callout, design: .monospaced)).lineLimit(1).truncationMode(.head)
                                    Spacer()
                                    Text("\(part.files)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.switch).controlSize(.small).disabled(!mods.canChange)
                        }
                    }
                }
                if !details.variants.isEmpty {
                    Section("Variants shipped with this mod") {
                        ForEach(details.variants) { variant in
                            HStack {
                                Text(variant.file).lineLimit(1).truncationMode(.head)
                                if variant.inUse { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("In use") }
                                Spacer()
                                if variant.targets.count == 1 {
                                    Button("Use") { mods.useVariant(details, variant, target: variant.targets[0]) }
                                        .disabled(!mods.canChange).help("Replaces \(variant.targets[0])")
                                } else if !variant.targets.isEmpty {
                                    Menu("Use as") {
                                        ForEach(variant.targets, id: \.self) { t in Button(t) { mods.useVariant(details, variant, target: t) } }
                                    }
                                    .fixedSize().disabled(!mods.canChange)
                                }
                            }
                        }
                    }
                }
                if !details.conflicts.isEmpty {
                    Section("Shared files") {
                        ForEach(details.conflicts) { c in
                            LabeledContent(c.slug.replacingOccurrences(of: "_", with: " "),
                                           value: "\(c.files) files, this mod wins \(c.wins)")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button("Show in Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: details.folder)) }
                Button("Run PS4 Fixes") { mods.fix(details.slug, name: details.name) }.disabled(!mods.canChange)
                if mods.busy != nil { ProgressView().controlSize(.small) }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 620, height: 560)
    }
}

private struct InstallSheet: View {
    @ObservedObject var mods: ModsModel
    let source: URL

    private var request: ModsModel.InstallRequest {
        .init(source: source, name: mods.installName, skipOptional: !mods.installOptional)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Install \(source.lastPathComponent)").font(.headline).lineLimit(2)
            TextField("Name", text: $mods.installName, prompt: Text("Automatic"))
            Toggle("Include optional parts (folders starting with _)", isOn: $mods.installOptional)
            ScrollViewReader { proxy in
                ScrollView {
                    Text(mods.installOutput.isEmpty ? "Files are sorted into the game's folders automatically and the PS4 fixes are applied. Preview shows what would be installed without changing anything." : mods.installOutput)
                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    Color.clear.frame(height: 1).id("end")
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onChange(of: mods.installOutput) { proxy.scrollTo("end", anchor: .bottom) }
            }
            HStack {
                if mods.busy != nil { ProgressView().controlSize(.small); Text(mods.busy ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                if mods.installFinished { Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                Spacer()
                if mods.installFinished {
                    Button("Done", action: mods.finishInstallSheet).keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel") { if mods.busy != nil { mods.cancel() } else { mods.finishInstallSheet() } }
                        .keyboardShortcut(.cancelAction)
                    Button("Preview") { mods.preview(request) }.disabled(!mods.canChange)
                    Button("Install") { mods.install(request) }.disabled(!mods.canChange).keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding()
        .frame(width: 620, height: 440)
        .alert("This mod is already installed", isPresented: Binding(get: { mods.replacePrompt != nil }, set: { if !$0 { mods.replacePrompt = nil } })) {
            Button("Replace It", role: .destructive) {
                if let request = mods.replacePrompt { mods.replacePrompt = nil; mods.install(request, replace: true) }
            }
            Button("Cancel", role: .cancel) { mods.replacePrompt = nil }
        } message: {
            Text("Replace the installed copy, or cancel and give this one another name.")
        }
    }
}

private struct ReportSheet: View {
    let report: ModsModel.Report
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(report.title).font(.headline)
            ScrollView {
                Text(report.text.isEmpty ? "Nothing to report." : report.text)
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding()
        .frame(width: 640, height: 420)
    }
}
