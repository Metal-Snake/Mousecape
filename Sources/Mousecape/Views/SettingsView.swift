import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    @State private var scale = EnginePreferences.cursorScale ?? Engine.scale
    @State private var leftHanded = EnginePreferences.leftHanded

    var body: some View {
        Form {
            Section {
                Toggle("Apply cape at login", isOn: agentBinding)
                if model.loginAgent.needsApproval {
                    HStack {
                        Text("Allow Mousecape in Login Items to finish turning this on.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Settings") { model.loginAgent.openLoginItemsSettings() }
                    }
                }
                if let error = model.loginAgent.lastError {
                    Text(error)
                        .foregroundStyle(.red)
                }
            } footer: {
                Text("macOS forgets custom cursors when you log out. A small background agent applies your cape again at login and when displays change.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                LabeledContent("Cursor size") {
                    HStack {
                        Slider(value: $scale, in: 1...4, step: 0.25)
                        Text(scale, format: .number.precision(.fractionLength(2)))
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                Toggle("Left-handed (mirror pointers)", isOn: $leftHanded)
            }

            HistorySettings(library: model.library)
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: scale) { _, newValue in
            Engine.scale = newValue
            EnginePreferences.cursorScale = newValue
        }
        .onChange(of: leftHanded) { _, newValue in
            EnginePreferences.leftHanded = newValue
            model.reapply()
            model.library.updateProblems()      // uneven mirroring only counts in left-handed mode
        }
        .onAppear { model.loginAgent.refresh() }
    }

    private var agentBinding: Binding<Bool> {
        Binding(get: { model.loginAgent.isEnabled || model.loginAgent.needsApproval },
                set: { model.loginAgent.setEnabled($0) })
    }
}

/// How much history each cape keeps: a number of saved states, or the disk space they may
/// take. A change applies to every cape at once; what no longer fits goes to the Trash.
private struct HistorySettings: View {
    let library: Library
    @State private var usedSpace: Int64?

    private enum Kind: Hashable { case count, megabytes }

    var body: some View {
        Section {
            Picker("Keep saved states", selection: kindBinding) {
                Text("By number").tag(Kind.count)
                Text("By disk space").tag(Kind.megabytes)
            }
            switch library.historyLimit {
            case .count(let count):
                Stepper(value: countBinding(count), in: HistoryLimit.countRange) {
                    HStack {
                        Text("Per cape")
                        Spacer()
                        Text("Up to ^[\(count) state](inflect: true)").monospacedDigit()
                    }
                }
            case .megabytes(let megabytes):
                Picker("Per cape", selection: megabytesBinding(megabytes)) {
                    ForEach(HistoryLimit.megabyteChoices, id: \.self) { value in
                        Text("Up to \(value) MB").tag(value)
                    }
                }
            }
        } header: {
            Text("History")
        } footer: {
            Text(footer)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: library.historyLimit) { measure() }
    }

    private var footer: String {
        var text = String(localized: "Each save keeps the state it replaces, so that Cape → History can bring it back. The state a cape came into the library with is always kept. Older states that no longer fit go to the Trash.")
        if let usedSpace {
            text += " " + String(localized: "The history takes \(usedSpace.formatted(.byteCount(style: .file))) now.")
        }
        return text
    }

    /// Adds up the history's files away from the main thread: a big library has many.
    private func measure() {
        let history = library.history
        Task {
            let size = await Task.detached { history.totalSize() }.value
            usedSpace = size
        }
    }

    private var kindBinding: Binding<Kind> {
        Binding {
            if case .megabytes = library.historyLimit { .megabytes } else { .count }
        } set: { kind in
            library.setHistoryLimit(kind == .count ? HistoryLimit.storedCount() : HistoryLimit.storedSpace())
        }
    }

    private func countBinding(_ count: Int) -> Binding<Int> {
        Binding { count } set: { library.setHistoryLimit(.count($0)) }
    }

    private func megabytesBinding(_ megabytes: Int) -> Binding<Int> {
        Binding { megabytes } set: { library.setHistoryLimit(.megabytes($0)) }
    }
}
